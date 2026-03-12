import 'dart:convert';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class LanyardData {
  final String discordStatus; // online | idle | dnd | offline
  final String? customStatusText;
  final String? customStatusEmoji;
  final LanyardSpotify? spotify;
  final List<LanyardActivity> activities;
  final String discordUsername;
  final String? avatarHash;
  final String discordId;

  const LanyardData({
    required this.discordStatus,
    this.customStatusText,
    this.customStatusEmoji,
    this.spotify,
    required this.activities,
    required this.discordUsername,
    this.avatarHash,
    required this.discordId,
  });

  String? get avatarUrl => avatarHash != null
      ? 'https://cdn.discordapp.com/avatars/$discordId/$avatarHash.png?size=128'
      : null;
}

class LanyardSpotify {
  final String song;
  final String artist;
  final String album;
  final String? albumArtUrl;
  final String? trackId;
  final int? timestampStart;
  final int? timestampEnd;

  const LanyardSpotify({
    required this.song,
    required this.artist,
    required this.album,
    this.albumArtUrl,
    this.trackId,
    this.timestampStart,
    this.timestampEnd,
  });

  double get progress {
    if (timestampStart == null || timestampEnd == null) return 0;
    final now   = DateTime.now().millisecondsSinceEpoch;
    final total = timestampEnd! - timestampStart!;
    if (total <= 0) return 0;
    return ((now - timestampStart!) / total).clamp(0.0, 1.0);
  }

  String get trackUrl => trackId != null
      ? 'https://open.spotify.com/track/$trackId'
      : '';
}

class LanyardActivity {
  final int    type;
  final String name;
  final String? state;
  final String? details;
  final String? largeImageUrl;
  final String? smallImageUrl;

  const LanyardActivity({
    required this.type,
    required this.name,
    this.state,
    this.details,
    this.largeImageUrl,
    this.smallImageUrl,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Parser
// ─────────────────────────────────────────────────────────────────────────────

LanyardData _parse(Map<String, dynamic> json) {
  final data = json['data'] as Map<String, dynamic>;
  final user = data['discord_user'] as Map<String, dynamic>;

  // ── Activities ────────────────────────────────────────────────
  String? customText;
  String? customEmoji;
  final activities = <LanyardActivity>[];

  for (final raw in (data['activities'] as List? ?? [])) {
    final a = raw as Map<String, dynamic>;
    final type = a['type'] as int? ?? 0;

    if (type == 4) {
      // Custom status
      customText  = a['state'] as String?;
      customEmoji = (a['emoji'] as Map<String, dynamic>?)?['name'] as String?;
      continue;
    }

    // Build asset image URL
    String? largeImg;
    String? smallImg;
    final assets = a['assets'] as Map<String, dynamic>?;
    if (assets != null) {
      String? makeUrl(String? key) {
        if (key == null) return null;
        if (key.startsWith('mp:external/')) {
          return 'https://media.discordapp.net/external/${key.replaceFirst('mp:external/', '')}';
        }
        final appId = a['application_id'] as String?;
        return appId != null
            ? 'https://cdn.discordapp.com/app-assets/$appId/$key.png'
            : null;
      }
      largeImg = makeUrl(assets['large_image'] as String?);
      smallImg = makeUrl(assets['small_image'] as String?);
    }

    activities.add(LanyardActivity(
      type:          type,
      name:          a['name']    as String? ?? '',
      state:         a['state']   as String?,
      details:       a['details'] as String?,
      largeImageUrl: largeImg,
      smallImageUrl: smallImg,
    ));
  }

  // ── Spotify ───────────────────────────────────────────────────
  LanyardSpotify? spotify;
  final sp = data['spotify'] as Map<String, dynamic>?;
  if (sp != null) {
    final ts = sp['timestamps'] as Map<String, dynamic>?;
    spotify = LanyardSpotify(
      song:           sp['song']           as String? ?? '',
      artist:         sp['artist']         as String? ?? '',
      album:          sp['album']          as String? ?? '',
      albumArtUrl:    sp['album_art_url']  as String?,
      trackId:        sp['track_id']       as String?,
      timestampStart: ts?['start']         as int?,
      timestampEnd:   ts?['end']           as int?,
    );
  }

  return LanyardData(
    discordStatus:    data['discord_status'] as String? ?? 'offline',
    customStatusText: customText,
    customStatusEmoji: customEmoji,
    spotify:          spotify,
    activities:       activities,
    discordUsername:  user['username'] as String? ?? '',
    avatarHash:       user['avatar']   as String?,
    discordId:        user['id']       as String? ?? '',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class LanyardService {
  static const _base = 'https://api.lanyard.rest/v1/users';

  static Future<LanyardData?> fetch(String discordId) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/$discordId'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['success'] != true) return null;
      return _parse(json);
    } catch (_) {
      return null;
    }
  }
}
