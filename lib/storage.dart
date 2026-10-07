import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide AndroidOptions;
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as secure_storage;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// GitHub cookies live ONLY in flutter_secure_storage. Values are never logged.
class CookieStore {
  static const _s = secure_storage.FlutterSecureStorage(
aOptions: secure_storage.AndroidOptions(encryptedSharedPreferences: true),
  );

  // Android's CookieManager only returns name=value, so flags are guessed
  // for these well-known GitHub cookies when restoring.
  static const _httpOnlyNames = {
    'user_session',
    '__Host-user_session_same_site',
    '_gh_sess',
    '_device_id',
    'tz',
  };

  Future<bool> has(String id) async => (await _s.read(key: 'cookies_$id')) != null;

  Future<void> delete(String id) => _s.delete(key: 'cookies_$id');

  Future<({int count, bool hasSession})> save(String id) async {
    final cookies =
        await CookieManager.instance().getCookies(url: WebUri('https://github.com'));
    final list = cookies
        .map((c) => {
              'n': c.name,
              'v': '${c.value}',
              'd': c.domain,
              'p': c.path,
              's': c.isSecure,
              'h': c.isHttpOnly,
              'e': c.expiresDate,
            })
        .toList();
    final hasSession = cookies.any((c) => c.name == 'user_session');
    if (hasSession) {
      await _s.write(key: 'cookies_$id', value: jsonEncode(list));
    }
    return (count: list.length, hasSession: hasSession);
  }

  /// Returns number of cookies restored (0 = nothing saved).
  Future<int> restore(String id) async {
    final raw = await _s.read(key: 'cookies_$id');
    if (raw == null) return 0;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final cm = CookieManager.instance();
    final defaultExpiry =
        DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch;
    for (final c in list) {
      final name = c['n'] as String;
      final isHost = name.startsWith('__Host-');
      await cm.setCookie(
        url: WebUri('https://github.com'),
        name: name,
        value: c['v'] as String,
        path: '/',
        // __Host- cookies: Secure, path "/", and NO domain.
        domain: isHost ? null : '.github.com',
        isSecure: true,
        isHttpOnly: (c['h'] as bool?) ?? _httpOnlyNames.contains(name),
        expiresDate: (c['e'] as int?) ?? defaultExpiry,
        sameSite: HTTPCookieSameSitePolicy.LAX,
      );
    }
    return list.length;
  }
}

class HistoryStore {
  static const _key = 'history';

  List<RunRecord> load(SharedPreferences p) {
    final raw = p.getStringList(_key) ?? [];
    final out = <RunRecord>[];
    for (final s in raw) {
      try {
        out.add(RunRecord.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }

  Future<void> save(SharedPreferences p, List<RunRecord> h) async {
    await p.setStringList(
        _key, h.take(100).map((r) => jsonEncode(r.toJson())).toList());
  }
}