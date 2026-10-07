import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'autostart.dart';
import 'models.dart';
import 'storage.dart';

class StepFailure implements Exception {
  StepFailure(this.status, this.step, this.note);
  final String status;
  final String step;
  final String note;
}

const _site = 'https://agentrouter.org';

const _clickGithubJs = r'''
(function () {
  const b = [...document.querySelectorAll('button')]
    .find(e => /continue with github/i.test(e.innerText));
  if (!b || b.disabled) return false;
  // tick an unchecked "agree to terms / privacy" box if the page has one
  document.querySelectorAll('input[type="checkbox"]').forEach(cb => {
    if (cb.checked) return;
    const t = (cb.closest('label,div,form') || document.body).innerText || '';
    if (/agree|terms|privacy|同意|协议/i.test(t)) cb.click();
  });
  b.scrollIntoView({ block: 'center' });
  // full pointer sequence, like a real tap (a bare click can be ignored)
  for (const t of ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click']) {
    b.dispatchEvent(new MouseEvent(t, { bubbles: true, cancelable: true, view: window }));
  }
  return true;
})();
''';

// Finds the button, ticks the terms box, scrolls it into view and returns its
// centre in physical pixels so a REAL touch can be sent there.
const _prepGithubJs = r'''
const sleep = ms => new Promise(r => setTimeout(r, ms));
const b = [...document.querySelectorAll('button')]
  .find(e => /continue with github/i.test(e.innerText));
if (!b || b.disabled) return null;
document.querySelectorAll('input[type="checkbox"]').forEach(cb => {
  if (cb.checked) return;
  const t = (cb.closest('label,div,form') || document.body).innerText || '';
  if (/agree|terms|privacy|同意|协议/i.test(t)) cb.click();
});
b.scrollIntoView({ block: 'center' });
await sleep(350);
const r = b.getBoundingClientRect();
const d = window.devicePixelRatio || 1;
return { x: (r.left + r.width / 2) * d, y: (r.top + r.height / 2) * d };
''';

// Used with callAsyncJavaScript (function body, may use await/return).
const _logoutJs = r'''
const sleep = ms => new Promise(r => setTimeout(r, ms));
const av = document.querySelector('header button[aria-haspopup="true"] .semi-avatar');
const btn = av && av.closest('button');
if (!btn) return 'no-avatar';
for (const t of ['mouseover', 'mouseenter', 'click']) {
  btn.dispatchEvent(new MouseEvent(t, { bubbles: true }));
}
for (let i = 0; i < 10; i++) {
  await sleep(300);
  const item = [...document.querySelectorAll('.semi-dropdown-item')]
    .find(e => /log\s?out|sign\s?out|退出/i.test(e.innerText || ''));
  if (item) { item.click(); return 'clicked'; }
}
return 'no-logout-item';
''';

Future<bool> _pollUntil(
  Future<bool> Function() cond,
  Duration timeout, {
  Duration every = const Duration(milliseconds: 500),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    try {
      if (await cond()) return true;
    } catch (_) {}
    await Future.delayed(every);
  }
  return false;
}

class RunEngine {
  RunEngine(this._log, this._cookies);

  final void Function(String) _log;
  final CookieStore _cookies;
  InAppWebViewController? web;
  Completer<void>? _loadWait;

  void onLoadStop() {
    final c = _loadWait;
    if (c != null && !c.isCompleted) c.complete();
  }

  Future<void> _load(String url, {Duration timeout = const Duration(seconds: 45)}) async {
    final c = Completer<void>();
    _loadWait = c;
    await web!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    await c.future.timeout(timeout);
  }

