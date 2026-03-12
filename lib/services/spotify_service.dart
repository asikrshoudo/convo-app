import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';

const _kClientId    = '88908407dc694de29b1daf7967d69140';
const _kRedirectUri = 'convo://spotify-callback';
const _kScopes      = [
  'user-read-currently-playing',
  'user-read-playback-state',
  'user-read-recently-played',
  'user-read-private',
];

class SpotifyTrack {
  final String title;
  final String artist;
  final String albumArt;
  final String trackUrl;
  final bool   isPlaying;
  final bool   isPremium;

  const SpotifyTrack({
    required this.title,
    required this.artist,
    required this.albumArt,
    required this.trackUrl,
    required this.isPlaying,
    required this.isPremium,
  });

  Map<String, dynamic> toMap() => {
    'title':     title,
    'artist':    artist,
    'albumArt':  albumArt,
    'trackUrl':  trackUrl,
    'isPlaying': isPlaying,
    'isPremium': isPremium,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory SpotifyTrack.fromMap(Map<String, dynamic> m) => SpotifyTrack(
    title:     m['title']     as String? ?? '',
    artist:    m['artist']    as String? ?? '',
    albumArt:  m['albumArt']  as String? ?? '',
    trackUrl:  m['trackUrl']  as String? ?? '',
    isPlaying: m['isPlaying'] == true,
    isPremium: m['isPremium'] == true,
  );
}

class SpotifyService {
  SpotifyService._();
  static final SpotifyService instance = SpotifyService._();
  Timer? _timer;

  String _verifier() {
    final b = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(b).replaceAll('=', '');
  }

  String _challenge(String v) {
    final d = sha256.convert(utf8.encode(v));
    return base64UrlEncode(d.bytes).replaceAll('=', '');
  }

  Future<bool> connect(String uid) async {
    try {
      final v  = _verifier();
      final c  = _challenge(v);
      final st = base64UrlEncode(
        List<int>.generate(16, (_) => Random.secure().nextInt(256)));

      final url = Uri.https('accounts.spotify.com', '/authorize', {
        'client_id':             _kClientId,
        'response_type':         'code',
        'redirect_uri':          _kRedirectUri,
        'code_challenge_method': 'S256',
        'code_challenge':        c,
        'state':                 st,
        'scope':                 _kScopes.join(' '),
      });

      final result = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: 'convo');

      final code = Uri.parse(result).queryParameters['code'];
      if (code == null) return false;

      final res = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type':    'authorization_code',
          'code':          code,
          'redirect_uri':  _kRedirectUri,
          'client_id':     _kClientId,
          'code_verifier': v,
        });

      if (res.statusCode != 200) return false;

      final d         = json.decode(res.body);
      final access    = d['access_token']  as String;
      final refresh   = d['refresh_token'] as String;
      final expiresAt = DateTime.now()
        .add(Duration(seconds: d['expires_in'] as int))
        .millisecondsSinceEpoch;

      await db.collection('users').doc(uid)
        .collection('private').doc('spotify')
        .set({
          'accessToken':  access,
          'refreshToken': refresh,
          'expiresAt':    expiresAt,
          'connectedAt':  FieldValue.serverTimestamp(),
        });

      await db.collection('users').doc(uid)
        .update({'spotifyConnected': true});

