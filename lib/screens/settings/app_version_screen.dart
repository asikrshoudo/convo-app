import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../core/update_service.dart';

class AppVersionScreen extends StatefulWidget {
  const AppVersionScreen({super.key});
  @override State<AppVersionScreen> createState() => _AppVersionScreenState();
}

class _AppVersionScreenState extends State<AppVersionScreen> {
  String _currentVersion = '...';
  String _latestVersion  = '';
  String _changelog      = '';
  bool   _loading        = true;
  bool   _hasUpdate      = false;
  String _downloadUrl    = '';
  String _apkName        = '';

  static const _owner  = 'asikrshoudo';
  static const _repo   = 'convo-app';
  static const _apiUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';
  static const _repoUrl = 'https://github.com/$_owner/$_repo/releases';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() { _loading = true; _hasUpdate = false; });
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() => _currentVersion = info.version);

      final res = await http.get(
        Uri.parse(_apiUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        setState(() => _loading = false);
        return;
      }

      final json     = jsonDecode(res.body) as Map<String, dynamic>;
      final latest   = (json['tag_name'] as String).replaceFirst('v', '');
      final changelog = json['body'] as String? ?? '';

      final assets   = (json['assets'] as List<dynamic>);
      final apkAsset = assets.firstWhere(
        (a) => (a['name'] as String).endsWith('.apk') &&
               (a['name'] as String).contains('arm64'),
        orElse: () => assets.firstWhere(
          (a) => (a['name'] as String).endsWith('.apk'),
          orElse: () => null));

      setState(() {
        _latestVersion = latest;
        _changelog     = changelog;
        _loading       = false;
        _hasUpdate     = UpdateService.isNewer(latest, info.version);
        if (apkAsset != null) {
          _downloadUrl = apkAsset['browser_download_url'] as String;
          _apkName     = apkAsset['name'] as String;
        }
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? kDark : kLightBg,
      appBar: AppBar(
        title: const Text('App Version'),
        backgroundColor: isDark ? kDark : kLightBg,
        elevation: 0),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: kAccent, strokeWidth: 2))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [

              // App logo + version card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? kCard : kLightCard,
                  borderRadius: BorderRadius.circular(kCardRadius),
                  border: Border.all(color: isDark ? kDivider : kLightDivider, width: 0.5)),
                child: Column(children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: kAccent.withOpacity(0.15),
                      shape: BoxShape.circle),
                    child: const Icon(Icons.chat_bubble_rounded,
                      color: kAccent, size: 36)),
                  const SizedBox(height: 12),
                  Text('Convo',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                      color: isDark ? kTextPrimary : kLightText)),
                  const SizedBox(height: 4),
                  Text('Version $_currentVersion (installed)',
                    style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 13)),
                ])),

              const SizedBox(height: 16),

              // Update status card
              if (_latestVersion.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _hasUpdate
                      ? kAccent.withOpacity(0.1) : const Color(0xFF34C759).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(kCardRadius),
                    border: Border.all(
                      color: _hasUpdate
                        ? kAccent.withOpacity(0.4) : const Color(0xFF34C759).withOpacity(0.3))),
                  child: Row(children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: (_hasUpdate ? kAccent : const Color(0xFF34C759)).withOpacity(0.15),
                        shape: BoxShape.circle),
                      child: Icon(
                        _hasUpdate
                          ? Icons.system_update_rounded
                          : Icons.check_circle_rounded,
                        color: _hasUpdate ? kAccent : const Color(0xFF34C759),
                        size: 26)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        _hasUpdate ? 'Update Available!' : 'You\'re up to date!',
                        style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15,
                          color: _hasUpdate ? kAccent : const Color(0xFF34C759))),
                      const SizedBox(height: 2),
                      Text(
                        _hasUpdate
                          ? 'v$_currentVersion → v$_latestVersion'
                          : 'v$_latestVersion is the latest version',
                        style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub, fontSize: 13)),
                    ])),
                  ])),

                // Changelog
                if (_changelog.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? kCard : kLightCard,
                      borderRadius: BorderRadius.circular(kCardRadius),
                      border: Border.all(color: isDark ? kDivider : kLightDivider, width: 0.5)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.article_outlined, color: kAccent, size: 16),
                        const SizedBox(width: 6),
                        Text("What's new",
                          style: TextStyle(fontWeight: FontWeight.bold,
                            color: isDark ? kTextPrimary : kLightText, fontSize: 14)),
                      ]),
                      const SizedBox(height: 10),
                      Text(
                        _changelog.length > 500
                          ? '${_changelog.substring(0, 500)}...'
                          : _changelog,
                        style: TextStyle(
                          color: isDark ? kTextSecondary : kLightTextSub, fontSize: 13, height: 1.5)),
                    ])),
                ],

                const SizedBox(height: 20),

                // Buttons
                if (_hasUpdate && _downloadUrl.isNotEmpty) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccent, elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                      icon: const Icon(Icons.download_rounded, color: Colors.white),
                      label: const Text('Download & Install',
                        style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold, fontSize: 15)),
                      onPressed: () => UpdateService.checkForUpdate(context))),
                  const SizedBox(height: 10),
                ],

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: isDark ? kDivider : kLightDivider),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                    icon: Icon(Icons.open_in_new_rounded,
                      color: isDark ? kTextSecondary : kLightTextSub, size: 18),
                    label: Text('View on GitHub',
                      style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub,
                        fontWeight: FontWeight.w500)),
                    onPressed: () => launchUrl(
                      Uri.parse(_repoUrl),
                      mode: LaunchMode.externalApplication))),

                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    icon: const Icon(Icons.refresh_rounded,
                      color: kAccent, size: 18),
                    label: const Text('Check Again',
                      style: TextStyle(color: kAccent)),
                    onPressed: _check)),
              ] else ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? kCard : kLightCard, borderRadius: BorderRadius.circular(kCardRadius)),
                  child: Row(children: [
                    Icon(Icons.wifi_off_rounded, color: isDark ? kTextSecondary : kLightTextSub),
                    SizedBox(width: 10),
                    Text('Could not check for updates.',
                      style: TextStyle(color: isDark ? kTextSecondary : kLightTextSub)),
                  ])),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _check,
                    child: const Text('Retry'))),
              ],
            ])));
  }
}
