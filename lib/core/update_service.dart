import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'dart:convert';

class UpdateService {
  static const _owner  = 'asikrshoudo';
  static const _repo   = 'convo-app';
  static const _apiUrl = 'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  /// Call this once on app start (e.g. in app.dart initState)
  static Future<void> checkForUpdate(BuildContext context) async {
    try {
      // 1. Get current version from pubspec
      final info = await PackageInfo.fromPlatform();
      final current = info.version; // e.g. "1.0.2"

      // 2. Fetch latest release from GitHub
      final res = await http.get(
        Uri.parse(_apiUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return;

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final latest = (json['tag_name'] as String).replaceFirst('v', ''); // "v1.0.3" → "1.0.3"
      final changelog = json['body'] as String? ?? '';

      // 3. Find arm64 APK asset
      final assets = (json['assets'] as List<dynamic>);
      final apkAsset = assets.firstWhere(
        (a) => (a['name'] as String).endsWith('.apk') &&
               (a['name'] as String).contains('arm64'),
        orElse: () => assets.firstWhere(
          (a) => (a['name'] as String).endsWith('.apk'),
          orElse: () => null,
        ),
      );
      if (apkAsset == null) return;

      final downloadUrl = apkAsset['browser_download_url'] as String;
      final apkName     = apkAsset['name'] as String;

      // 4. Compare versions
      if (!_isNewer(latest, current)) return;

      // 5. Show dialog
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => UpdateDialog(
            currentVersion: current,
            newVersion: latest,
            changelog: changelog,
            downloadUrl: downloadUrl,
            apkName: apkName,
          ),
        );
      }
    } catch (_) {
      // Silent fail — update check should never crash the app
    }
  }

  /// Returns true if [latest] is newer than [current]
  static bool _isNewer(String latest, String current) {
    final l = _parse(latest);
    final c = _parse(current);
    for (int i = 0; i < 3; i++) {
      if (l[i] > c[i]) return true;
      if (l[i] < c[i]) return false;
    }
    return false;
  }

  static List<int> _parse(String v) {
    final parts = v.split('.');
    return List.generate(3, (i) => i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class UpdateDialog extends StatefulWidget {
  final String currentVersion, newVersion, changelog, downloadUrl, apkName;
  const UpdateDialog({
    super.key,
    required this.currentVersion,
    required this.newVersion,
    required this.changelog,
    required this.downloadUrl,
    required this.apkName,
  });
  @override State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  double _progress = 0;
  bool _downloading = false;
  bool _done = false;
  String? _apkPath;

  Future<void> _download() async {
    setState(() { _downloading = true; _progress = 0; });

    try {
      final client = http.Client();
      final req    = http.Request('GET', Uri.parse(widget.downloadUrl));
      final res    = await client.send(req);
      final total  = res.contentLength ?? 1;

      final dir  = await getExternalStorageDirectory() ?? await getTemporaryDirectory();
      final file = File('${dir.path}/${widget.apkName}');
      final sink = file.openWrite();

      int received = 0;
      await res.stream.forEach((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (mounted) setState(() => _progress = received / total);
      });
      await sink.close();
      client.close();

      setState(() { _done = true; _apkPath = file.path; });
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _install() async {
    if (_apkPath == null) return;
    await OpenFile.open(_apkPath!);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF00C853).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.system_update_rounded, color: Color(0xFF00C853), size: 26)),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Update Available',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('v${widget.currentVersion} → v${widget.newVersion}',
                style: const TextStyle(color: Color(0xFF00C853), fontSize: 13)),
            ]),
          ]),

          const SizedBox(height: 16),

          // Changelog
          if (widget.changelog.isNotEmpty) ...[
            Text("What's new:", style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13,
              color: isDark ? Colors.white70 : Colors.black54)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                borderRadius: BorderRadius.circular(10)),
              child: Text(
                widget.changelog.length > 300
                  ? '${widget.changelog.substring(0, 300)}...'
                  : widget.changelog,
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54, height: 1.5))),
            const SizedBox(height: 16),
          ],

          // Progress bar
          if (_downloading) ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_done ? 'Download complete!' : 'Downloading...',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              Text('${(_progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Color(0xFF00C853), fontSize: 13, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 8,
                backgroundColor: isDark ? Colors.white12 : Colors.grey[200],
                color: const Color(0xFF00C853))),
            const SizedBox(height: 16),
          ],

          // Buttons
          Row(children: [
            if (!_downloading)
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.withOpacity(0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Later', style: TextStyle(color: Colors.grey)))),

            if (!_downloading) const SizedBox(width: 12),

            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C853),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: _done ? _install : (_downloading ? null : _download),
                child: Text(
                  _done ? 'Install Now' : (_downloading ? 'Downloading...' : 'Update'),
                  style: const TextStyle(fontWeight: FontWeight.bold)))),
          ]),
        ]),
      ),
    );
  }
}
