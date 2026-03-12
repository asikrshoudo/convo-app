import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../core/constants.dart';

// ── URL Detection ────────────────────────────────────────────────────────────
final _urlRegex = RegExp(
  r'https?://[^\s]+',
  caseSensitive: false,
);

String? extractFirstUrl(String text) {
  final match = _urlRegex.firstMatch(text);
  return match?.group(0);
}

// ── Link Metadata ─────────────────────────────────────────────────────────────
class LinkMeta {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  const LinkMeta({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
  });
}

Future<LinkMeta?> fetchLinkMeta(String url) async {
  try {
    final resp = await http.get(
      Uri.parse(url),
      headers: {'User-Agent': 'Mozilla/5.0 (compatible; ConvoBot/1.0)'},
    ).timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) return null;
    final body = resp.body;

    String? _og(String prop) {
      final r = RegExp(
        '<meta[^>]*property=["\']og:$prop["\'][^>]*content=["\']([^"\']+)["\']',
        caseSensitive: false);
      final r2 = RegExp(
        '<meta[^>]*content=["\']([^"\']+)["\'][^>]*property=["\']og:$prop["\']',
        caseSensitive: false);
      return r.firstMatch(body)?.group(1) ?? r2.firstMatch(body)?.group(1);
    }

    String? _meta(String name) {
      final r = RegExp(
        '<meta[^>]*name=["\']$name["\'][^>]*content=["\']([^"\']+)["\']',
        caseSensitive: false);
      return r.firstMatch(body)?.group(1);
    }

    String? _title() {
      final r = RegExp('<title>([^<]+)</title>', caseSensitive: false);
      return r.firstMatch(body)?.group(1)?.trim();
    }

    final title       = _og('title')       ?? _title();
    final description = _og('description') ?? _meta('description');
    final image       = _og('image');
    final siteName    = _og('site_name')   ?? Uri.parse(url).host;

    return LinkMeta(
      url: url,
      title: title,
      description: description,
      imageUrl: image,
      siteName: siteName,
    );
  } catch (_) {
    return null;
  }
}

// ── Link Preview Widget ───────────────────────────────────────────────────────
class LinkPreviewCard extends StatefulWidget {
  final String url;
  final bool isMe;
  const LinkPreviewCard({super.key, required this.url, required this.isMe});

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;
  LinkMeta? _meta;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    fetchLinkMeta(widget.url).then((m) {
      if (mounted) setState(() { _meta = m; _loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        width: 220,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: widget.isMe
            ? Colors.white.withOpacity(0.12)
            : isDark ? kCard2 : kLightCard2,
          borderRadius: BorderRadius.circular(10)),
        child: const SizedBox(
          height: 12,
          child: LinearProgressIndicator(
            color: kAccent, backgroundColor: Colors.transparent)));
    }

    if (_meta == null || (_meta!.title == null && _meta!.imageUrl == null)) {
      // Fallback: just a tappable URL chip
      return GestureDetector(
        onTap: () => launchUrl(Uri.parse(widget.url),
          mode: LaunchMode.externalApplication),
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: widget.isMe
              ? Colors.white.withOpacity(0.15)
              : isDark ? kCard2 : kLightCard2,
            borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.link_rounded, size: 13,
              color: widget.isMe ? Colors.white70 : kAccent),
            const SizedBox(width: 5),
            Flexible(child: Text(
              Uri.parse(widget.url).host,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: widget.isMe ? Colors.white70 : kAccent,
                decoration: TextDecoration.underline))),
          ])));
    }

    final m = _meta!;
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(widget.url),
        mode: LaunchMode.externalApplication),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: widget.isMe
            ? Colors.white.withOpacity(0.12)
            : isDark ? kCard2 : kLightCard2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isMe
              ? Colors.white.withOpacity(0.2)
              : isDark ? kDivider : kLightDivider,
            width: 0.5)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            if (m.imageUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12)),
                child: Image.network(
                  m.imageUrl!,
                  height: 130, width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox())),

            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Site name
                  if (m.siteName != null)
                    Text(m.siteName!.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10, letterSpacing: 0.5,
                        fontWeight: FontWeight.w700,
                        color: widget.isMe ? Colors.white54 : kAccent)),
                  if (m.siteName != null) const SizedBox(height: 3),

                  // Title
                  if (m.title != null)
                    Text(m.title!,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: widget.isMe ? Colors.white : isDark ? kTextPrimary : kLightText)),

                  // Description
                  if (m.description != null) ...[ 
                    const SizedBox(height: 3),
                    Text(m.description!,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.isMe ? Colors.white60 : isDark ? kTextSecondary : kLightTextSub)),
                  ],
                ])),
          ]));
  }
}
