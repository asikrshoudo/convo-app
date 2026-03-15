import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../core/constants.dart';

// ── URL detection ─────────────────────────────────────────────────────────────
final _urlRegex = RegExp(
  r"""https?://[^\s\)\]\>"']+""",
  caseSensitive: false,
);

String? extractFirstUrl(String text) =>
    _urlRegex.firstMatch(text)?.group(0);

bool hasUrl(String text) => _urlRegex.hasMatch(text);

// ── URL type helpers ──────────────────────────────────────────────────────────

bool _isDirectImage(String url) {
  final u = url.toLowerCase().split('?').first;
  return u.endsWith('.jpg')  || u.endsWith('.jpeg') ||
         u.endsWith('.png')  || u.endsWith('.gif')  ||
         u.endsWith('.webp') || u.endsWith('.bmp');
}

bool _isDirectVideo(String url) {
  final u = url.toLowerCase().split('?').first;
  return u.endsWith('.mp4') || u.endsWith('.webm') || u.endsWith('.mov');
}

String? _youtubeId(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  if (uri.host.contains('youtube.com')) return uri.queryParameters['v'];
  if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty)
    return uri.pathSegments.first;
  return null;
}

// ── Metadata model ────────────────────────────────────────────────────────────
class LinkMeta {
  final String  url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  const LinkMeta({
    required this.url,
    this.title, this.description, this.imageUrl, this.siteName,
  });
}

// ── In-memory cache ───────────────────────────────────────────────────────────
final _cache = <String, LinkMeta?>{};

Future<LinkMeta?> fetchLinkMeta(String url) async {
  if (_cache.containsKey(url)) return _cache[url];
  try {
    final uri  = Uri.parse(url);
    final resp = await http.get(uri, headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Accept':          'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.5',
      'Accept-Encoding': 'identity',
    }).timeout(const Duration(seconds: 8));

    if (resp.statusCode != 200) { _cache[url] = null; return null; }
    final body = resp.body;

    String? og(String prop) {
      for (final re in [
        RegExp('<meta[^>]+property=["\']og:$prop["\'][^>]+content=["\']([^"\']+)["\']',
            caseSensitive: false, dotAll: true),
        RegExp('<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']og:$prop["\']',
            caseSensitive: false, dotAll: true),
      ]) {
        final m = re.firstMatch(body);
        if (m != null) return _html(m.group(1)!.trim());
      }
      return null;
    }

    String? mt(String name) {
      for (final re in [
        RegExp('<meta[^>]+name=["\']$name["\'][^>]+content=["\']([^"\']+)["\']',
            caseSensitive: false, dotAll: true),
        RegExp('<meta[^>]+content=["\']([^"\']+)["\'][^>]+name=["\']$name["\']',
            caseSensitive: false, dotAll: true),
      ]) {
        final m = re.firstMatch(body);
        if (m != null) return _html(m.group(1)!.trim());
      }
      return null;
    }

    String? titleTag() {
      final m = RegExp(r'<title[^>]*>([^<]+)</title>',
          caseSensitive: false).firstMatch(body);
      return m != null ? _html(m.group(1)!.trim()) : null;
    }

    final title       = og('title')       ?? mt('twitter:title')       ?? titleTag();
    final description = og('description') ?? mt('description')         ?? mt('twitter:description');
    var   imageUrl    = og('image')       ?? mt('twitter:image');
    final siteName    = og('site_name')   ?? uri.host.replaceFirst('www.', '');

    if (imageUrl != null && imageUrl.isNotEmpty && !imageUrl.startsWith('http'))
      imageUrl = '${uri.scheme}://${uri.host}$imageUrl';

    final result = LinkMeta(url: url, title: title, description: description,
        imageUrl: imageUrl, siteName: siteName);
    _cache[url] = result;
    return result;
  } catch (_) {
    _cache[url] = null;
    return null;
  }
}

