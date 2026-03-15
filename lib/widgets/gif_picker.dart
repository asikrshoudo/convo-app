import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

// Replace with your GIPHY API key from developers.giphy.com (free)
const _giphyApiKey = String.fromEnvironment('GIPHY_API_KEY',
    defaultValue: 'dc6zaTOxFJmzC'); // public beta key for testing
const _giphyBase = 'https://api.giphy.com/v1/gifs';

class GifPicker extends StatefulWidget {
  const GifPicker({super.key});
  @override
  State<GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<GifPicker> {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<_GifItem> _gifs    = [];
  bool   _loading  = false;
  bool   _searched = false;
  String _query    = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    setState(() { _loading = true; _searched = false; _error = null; });
    try {
      final key = _giphyApiKey;
      final url = '$_giphyBase/trending?api_key=$key&limit=24&rating=g';
      final res = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _gifs    = _parse(data);
          _loading = false;
        });
      } else {
        setState(() { _loading = false; _error = 'API error ${res.statusCode}'; });
      }
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) { _loadTrending(); return; }
    setState(() { _loading = true; _searched = true; _query = q; _gifs = []; _error = null; });
    try {
      final url = '$_giphyBase/search?api_key=$_giphyApiKey'
          '&q=${Uri.encodeComponent(q)}&limit=24&rating=g';
      final res = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _gifs    = _parse(data);
          _loading = false;
        });
      } else {
        setState(() { _loading = false; _error = 'API error ${res.statusCode}'; });
      }
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  List<_GifItem> _parse(Map<String, dynamic> data) {
    final results = data['data'] as List? ?? [];
    return results.map((r) {
      final images = r['images'] as Map? ?? {};
      final preview = (images['downsized_medium'] as Map?)?['url'] as String?
          ?? (images['downsized'] as Map?)?['url'] as String?
          ?? (images['fixed_height'] as Map?)?['url'] as String? ?? '';
      final full = (images['original'] as Map?)?['url'] as String?
          ?? preview;
      // Keep only the base URL — GIPHY .gif URLs work without query params
      // e.g. https://media.giphy.com/media/xxx/giphy.gif
      String cleanUrl = full.contains('?')
          ? full.substring(0, full.indexOf('?'))
          : full;
      // Ensure it ends with .gif so link_preview detects it as image
      if (!cleanUrl.toLowerCase().endsWith('.gif')) cleanUrl = full;
      return _GifItem(
        previewUrl: preview,
        fullUrl:    cleanUrl,
        id: r['id'] as String? ?? '',
      );
    }).where((g) => g.previewUrl.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: BoxDecoration(
        color: isDark ? kCard : kLightCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(children: [

        // Handle
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: isDark ? kTextTertiary : kLightTextSub,
            borderRadius: BorderRadius.circular(2))),

        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? kCard2 : kLightCard2,
              borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Padding(
                padding: EdgeInsets.only(left: 12),
                child: Icon(Icons.search_rounded, color: kAccent, size: 20)),
              Expanded(child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                style: TextStyle(
                  color: isDark ? kTextPrimary : kLightText, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search GIFs...',
                  hintStyle: TextStyle(
                    color: isDark ? kTextTertiary : kLightTextSub,
                    fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 10)))),
              if (_searchCtrl.text.isNotEmpty)
                GestureDetector(
                  onTap: () { _searchCtrl.clear(); _loadTrending(); },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Icon(Icons.close_rounded, size: 18,
                      color: isDark ? kTextSecondary : kLightTextSub))),
            ]))),

        // Label row
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Row(children: [
            Text(_searched ? 'Results for "$_query"' : 'Trending',
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: isDark ? kTextSecondary : kLightTextSub)),
            const Spacer(),
            Text('via GIPHY', style: TextStyle(
              fontSize: 10,
              color: isDark ? kTextTertiary : kLightTextSub)),
          ])),

        // Grid
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(
              color: kAccent, strokeWidth: 2))
          : _gifs.isEmpty
            ? Center(child: Text(
                _error != null
                  ? 'Error: $_error'
                  : _searched ? 'No GIFs found' : 'Could not load GIFs',
                style: TextStyle(
                  color: isDark ? kTextSecondary : kLightTextSub,
                  fontSize: 13),
                textAlign: TextAlign.center))
            : GridView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: 1.6),
                itemCount: _gifs.length,
                itemBuilder: (_, i) {
                  final gif = _gifs[i];
                  return GestureDetector(
                    onTap: () => Navigator.pop(context, gif.fullUrl),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        gif.previewUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, prog) =>
                          prog == null ? child
                          : Container(
                              color: isDark ? kCard2 : kLightCard2,
                              child: const Center(child: SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5, color: kAccent)))),
                        errorBuilder: (_, __, ___) => Container(
                          color: isDark ? kCard2 : kLightCard2,
                          child: const Icon(Icons.gif_rounded,
                            color: kAccent, size: 32)))));
                })),

        // Safe area padding
        SizedBox(height: MediaQuery.of(context).padding.bottom),
      ]));
  }
}

class _GifItem {
  final String id, previewUrl, fullUrl;
  const _GifItem({required this.id, required this.previewUrl, required this.fullUrl});
}