      await _poll(uid);
      _startPolling(uid);
      return true;
    } catch (e) {
      debugPrint('Spotify connect: $e');
      return false;
    }
  }

  Future<void> disconnect(String uid) async {
    _timer?.cancel();
    _timer = null;
    await db.collection('users').doc(uid)
      .collection('private').doc('spotify').delete();
    await db.collection('users').doc(uid).update({
      'spotifyConnected': false,
      'spotifyTrack':     FieldValue.delete(),
    });
  }

  Future<String?> _validToken(String uid) async {
    try {
      final snap = await db.collection('users').doc(uid)
        .collection('private').doc('spotify').get();
      if (!snap.exists) return null;

      final d       = snap.data()!;
      final access  = d['accessToken']  as String;
      final refresh = d['refreshToken'] as String;
      final expiry  = d['expiresAt']    as int;

      if (DateTime.now().millisecondsSinceEpoch < expiry - 60000) {
        return access;
      }

      final res = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type':    'refresh_token',
          'refresh_token': refresh,
          'client_id':     _kClientId,
        });

      if (res.statusCode != 200) return null;

      final nd     = json.decode(res.body);
      final newTok = nd['access_token'] as String;
      final newExp = DateTime.now()
        .add(Duration(seconds: nd['expires_in'] as int))
        .millisecondsSinceEpoch;

      await db.collection('users').doc(uid)
        .collection('private').doc('spotify')
        .update({'accessToken': newTok, 'expiresAt': newExp});

      return newTok;
    } catch (e) {
      debugPrint('Token refresh: $e');
      return null;
    }
  }

  Future<void> _poll(String uid) async {
    try {
      final token = await _validToken(uid);
      if (token == null) { _timer?.cancel(); return; }

      final meRes = await http.get(
        Uri.parse('https://api.spotify.com/v1/me'),
        headers: {'Authorization': 'Bearer $token'});
      if (meRes.statusCode != 200) return;

      final isPremium = json.decode(meRes.body)['product'] == 'premium';
      SpotifyTrack? track;

      if (isPremium) {
        track = await _nowPlaying(token, isPremium: true);
      }
      track ??= await _lastPlayed(token, isPremium: isPremium);

      if (track != null) {
        await db.collection('users').doc(uid)
          .update({'spotifyTrack': track.toMap()});
      } else {
        await db.collection('users').doc(uid)
          .update({'spotifyTrack': FieldValue.delete()});
      }
    } catch (e) {
      debugPrint('Spotify poll: $e');
    }
  }

  Future<SpotifyTrack?> _nowPlaying(String token,
      {required bool isPremium}) async {
    final res = await http.get(
      Uri.parse('https://api.spotify.com/v1/me/player/currently-playing'),
      headers: {'Authorization': 'Bearer $token'});
    if (res.statusCode == 204 || res.body.isEmpty || res.statusCode != 200) {
      return null;
    }
    final d    = json.decode(res.body);
    final item = d['item'];
    if (item == null) return null;
    return SpotifyTrack(
      title:     item['name'] ?? '',
      artist:    (item['artists'] as List).map((a) => a['name']).join(', '),
      albumArt:  item['album']?['images']?[0]?['url'] ?? '',
      trackUrl:  item['external_urls']?['spotify'] ?? '',
      isPlaying: d['is_playing'] == true,
      isPremium: isPremium);
  }

  Future<SpotifyTrack?> _lastPlayed(String token,
      {required bool isPremium}) async {
    final res = await http.get(
      Uri.parse(
        'https://api.spotify.com/v1/me/player/recently-played?limit=1'),
      headers: {'Authorization': 'Bearer $token'});
    if (res.statusCode != 200) return null;
    final items = json.decode(res.body)['items'] as List?;
    if (items == null || items.isEmpty) return null;
    final item = items[0]['track'];
    return SpotifyTrack(
      title:     item['name'] ?? '',
      artist:    (item['artists'] as List).map((a) => a['name']).join(', '),
      albumArt:  item['album']?['images']?[0]?['url'] ?? '',
      trackUrl:  item['external_urls']?['spotify'] ?? '',
      isPlaying: false,
      isPremium: isPremium);
  }

  void _startPolling(String uid) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _poll(uid));
  }

  void stopPolling() { _timer?.cancel(); _timer = null; }

  Future<void> resumeIfConnected(String uid) async {
    final snap = await db.collection('users').doc(uid).get();
    if (snap.data()?['spotifyConnected'] == true) {
      await _poll(uid);
      _startPolling(uid);
    }
  }
}
