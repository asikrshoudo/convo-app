import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants.dart';

/// Discord-style markdown renderer.
/// Supports:
///  Block  : ```lang code```, # h1, ## h2, ### h3,
///           > blockquote, - / * list, 1. ordered list, ---
///  Inline : **bold**, __bold__, *italic*, _italic_,
///           ~~strike~~, `code`, ||spoiler||
class MarkdownText extends StatelessWidget {
  final String text;
  final Color  textColor;
  final bool   isMe;
  final double fontSize;

  const MarkdownText({
    super.key,
    required this.text,
    required this.textColor,
    required this.isMe,
    this.fontSize = 15,
  });

  // ── Public helper: does this string contain any markdown? ─────────────────
  static bool hasMarkdown(String t) =>
    t.contains('**') || t.contains('__') ||
    t.contains('*')  || t.contains('_')  ||
    t.contains('~~') || t.contains('`')  ||
    t.contains('||') || t.contains('> ') ||
    t.startsWith('#') || t.contains('\n#') ||
    t.contains('---') ||
    RegExp(r'^[-*]\s', multiLine: true).hasMatch(t) ||
    RegExp(r'^\d+\.\s', multiLine: true).hasMatch(t);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _buildContent(raw: text, isDark: isDark);
  }

  // ── Top-level builder: split on ``` code fences first ────────────────────
  Widget _buildContent({required String raw, required bool isDark}) {
    final widgets = <Widget>[];
    final fenceRe = RegExp(r'```(\w*)\n?([\s\S]*?)```', multiLine: true);
    int last = 0;

    for (final m in fenceRe.allMatches(raw)) {
      if (m.start > last) {
        widgets.addAll(
          _textBlocks(raw.substring(last, m.start), isDark: isDark));
      }
      final lang = m.group(1)?.trim() ?? '';
      final code = (m.group(2) ?? '').trimRight();
      widgets.add(_CodeBlock(code: code, lang: lang, isMe: isMe, isDark: isDark));
      last = m.end;
    }

    if (last < raw.length) {
      widgets.addAll(_textBlocks(raw.substring(last), isDark: isDark));
    }

    if (widgets.isEmpty) {
      return Text(raw,
        style: TextStyle(
          color: textColor, fontSize: fontSize, height: 1.35));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets
        .map((w) => Padding(padding: const EdgeInsets.only(bottom: 2), child: w))
        .toList());
  }

  // ── Line-by-line block processor ─────────────────────────────────────────
  List<Widget> _textBlocks(String text, {required bool isDark}) {
    final widgets = <Widget>[];
    final lines   = text.split('\n');
    int i = 0;

    while (i < lines.length) {
      final line = lines[i];

      // Blank line → skip
      if (line.trim().isEmpty) { i++; continue; }

      // Horizontal rule
      if (RegExp(r'^-{3,}$').hasMatch(line.trim())) {
        widgets.add(Divider(
          color: (isMe ? Colors.white : kAccent).withOpacity(0.25),
          height: 14, thickness: 0.5));
        i++; continue;
      }

      // Headings  # ## ###
      final hm = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(line);
      if (hm != null) {
        final level = hm.group(1)!.length;
        final fs    = level == 1 ? 20.0 : level == 2 ? 17.0 : 15.0;
        final fw    = level == 3 ? FontWeight.w600 : FontWeight.bold;
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: fs, fontWeight: fw, height: 1.3),
              children: _inline(hm.group(2)!, isDark: isDark)))));
        i++; continue;
      }

      // Blockquote  >
      if (line.startsWith('> ') || line == '>') {
        final qLines = <String>[];
        while (i < lines.length &&
               (lines[i].startsWith('> ') || lines[i] == '>')) {
          qLines.add(lines[i].length > 2 ? lines[i].substring(2) : '');
          i++;
        }
        widgets.add(_Blockquote(
          content: qLines.join('\n'),
          isMe: isMe, isDark: isDark,
          textColor: textColor, fontSize: fontSize,
          parseInline: _inline));
        continue;
      }

      // Unordered list  - or *
      if (RegExp(r'^[-*]\s+').hasMatch(line)) {
        while (i < lines.length && RegExp(r'^[-*]\s+').hasMatch(lines[i])) {
          final item = lines[i].replaceFirst(RegExp(r'^[-*]\s+'), '');
          widgets.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• ',
                style: TextStyle(
                  color: textColor, fontSize: fontSize, height: 1.4)),
              Expanded(child: RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: fontSize, height: 1.4),
                  children: _inline(item, isDark: isDark)))),
            ]));
          i++;
        }
        continue;
      }

      // Ordered list  1. 2.
      if (RegExp(r'^\d+\.\s+').hasMatch(line)) {
        int n = 1;
        while (i < lines.length) {
          final om = RegExp(r'^\d+\.\s+(.+)$').firstMatch(lines[i]);
          if (om == null) break;
          final item = om.group(1)!;
          widgets.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$n. ',
                style: TextStyle(
                  color: textColor, fontSize: fontSize, height: 1.4)),
              Expanded(child: RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: fontSize, height: 1.4),
                  children: _inline(item, isDark: isDark)))),
            ]));
          i++; n++;
        }
        continue;
      }

      // Regular text line
      widgets.add(RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: fontSize, height: 1.35, letterSpacing: -0.1),
          children: _inline(line, isDark: isDark))));
      i++;
    }

    return widgets;
  }

  // ── Inline markdown parser ────────────────────────────────────────────────
  List<InlineSpan> _inline(String text, {required bool isDark}) {
    final re = RegExp(
      r'\*\*(.+?)\*\*|__(.+?)__|'     // bold
      r'\*(.+?)\*|_(.+?)_|'           // italic
      r'~~(.+?)~~|'                   // strikethrough
      r'\|\|(.+?)\|\||'               // ||spoiler||
      r'`(.+?)`',                     // `inline code`
      dotAll: true,
    );

    final spans = <InlineSpan>[];
    int last = 0;

    void plain(String s) {
      if (s.isEmpty) return;
      spans.add(TextSpan(text: s, style: TextStyle(color: textColor)));
    }

    for (final m in re.allMatches(text)) {
      plain(text.substring(last, m.start));

      final bold   = m.group(1) ?? m.group(2);
      final italic = m.group(3) ?? m.group(4);
      final strike = m.group(5);
      final spoil  = m.group(6);
      final code   = m.group(7);

      if (bold != null) {
        spans.add(TextSpan(text: bold,
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold)));
      } else if (italic != null) {
        spans.add(TextSpan(text: italic,
          style: TextStyle(color: textColor, fontStyle: FontStyle.italic)));
      } else if (strike != null) {
        spans.add(TextSpan(text: strike,
          style: TextStyle(
            color: textColor.withOpacity(0.5),
            decoration: TextDecoration.lineThrough,
            decorationColor: textColor.withOpacity(0.5))));
      } else if (spoil != null) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _Spoiler(
            text: spoil, textColor: textColor, fontSize: fontSize)));
      } else if (code != null) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(isMe ? 0.25 : 0.08),
              borderRadius: BorderRadius.circular(4)),
            child: Text(code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: fontSize - 1,
                color: isMe
                  ? Colors.white.withOpacity(0.9)
                  : isDark
                    ? const Color(0xFFE06C75)
                    : const Color(0xFFD6546B))))));
      }
      last = m.end;
    }

    plain(text.substring(last));

    return spans.isEmpty
      ? [TextSpan(text: text, style: TextStyle(color: textColor))]
      : spans;
  }
}

