"""Writes the release note for a push build of main.

Collects the PRs merged since the last published release of this repository,
and the upstream releases those merges brought in, then has a model write the
note in upstream's style. Falls back to a plain list of PR titles when the
model can't be reached, so a release never waits on it.

Env: GH_TOKEN, GITHUB_REPOSITORY, UPSTREAM, OPENROUTER_API_KEY (optional),
RELEASE_NOTE_MODEL. Usage: release_note.py <out file>
"""

import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

REPO = os.environ['GITHUB_REPOSITORY']
UPSTREAM = os.environ.get('UPSTREAM', 'bggRGjQaUbCoE/PiliPlus')
MODEL = os.environ.get('RELEASE_NOTE_MODEL') or 'deepseek/deepseek-v4.1-flash'
OWNER = REPO.split('/')[0]
UPSTREAM_OWNER = UPSTREAM.split('/')[0]


def run(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True).stdout.strip()


def gh_api(path):
    """The response, or None for a 404. Any other failure is retried, then
    raised: a note quietly missing PRs would never get them back, since the
    next release starts from this one."""
    for attempt in range(3):
        res = subprocess.run(['gh', 'api', path], capture_output=True, text=True)
        if res.returncode == 0:
            return json.loads(res.stdout)
        if 'HTTP 404' in res.stderr:
            return None
        print(f'::warning::gh api {path} failed (try {attempt + 1}): {res.stderr.strip()}')
        time.sleep(5 * (attempt + 1))
    raise RuntimeError(f'gh api {path} kept failing')


def upstream_tags_in(rev, exclude=None):
    """Upstream release tags reachable from rev, minus those reachable from exclude."""
    args = ['git', 'tag', '--merged', rev]
    if exclude:
        args += ['--no-merged', exclude]
    return [t for t in run(*args).splitlines() if re.fullmatch(r'[\d.]+', t)]


def collect():
    run('git', 'fetch', '-q', '--force', f'https://github.com/{UPSTREAM}.git', 'refs/tags/*:refs/tags/*')
    latest = gh_api(f'repos/{REPO}/releases/latest')
    base = latest['tag_name'] if latest else None
    if base:
        run('git', 'fetch', '-q', '--force', 'origin', f'refs/tags/{base}:refs/tags/{base}')
    else:
        # The first release: start from the newest upstream release in main.
        tags = sorted(upstream_tags_in('HEAD'), key=lambda t: [int(x) for x in t.split('.')])
        base = tags[-1] if tags else None
    span = f'{base}..HEAD' if base else 'HEAD'

    prs = {}
    for sha in run('git', 'rev-list', '--first-parent', span).splitlines():
        for pr in gh_api(f'repos/{REPO}/commits/{sha}/pulls') or []:
            if pr.get('merged_at') and pr['base']['ref'] == 'main':
                prs.setdefault(pr['number'], pr)
                break
    upstream = []
    for tag in upstream_tags_in('HEAD', base):
        rel = gh_api(f'repos/{UPSTREAM}/releases/tags/{tag}')
        if rel and rel.get('body'):
            upstream.append((tag, rel['body'].strip()))
    upstream.sort(key=lambda r: [int(x) for x in r[0].split('.')])
    # Only a base that is one of our releases can be compared with this one.
    release = base if latest else None
    return base, sorted(prs.values(), key=lambda p: p['number']), upstream, release


def fallback(prs):
    return '\n'.join(f"{p['title']} #{p['number']}" for p in prs)


def compose(own, upstream):
    """This repository's lines, then each upstream release's note verbatim:
    appended here, not left to the model, so none goes missing or reworded."""
    parts = [own] if own else []
    parts += [f'同步上游 {tag}\n{body}' for tag, body in upstream]
    return '\n\n'.join(parts) or '其他调整'


def is_sync(pr):
    return pr['title'].startswith('chore: merge upstream')


def ask_model(prs, examples):
    key = os.environ.get('OPENROUTER_API_KEY')
    if not key:
        return None
    system = (
        '你为 PiliPlus（第三方哔哩哔哩客户端）的一个 fork 写版本更新说明。只输出更新说明正文，'
        '不要标题、前言、总结或代码块。\n'
        '风格照下面的上游历史说明：简体中文，一行一条，短句，从用户视角写能看到的变化，不写实现细节；'
        '先写新功能和调整，空一行后以「修复 bug」开头列修复；每条末尾写对应 PR 的 #编号；'
        f'PR 作者是 @{OWNER} 时不署名，其他作者在末尾加 by @用户名；'
        'CI、文档、测试、纯重构等用户看不到的改动省略。\n\n'
        '上游历史说明示例：\n' + examples
    )
    parts = ['## 这一版合并的 PR']
    for p in prs:
        body = (p.get('body') or '').strip()[:4000]
        parts.append(f"### #{p['number']} {p['title']}（作者 @{p['user']['login']}）\n{body}")
    req = urllib.request.Request(
        'https://openrouter.ai/api/v1/chat/completions',
        json.dumps({
            'model': MODEL,
            'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': '根据下面的内容写这一版的更新说明。\n\n' + '\n\n'.join(parts)},
            ],
        }).encode(),
        {'Authorization': f'Bearer {key}', 'Content-Type': 'application/json'},
    )
    for attempt in range(2):
        try:
            res = json.load(urllib.request.urlopen(req, timeout=180))
            text = res['choices'][0]['message'].get('content')
            if isinstance(text, str):
                text = re.sub(r'^```\w*\n|\n```$', '', text.strip()).strip()
                if text:
                    return text
            print(f'::warning::release note model returned no text (try {attempt + 1})')
        # Whatever goes wrong with the model, the PR titles still make a note.
        except Exception as e:  # noqa: BLE001

            print(f'::warning::release note model failed (try {attempt + 1}): {e}')
    return None


def main():
    base, prs, upstream, release = collect()
    # The release this note starts from, for the update dialog's link to this
    # version's commits (release_manifest.ps1 gets it as PREVIOUS_TAG).
    if output := os.environ.get('GITHUB_OUTPUT'):
        with open(output, 'a', encoding='utf-8') as f:
            f.write(f'base={release or ""}\n')
    print(f'since {base}: PRs {[p["number"] for p in prs]}, upstream {[t for t, _ in upstream]}')
    examples = []
    for rel in (gh_api(f'repos/{UPSTREAM}/releases?per_page=3') or []):
        if rel.get('body'):
            examples.append(f"### {rel['tag_name']}\n{rel['body'].strip()}")
    # Syncs only bring upstream's changes in, which compose() adds as they are.
    own = [p for p in prs if not is_sync(p)]
    own_note = (ask_model(own, '\n\n'.join(examples)) or fallback(own)) if own else ''
    note = compose(own_note, upstream)
    with open(sys.argv[1], 'w', encoding='utf-8') as f:
        f.write(note + '\n')
    print(note)


if __name__ == '__main__':
    main()