String _html(String s) => s
    .replaceAll('&amp;',  '&').replaceAll('&lt;',   '<')
    .replaceAll('&gt;',   '>').replaceAll('&quot;', '"')
    .replaceAll('&#39;',  "'").replaceAll('&apos;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });

// ── LinkPreviewCard — dispatches to correct embed type ────────────────────────
class LinkPreviewCard extends StatefulWidget {
  final String url;
  final bool   isMe;
  const LinkPreviewCard({super.key, required this.url, required this.isMe});

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  LinkMeta? _meta;
  bool _loading = true;
  bool _failed  = false;

  @override
  void initState() {
    super.initState();
    // Direct media and YouTube don't need OG fetch
    if (_isDirectImage(widget.url) || _isDirectVideo(widget.url) ||
        _youtubeId(widget.url) != null) {
      _loading = false;
      return;
    }
    if (_cache.containsKey(widget.url)) {
      _meta    = _cache[widget.url];
      _loading = false;
      _failed  = _meta == null;
    } else {
      fetchLinkMeta(widget.url).then((m) {
        if (!mounted) return;
        setState(() { _meta = m; _loading = false; _failed = m == null; });
      });
    }
  }

  void _open() => launchUrl(Uri.parse(widget.url),
      mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {

    // ── 1. Direct image ───────────────────────────────────────────────────
    if (_isDirectImage(widget.url))
      return _ImageEmbed(url: widget.url, isMe: widget.isMe, onTap: _open);

    // ── 2. YouTube ────────────────────────────────────────────────────────
    final ytId = _youtubeId(widget.url);
    if (ytId != null)
      return _YouTubeEmbed(videoId: ytId, isMe: widget.isMe, onTap: _open);

    // ── 3. Direct video ───────────────────────────────────────────────────
    if (_isDirectVideo(widget.url))
      return _VideoLinkCard(url: widget.url, isMe: widget.isMe, onTap: _open);

    // ── 4. Loading skeleton ───────────────────────────────────────────────
    if (_loading) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        height: 60,
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: widget.isMe
              ? Colors.white.withOpacity(0.1)
              : isDark ? kCard2 : kLightCard2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.isMe
                ? Colors.white.withOpacity(0.15)
                : isDark ? kDivider : kLightDivider, width: 0.5)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Icon(Icons.link_rounded, size: 16,
              color: widget.isMe ? Colors.white38
                  : isDark ? kTextSecondary : kLightTextSub),
            const SizedBox(width: 8),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment:  MainAxisAlignment.center,
              children: [
                Container(height: 9, width: 120,
                  decoration: BoxDecoration(
                    color: (widget.isMe ? Colors.white : kAccent).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 6),
                Container(height: 7, width: 80,
                  decoration: BoxDecoration(
                    color: (widget.isMe ? Colors.white : kAccent).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(4))),
              ])),
          ])));
    }

    // ── 5. Fallback chip ──────────────────────────────────────────────────
    if (_failed || _meta == null ||
        (_meta!.title == null && _meta!.imageUrl == null)) {
      return GestureDetector(
        onTap: _open,
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: widget.isMe
                ? Colors.white.withOpacity(0.12)
                : isDark ? kCard2 : kLightCard2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isMe
                  ? Colors.white.withOpacity(0.18)
                  : isDark ? kDivider : kLightDivider, width: 0.5)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.link_rounded, size: 13,
              color: widget.isMe ? Colors.white70 : kAccent),
            const SizedBox(width: 6),
            Flexible(child: Text(
              Uri.parse(widget.url).host.replaceFirst('www.', ''),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: widget.isMe ? Colors.white70 : kAccent,
                decoration: TextDecoration.underline,
                decorationColor: widget.isMe ? Colors.white70 : kAccent))),
          ])));
    }

    // ── 6. Full OG card ───────────────────────────────────────────────────
    final m         = _meta!;
    final cardBg    = widget.isMe
        ? Colors.white.withOpacity(0.11) : isDark ? kCard2 : kLightCard2;
    final border    = widget.isMe
        ? Colors.white.withOpacity(0.18) : isDark ? kDivider : kLightDivider;
    final titleCol  = widget.isMe ? Colors.white
        : isDark ? kTextPrimary : kLightText;
    final subCol    = widget.isMe ? Colors.white60
        : isDark ? kTextSecondary : kLightTextSub;
    final siteCol   = widget.isMe ? Colors.white54 : kAccent;
    final accentBar = kAccent.withOpacity(widget.isMe ? 0.6 : 0.85);

    return GestureDetector(
      onTap: _open,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 0.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (m.imageUrl != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.network(
                m.imageUrl!,
                height: 140, width: double.infinity, fit: BoxFit.cover,
                loadingBuilder: (_, child, prog) => prog == null ? child
                    : Container(height: 60,
                        color: (widget.isMe ? Colors.white : kAccent).withOpacity(0.06),
                        child: const Center(child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: kAccent))),
                errorBuilder: (_, __, ___) => const SizedBox.shrink())),

          Padding(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 3,
                constraints: const BoxConstraints(minHeight: 28),
                margin: const EdgeInsets.only(right: 8, top: 1),
                decoration: BoxDecoration(
                  color: accentBar, borderRadius: BorderRadius.circular(2))),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (m.siteName != null && m.siteName!.isNotEmpty)
                    Text(m.siteName!.toUpperCase(),
                      style: TextStyle(fontSize: 10, letterSpacing: 0.6,
                        fontWeight: FontWeight.w700, color: siteCol)),
                  if (m.title != null) ...[
                    if (m.siteName != null) const SizedBox(height: 2),
                    Text(m.title!, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        height: 1.3, color: titleCol)),
                  ],
                  if (m.description != null) ...[
                    const SizedBox(height: 4),
                    Text(m.description!, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, height: 1.4, color: subCol)),
                  ],
                ])),
            ])),
        ])));
  }
}

