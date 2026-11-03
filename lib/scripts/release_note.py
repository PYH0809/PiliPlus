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
    try:
        return json.loads(run('gh', 'api', path))
    except subprocess.CalledProcessError:
        return None


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
    return base, sorted(prs.values(), key=lambda p: p['number']), upstream


def fallback(prs, upstream):
    lines = [f"{p['title']} #{p['number']}" for p in prs if not is_sync(p)]
    for tag, body in upstream:
        lines += ['', f'同步上游 {tag}', body]
    return '\n'.join(lines).strip() or '其他调整'


def is_sync(pr):
    return pr['title'].startswith('chore: merge upstream')


def ask_model(prs, upstream, examples):
    key = os.environ.get('OPENROUTER_API_KEY')
    if not key:
        return None
    system = (
        '你为 PiliPlus（第三方哔哩哔哩客户端）的一个 fork 写版本更新说明。只输出更新说明正文，'
        '不要标题、前言、总结或代码块。\n'
        '风格照下面的上游历史说明：简体中文，一行一条，短句，从用户视角写能看到的变化，不写实现细节；'
        '先写新功能和调整，空一行后以「修复 bug」开头列修复；每条末尾写对应 PR 的 #编号；'
        f'PR 作者是 @{OWNER} 时不署名，其他作者在末尾加 by @用户名；'
        'CI、文档、测试、纯重构等用户看不到的改动省略；「chore: merge upstream」开头的 PR 只是同步上游，本身不单列。\n'
        '如果给了上游版本的更新说明，把它们放在最后：每个版本空一行，先写一行「同步上游 <版本号>」，'
        '再原样照抄该版本的说明，不改写、不删条目。\n\n'
        '上游历史说明示例：\n' + examples
    )
    parts = ['## 这一版合并的 PR']
    for p in prs:
        body = (p.get('body') or '').strip()[:4000]
        parts.append(f"### #{p['number']} {p['title']}（作者 @{p['user']['login']}）\n{body}")
    if upstream:
        parts.append('## 同步进来的上游版本')
        parts += [f'### {tag}\n{body}' for tag, body in upstream]
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
            text = res['choices'][0]['message']['content'].strip()
            text = re.sub(r'^```\w*\n|\n```$', '', text).strip()
            if text:
                return text
        except (urllib.error.URLError, TimeoutError, KeyError, IndexError, ValueError) as e:
            print(f'::warning::release note model failed (try {attempt + 1}): {e}')
    return None


def main():
    base, prs, upstream = collect()
    print(f'since {base}: PRs {[p["number"] for p in prs]}, upstream {[t for t, _ in upstream]}')
    examples = []
    for rel in (gh_api(f'repos/{UPSTREAM}/releases?per_page=3') or []):
        if rel.get('body'):
            examples.append(f"### {rel['tag_name']}\n{rel['body'].strip()}")
    note = ask_model(prs, upstream, '\n\n'.join(examples)) or fallback(prs, upstream)
    with open(sys.argv[1], 'w', encoding='utf-8') as f:
        f.write(note + '\n')
    print(note)


if __name__ == '__main__':
    main()
