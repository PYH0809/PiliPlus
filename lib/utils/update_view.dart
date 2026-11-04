import 'package:material_ui/material_ui.dart';

// 更新对话框的排版：发版说明按段落分组，元信息和链接都退到次要的灰色小字

// 发版说明里的一段：可能有个小标题（如「修复 bug」），下面是一条条改动
class NoteSection {
  final String? title;
  final List<NoteEntry> entries;

  const NoteSection(this.title, this.entries);
}

// 一条改动；refs 是行尾的 PR 号（#77）
class NoteEntry {
  final String text;
  final List<String> refs;

  const NoteEntry(this.text, [this.refs = const []]);
}

abstract final class ReleaseNote {
  static final _refs = RegExp(r'(?:\s+#\d+)+$');
  static final _bullet = RegExp(r'^\s*[-*•]\s+');
  static final _heading = RegExp(r'^#{1,6}\s+');

  // release_note.py 写的说明是一行一条，段落之间空一行，段首可能有一行
  // 小标题；上游的说明照抄，可能带 Markdown 的标题和列表符号
  static List<NoteSection> parse(String body) {
    final sections = <NoteSection>[];
    for (final group in body.trim().split(RegExp(r'\n\s*\n'))) {
      final lines = [
        for (final line in group.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];
      if (lines.isEmpty) continue;
      String? title;
      final first = lines.first;
      if (_heading.hasMatch(first)) {
        title = first.replaceFirst(_heading, '');
        lines.removeAt(0);
      } else if (lines.length > 1 &&
          !_refs.hasMatch(first) &&
          !_bullet.hasMatch(first) &&
          first.length <= 16) {
        title = first;
        lines.removeAt(0);
      }
      sections.add(
        NoteSection(title, [for (final line in lines) _entry(line)]),
      );
    }
    return sections;
  }

  static NoteEntry _entry(String line) {
    var text = line.replaceFirst(_bullet, '').replaceAll('`', '');
    final refs = <String>[];
    if (_refs.firstMatch(text) case final match?) {
      refs.addAll(match[0]!.trim().split(RegExp(r'\s+')));
      text = text.substring(0, match.start);
    }
    return NoteEntry(text.trim(), refs);
  }
}

class ReleaseNoteView extends StatelessWidget {
  const ReleaseNoteView({super.key, required this.sections});

  final List<NoteSection> sections;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final text = TextStyle(
      fontSize: 14,
      height: 20 / 14,
      color: colorScheme.onSurface,
    );
    final muted = text.copyWith(fontSize: 12, color: colorScheme.outline);
    return Column(
      crossAxisAlignment: .start,
      children: [
        for (final (index, section) in sections.indexed) ...[
          if (index > 0) const SizedBox(height: 14),
          if (section.title case final title?)
            Padding(
              padding: const .only(bottom: 6),
              child: Text(
                title,
                // 和正文同一个颜色，层级只靠字号和字重
                style: text.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          for (final (i, entry) in section.entries.indexed)
            Padding(
              padding: .only(top: i == 0 ? 0 : 6),
              child: Row(
                crossAxisAlignment: .start,
                children: [
                  // 圆点和首行文字居中对齐
                  Padding(
                    padding: const .fromLTRB(2, 8, 8, 0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: muted.color,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox.square(dimension: 4),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: entry.text,
                        children: [
                          if (entry.refs.isNotEmpty)
                            TextSpan(
                              text: '  ${entry.refs.join(' ')}',
                              style: muted,
                            ),
                        ],
                      ),
                      style: text,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

// 对话框里的次要链接：小号、灰色、没有水波纹
class DialogLink extends StatelessWidget {
  const DialogLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.onSurfaceVariant,
        textStyle: const TextStyle(fontSize: 13),
        padding: const .symmetric(horizontal: 4),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        splashFactory: NoSplash.splashFactory,
        overlayColor: Colors.transparent,
      ),
      child: Text(label),
    );
  }
}

// 「2.2.0+6132 · 24.5 MB · 11月4日」
String updateMeta(String tag, {int? size, DateTime? date}) => [
  tag,
  if (size != null) '${(size / 1048576).toStringAsFixed(1)} MB',
  if (date != null) '${date.month}月${date.day}日',
].join(' · ');

// 能滚的区域底部渐隐，提示下面还有；滚到底就不隐了
class FadingScroll extends StatefulWidget {
  const FadingScroll({super.key, required this.child});

  final Widget child;

  @override
  State<FadingScroll> createState() => _FadingScrollState();
}

class _FadingScrollState extends State<FadingScroll> {
  final _controller = ScrollController();
  bool _more = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final more = position.extentAfter > 1;
    if (more != _more) setState(() => _more = more);
  }

  @override
  Widget build(BuildContext context) {
    final scroll = Scrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        controller: _controller,
        child: widget.child,
      ),
    );
    // 一直套着，免得开关时滚动位置跟着子树重建丢掉
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black,
          Colors.black,
          _more ? Colors.transparent : Colors.black,
        ],
        stops: [0, 1 - 32 / rect.height.clamp(32, double.infinity), 1],
      ).createShader(rect),
      child: scroll,
    );
  }
}