// ── Direct image embed ────────────────────────────────────────────────────────
class _ImageEmbed extends StatelessWidget {
  final String url;
  final bool   isMe;
  final VoidCallback onTap;
  const _ImageEmbed({required this.url, required this.isMe, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        constraints: const BoxConstraints(maxWidth: 260, maxHeight: 300),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8, offset: const Offset(0, 2))]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            url, fit: BoxFit.cover,
            loadingBuilder: (_, child, prog) => prog == null ? child
                : Container(
                    width: 200, height: 140,
                    color: kAccent.withOpacity(0.08),
                    child: const Center(child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: kAccent))),
            errorBuilder: (_, __, ___) => const SizedBox.shrink()))));
  }
}

// ── YouTube embed ─────────────────────────────────────────────────────────────
class _YouTubeEmbed extends StatelessWidget {
  final String videoId;
  final bool   isMe;
  final VoidCallback onTap;
  const _YouTubeEmbed({required this.videoId, required this.isMe, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final thumb = 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10, offset: const Offset(0, 3))]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(children: [

            // Thumbnail
            Image.network(
              thumb,
              width: double.infinity, height: 158, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 158, color: Colors.black87,
                child: const Center(child: Icon(
                  Icons.play_circle_outline_rounded,
                  color: Colors.white38, size: 48)))),

            // Gradient overlay
            Positioned.fill(child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.6)])))),

            // Play button
            Positioned.fill(child: Center(
              child: Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF0000),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(0.45), blurRadius: 14)]),
                child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 30)))),

            // YouTube label
            Positioned(
              left: 10, bottom: 8,
              child: Row(children: [
                const Icon(Icons.smart_display_rounded,
                  color: Color(0xFFFF0000), size: 14),
                const SizedBox(width: 4),
                const Text('YouTube',
                  style: TextStyle(
                    color: Colors.white, fontSize: 11,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
              ])),
          ]))));
  }
}

// ── Direct video link card ────────────────────────────────────────────────────
class _VideoLinkCard extends StatelessWidget {
  final String url;
  final bool   isMe;
  final VoidCallback onTap;
  const _VideoLinkCard({required this.url, required this.isMe, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final host   = Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? '';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 240),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.white.withOpacity(0.12)
              : isDark ? kCard2 : kLightCard2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isMe
                ? Colors.white.withOpacity(0.18)
                : isDark ? kDivider : kLightDivider, width: 0.5)),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: kAccent.withOpacity(0.15), shape: BoxShape.circle),
            child: const Icon(Icons.play_circle_outline_rounded,
              color: kAccent, size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Video',
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: isMe ? Colors.white : isDark ? kTextPrimary : kLightText)),
              Text(host, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11,
                  color: isMe ? Colors.white60 : kAccent)),
            ])),
          Icon(Icons.open_in_new_rounded, size: 14,
            color: isMe ? Colors.white38 : isDark ? kTextTertiary : kLightTextSub),
        ])));
  }
}
