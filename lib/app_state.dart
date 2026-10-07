import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'autostart.dart';
import 'models.dart';
import 'notifications.dart';
import 'runner.dart';
import 'storage.dart';

final AppState app = AppState();

class AppState extends ChangeNotifier {
  final notifier = Notifier();
  final cookies = CookieStore();
  final _historyStore = HistoryStore();
  late final RunEngine engine = RunEngine(_log, cookies);

  final Completer<void> webReady = Completer<void>();
  final ValueNotifier<int> tab = ValueNotifier(0);
  late SharedPreferences prefs;

  /// Ordered list of account ids (any number of accounts).
  final List<String> accountIds = [];
  final Map<String, String> names = {};
  final Map<String, bool> sessionSaved = {};
  final Map<String, bool> needsRelogin = {};
  List<RunRecord> history = [];
  final List<String> logLines = [];
  List<int> pendingIds = [];

  bool isRunning = false;
  bool quickWaits = false;
  int gapSeconds = 15; // pause between one account's logout and the next login
  int dailyHour = 18;
  int dailyMinute = 30;
  bool autoStart = true; // launch the app and run by itself at the daily time
  bool overlayOk = true;
  bool fsiOk = true;
  DateTime? _lastDaily;
  final Set<String> selected = {};
  String? currentLabel;
  String? lastSummary;

  Timer? testTimer;
  Timer? _tick;
  DateTime? _testAt;
  int countdown = 0;
  DateTime? _lastTrigger;
  String? _launchPayload;

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    gapSeconds = prefs.getInt('gap') ?? 15;
    dailyHour = prefs.getInt('daily_h') ?? 18;
    dailyMinute = prefs.getInt('daily_m') ?? 30;
    autoStart = prefs.getBool('autostart') ?? true;
    Autostart.listen(() => triggerRun('daily'));
    _loadAccounts();
    for (final id in accountIds) {
      sessionSaved[id] = await cookies.has(id);
      needsRelogin[id] = prefs.getBool('needs_$id') ?? false;
    }
    selected.addAll(accountIds);
    history = _historyStore.load(prefs);