  Future<void> _clearAll() async {
    try {
      await _load('about:blank', timeout: const Duration(seconds: 5));
    } catch (_) {}
    await CookieManager.instance().deleteAllCookies();
    try {
      await WebStorageManager.instance().deleteAllData();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<bool> _isLoggedIn() async {
    final u = await web!.getUrl();
    if (u == null || u.host != 'agentrouter.org' || !u.path.startsWith('/console')) {
      return false;
    }
    final r = await web!.evaluateJavascript(
        source: "!!document.querySelector('header .semi-avatar')");
    return r == true;
  }

  Future<bool> _isLoggedOut() async {
    final u = await web!.getUrl();
    if (u != null && u.host == 'agentrouter.org' && u.path.startsWith('/login')) {
      return true;
    }
    final r = await web!.evaluateJavascript(
        source: "!!document.querySelector('header a[href=\"/login\"]')");
    return r == true;
  }

  /// True once the click took effect: we are no longer on agentrouter's /login.
  Future<bool> _leftLoginPage() async {
    final u = await web!.getUrl();
    if (u == null) return false;
    return u.host != 'agentrouter.org' || !u.path.startsWith('/login');
  }

  bool _isGithubLoginPage(WebUri u) =>
      u.host == 'github.com' &&
      (u.path == '/login' || u.path == '/session' || u.path.startsWith('/sessions'));

  /// Taps "Continue with GitHub" with a real native touch (isTrusted + user
  /// activation), falling back to a synthetic JS click if that is unavailable.
  Future<bool> _tapGithub() async {
    final r = await web!.callAsyncJavaScript(functionBody: _prepGithubJs);
    final v = r?.value;
    if (v is! Map) return false; // button not rendered yet
    try {
      final x = (v['x'] as num).toDouble();
      final y = (v['y'] as num).toDouble();
      if (await Autostart.tap(x, y)) return true;
    } catch (_) {}
    return (await web!.evaluateJavascript(source: _clickGithubJs)) == true;
  }

  Future<void> _logoutFallback() async {
    await web!.evaluateJavascript(
        source: 'localStorage.clear(); sessionStorage.clear(); true;');
    final cm = CookieManager.instance();
    final list = await cm.getCookies(url: WebUri(_site));
    for (final c in list) {
      await cm.deleteCookie(
        url: WebUri(_site),
        name: c.name,
        domain: c.domain,
        path: c.path ?? '/',
      );
    }
    await _load('$_site/login');
  }

  Future<AccountResult> runOne(String id, String name, {required bool quick}) async {
    var step = 'start';
    String? note;
    AccountResult res(String status, [String? n]) => AccountResult(
          id: id,
          name: name,
          status: status,
          step: step,
          note: n ?? note,
          at: DateTime.now(),
        );

    final waitSecs = quick ? 3 : 10;
    final loginTimeout = Duration(seconds: quick ? 40 : 60);

    try {
      step = 'clear';
      _log('[$name] clearing cookies + storage');
      await _clearAll();

      step = 'restore';
      _log('[$name] restoring github session');
      final n = await _cookies.restore(id);
      if (n == 0) throw StepFailure('relogin', step, 'no saved session');

      step = 'load-login';
      _log('[$name] loading /login');
      await _load('$_site/login');
      // let the JS app render and attach its handlers before the first click
      await Future.delayed(const Duration(milliseconds: 1500));

      step = 'click-github';
      var navigated = false;
      for (var attempt = 1; attempt <= 6 && !navigated; attempt++) {
        _log('[$name] clicking Continue with GitHub (try $attempt)');
        final clicked = await _pollUntil(_tapGithub, const Duration(seconds: 15));
        if (!clicked) throw StepFailure('failed', step, 'GitHub button not found');
        navigated = await _pollUntil(
          _leftLoginPage,
          const Duration(seconds: 6),
          every: const Duration(milliseconds: 300),
        );
        if (!navigated) _log('[$name] click had no effect, retrying');
      }
      if (!navigated) {
        throw StepFailure('failed', step, 'click had no effect after 6 tries');
      }

      step = 'wait-login';
      _log('[$name] waiting for login (${loginTimeout.inSeconds}s max)');
      final end = DateTime.now().add(loginTimeout);
      var loggedIn = false;
      while (DateTime.now().isBefore(end)) {
        try {
          if (await _isLoggedIn()) {
            loggedIn = true;
            break;
          }
          final u = await web!.getUrl();
          if (u != null && _isGithubLoginPage(u)) {
            throw StepFailure('relogin', step, 'GitHub asked for login');
          }
        } on StepFailure {
          rethrow;
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (!loggedIn) throw StepFailure('timeout', step, 'login not detected');
      _log('[$name] logged in');

      step = 'wait-${waitSecs}s';
      _log('[$name] waiting ${waitSecs}s');
      await Future.delayed(Duration(seconds: waitSecs));

      step = 'logout';
      _log('[$name] logging out');
      final r = await web!.callAsyncJavaScript(functionBody: _logoutJs);
      final v = r?.value?.toString();
      var loggedOut = false;
      if (v == 'clicked') {
        step = 'wait-logout';
        loggedOut = await _pollUntil(_isLoggedOut, const Duration(seconds: 30));
      }
      if (!loggedOut) {
        step = 'logout-fallback';
        note = 'logout used fallback (${v ?? 'null'})';
        _log('[$name] logout click failed ($v), using fallback');
        await _logoutFallback();
        step = 'wait-logout';
        loggedOut = await _pollUntil(_isLoggedOut, const Duration(seconds: 30));
      }
      if (!loggedOut) throw StepFailure('timeout', step, 'logged-out state not seen');

      step = 'done';
      _log('[$name] success');
      return res('success');
    } on StepFailure catch (e) {
      step = e.step;
      _log('[$name] ${e.status} at ${e.step}: ${e.note}');
      return res(e.status, e.note);
    } on TimeoutException {
      _log('[$name] timeout at $step');
      return res('timeout', 'timed out');
    } catch (e) {
      _log('[$name] failed at $step: ${e.runtimeType}');
      return res('failed', e.runtimeType.toString());
    }
  }
}