// ── Spoiler widget ────────────────────────────────────────────────────────────
class _Spoiler extends StatefulWidget {
  final String text;
  final Color  textColor;
  final double fontSize;
  const _Spoiler({
    required this.text,
    required this.textColor,
    required this.fontSize});

  @override
  State<_Spoiler> createState() => _SpoilerState();
}

class _SpoilerState extends State<_Spoiler> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _shown = !_shown),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: _shown
            ? Colors.transparent
            : widget.textColor.withOpacity(0.75),
          borderRadius: BorderRadius.circular(3)),
        child: Text(widget.text,
          style: TextStyle(
            fontSize: widget.fontSize,
            color: _shown ? widget.textColor : Colors.transparent))));
  }
}

// ── Blockquote widget ─────────────────────────────────────────────────────────
class _Blockquote extends StatelessWidget {
  final String content;
  final bool   isMe, isDark;
  final Color  textColor;
  final double fontSize;
  final List<InlineSpan> Function(String, {required bool isDark}) parseInline;

  const _Blockquote({
    required this.content,
    required this.isMe,
    required this.isDark,
    required this.textColor,
    required this.fontSize,
    required this.parseInline});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(isMe ? 0.15 : 0.05),
      border: Border(left: BorderSide(
        color: (isMe ? Colors.white : kAccent).withOpacity(0.45),
        width: 3))),
    child: RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: fontSize, height: 1.35,
          fontStyle: FontStyle.italic),
        children: parseInline(content, isDark: isDark))));
}

// ── Discord-style code block ──────────────────────────────────────────────────
class _CodeBlock extends StatefulWidget {
  final String code, lang;
  final bool   isMe, isDark;
  const _CodeBlock({
    required this.code,
    required this.lang,
    required this.isMe,
    required this.isDark});

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2),
      () { if (mounted) setState(() => _copied = false); });
  }

  @override
  Widget build(BuildContext context) {
    final bg          = Colors.black.withOpacity(widget.isMe ? 0.28 : 0.09);
    final borderColor = (widget.isMe ? Colors.white : kAccent).withOpacity(0.13);
    final codeColor   = widget.isMe
      ? Colors.white.withOpacity(0.88)
      : widget.isDark
        ? const Color(0xFFABB2BF)
        : const Color(0xFF383A42);
    final mutedColor  = widget.isMe
      ? Colors.white.withOpacity(0.45)
      : widget.isDark ? kTextSecondary : kLightTextSub;

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 0.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Header bar: lang + copy ─────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(
                color: borderColor, width: 0.5))),
            child: Row(children: [
              if (widget.lang.isNotEmpty)
                Text(widget.lang,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: mutedColor)),
              const Spacer(),
              GestureDetector(
                onTap: _copy,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _copied
                    ? Row(key: const ValueKey('d'), children: [
                        Icon(Icons.check_rounded,
                          size: 13, color: mutedColor),
                        const SizedBox(width: 4),
                        Text('Copied!',
                          style: TextStyle(fontSize: 11, color: mutedColor)),
                      ])
                    : Row(key: const ValueKey('c'), children: [
                        Icon(Icons.copy_rounded,
                          size: 13, color: mutedColor),
                        const SizedBox(width: 4),
                        Text('Copy',
                          style: TextStyle(fontSize: 11, color: mutedColor)),
                      ]))),
            ])),

          // ── Code content ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              widget.code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: codeColor,
                height: 1.55))),
        ]));
  }
}