    await notifier.init(handleTap);
    await ensureDaily();
    final d = await notifier.plugin.getNotificationAppLaunchDetails();
    if (d?.didNotificationLaunchApp ?? false) {
      _launchPayload = d!.notificationResponse?.payload;
    }
    try {
      if (await Autostart.consumeAutorun()) _launchPayload = 'run';
    } catch (_) {}
    await refreshOverlay();
  }

  // ---- daily time + autostart ------------------------------------------

  Future<void> setDailyTime(int h, int m) async {
    dailyHour = h;
    dailyMinute = m;
    await prefs.setInt('daily_h', h);
    await prefs.setInt('daily_m', m);
    await ensureDaily();
  }

  Future<void> setAutoStart(bool v) async {
    autoStart = v;
    await prefs.setBool('autostart', v);
    await ensureDaily();
    await refreshOverlay();
  }

  Future<void> refreshOverlay() async {
    try {
      overlayOk = await Autostart.canOverlay();
      fsiOk = await Autostart.canFullScreen();
    } catch (_) {}
    notifyListeners();
  }

  // ---- accounts ---------------------------------------------------------

  void _loadAccounts() {
    final raw = prefs.getString('accounts');
    if (raw != null) {
      try {
        for (final e in (jsonDecode(raw) as List)) {
          final m = e as Map<String, dynamic>;
          accountIds.add(m['id'] as String);
          names[m['id'] as String] = m['name'] as String;
        }
        return;
      } catch (_) {
        accountIds.clear();
        names.clear();
      }
    }
    // first run (or upgrade from the fixed 3 accounts): seed acc1..acc3
    for (final id in kAccountIds) {
      accountIds.add(id);
      names[id] = prefs.getString('name_$id') ?? id;
    }
    _saveAccounts();
  }

  Future<void> _saveAccounts() => prefs.setString(
        'accounts',
        jsonEncode([
          for (final id in accountIds) {'id': id, 'name': names[id] ?? id}
        ]),
      );

  Future<void> addAccount(String name) async {
    final id = 'a${DateTime.now().millisecondsSinceEpoch}';
    accountIds.add(id);
    names[id] = name.trim().isEmpty ? 'Account ${accountIds.length}' : name.trim();
    sessionSaved[id] = false;
    needsRelogin[id] = false;
    selected.add(id);
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> removeAccount(String id) async {
    if (isRunning) return;
    await cookies.delete(id);
    await prefs.remove('needs_$id');
    accountIds.remove(id);
    names.remove(id);
    sessionSaved.remove(id);
    needsRelogin.remove(id);
    selected.remove(id);
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> rename(String id, String name) async {
    names[id] = name.trim().isEmpty ? id : name.trim();
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> markSaved(String id) async {
    sessionSaved[id] = true;
    needsRelogin[id] = false;
    await prefs.setBool('needs_$id', false);
    notifyListeners();
  }

  Future<void> setGap(int v) async {
    gapSeconds = v;
    await prefs.setInt('gap', v);
    notifyListeners();
  }

  // ---- notification handling -------------------------------------------

  void handleTap(NotificationResponse r) => handlePayload(r.payload);

  void handlePayload(String? p) {
    switch (p) {
      case 'run':
        triggerRun('daily');
      case 'test':
        triggerRun('test-tap');
      case 'summary':
        tab.value = 3;
      default:
        break;
    }
  }

  /// Called once the UI is up: handles the cold-start tap.
  void handleLaunch() {
    final p = _launchPayload;
    _launchPayload = null;
    handlePayload(p);
  }

  Future<void> ensureDaily() async {
    try {
      await notifier.scheduleDaily(dailyHour, dailyMinute);
    } catch (e) {
      _log('Could not schedule daily: ${e.runtimeType}');
    }
    try {
      if (autoStart) {
        await Autostart.schedule(dailyHour, dailyMinute);
      } else {
        await Autostart.cancel();
      }
    } catch (e) {
      _log('Could not schedule autostart: ${e.runtimeType}');
    }
    await refreshPending();
  }

  Future<void> refreshPending() async {
    try {
      pendingIds = await notifier.pendingIds();
    } catch (_) {}
    notifyListeners();
  }

  // ---- test mode --------------------------------------------------------

  Future<void> scheduleTest({int seconds = 30}) async {
    if (isRunning) return;
    try {
      await notifier.scheduleTest(seconds);
    } catch (e) {
      _log('Test notification failed: ${e.runtimeType}');
    }
    testTimer?.cancel();
    _tick?.cancel();
    _testAt = DateTime.now().add(Duration(seconds: seconds));
    countdown = seconds;
    testTimer = Timer(Duration(seconds: seconds), () => triggerRun('test-timer'));
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      countdown =
          _testAt!.difference(DateTime.now()).inSeconds.clamp(0, 9999).toInt();
      if (countdown <= 0) t.cancel();
      notifyListeners();
    });
    await refreshPending();
  }

  void toggleSelected(String id, bool on) {
    on ? selected.add(id) : selected.remove(id);
    notifyListeners();
  }

  void setQuick(bool v) {
    quickWaits = v;
    notifyListeners();
  }

  // ---- the run ----------------------------------------------------------

  Future<void> triggerRun(String source) async {
    if (isRunning) return; // lock: a late tap can't start a second run
    final now = DateTime.now();
    if (source == 'daily') {
      // alarm launch + full-screen notification can both fire: run only once
      final d = _lastDaily;
      if (d != null && now.difference(d).inMinutes < 10) return;
      _lastDaily = now;
    }
    final last = _lastTrigger;
    if (last != null && now.difference(last).inSeconds < 5) return;
    _lastTrigger = now;
    isRunning = true;
    Autostart.keepAwake(true).catchError((_) {});

    testTimer?.cancel();
    _tick?.cancel();
    countdown = 0;
    logLines.clear();
    notifyListeners();

    final isTest = source.startsWith('test') || source == 'run-now';
    final ids = isTest
        ? accountIds.where(selected.contains).toList()
        : List<String>.of(accountIds);
    final quick = isTest && quickWaits;
    final gap = quick ? 3 : gapSeconds;

    try {
      try {
        await notifier.cancelTest();
      } catch (_) {}
      if (ids.isEmpty) {
        _log('No accounts to run');
        return;
      }
      tab.value = 2;
      _progress('Opening the app…');
      if (!await _waitForeground()) {
        _log('App could not reach the foreground, aborting');
        _lastDaily = null; // let the "tap to run" notification start it
        try {
          await notifier.clearProgress();
          await notifier.showRetry();
        } catch (_) {}
        return;
      }
      try {
        await webReady.future.timeout(const Duration(seconds: 15));
      } on TimeoutException {
        _log('WebView not ready, aborting');
        return;
      }
      await Future.delayed(const Duration(milliseconds: 600));

      _log('Run started (source: $source${quick ? ', quick' : ''}, ${ids.length} accounts)');
      final rec = RunRecord(startedAt: now, source: source, isTest: isTest);
      for (var i = 0; i < ids.length; i++) {
        final id = ids[i];
        currentLabel = names[id];
        _progress('${names[id] ?? id}  (${i + 1}/${ids.length})',
            done: i, total: ids.length);
        notifyListeners();
        final r = await engine.runOne(id, names[id] ?? id, quick: quick);
        rec.results.add(r);
        if (r.status == 'relogin') {
          needsRelogin[id] = true;
          await prefs.setBool('needs_$id', true);
        } else if (r.status == 'success') {
          needsRelogin[id] = false;
          await prefs.setBool('needs_$id', false);
        }
        notifyListeners();

        if (i < ids.length - 1 && gap > 0) {
          currentLabel = 'waiting ${gap}s before next account';
          _progress('Waiting ${gap}s before next account',
              done: i + 1, total: ids.length);
          _log('Waiting ${gap}s before next account');
          await Future.delayed(Duration(seconds: gap));
        }
      }
      history.insert(0, rec);
      await _historyStore.save(prefs, history);

      try {
        await notifier.clearProgress();
      } catch (_) {}
      lastSummary = '${rec.okCount}/${rec.results.length} done';
      _log('Finished: $lastSummary');
      try {
        await notifier.showSummary(lastSummary!);
      } catch (_) {}
    } catch (e) {
      _log('Run aborted: ${e.runtimeType}');
    } finally {
      Autostart.keepAwake(false).catchError((_) {});
      notifier.clearProgress().catchError((_) {});
      isRunning = false;
      currentLabel = null;
      notifyListeners();
    }
  }

  void _progress(String text, {int? done, int? total}) {
    notifier
        .showProgress('Daily login run', text, done: done, total: total)
        .catchError((_) {});
  }

  /// Waits until the app is really on screen (taps need a visible WebView).
  Future<bool> _waitForeground() async {
    bool fg() =>
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    final end = DateTime.now().add(const Duration(seconds: 90));
    var n = 0;
    while (!fg()) {
      if (DateTime.now().isAfter(end)) return false;
      if (n % 5 == 0) {
        _log('Bringing the app to the foreground');
        try {
          await Autostart.bringToFront();
        } catch (_) {}
      }
      n++;
      await Future.delayed(const Duration(seconds: 1));
    }
    await Future.delayed(const Duration(milliseconds: 1200)); // WebView surface
    return true;
  }

  void _log(String m) {
    final t = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    logLines.add('${p(t.hour)}:${p(t.minute)}:${p(t.second)}  $m');
    if (logLines.length > 300) logLines.removeAt(0);
    notifyListeners();
  }
}