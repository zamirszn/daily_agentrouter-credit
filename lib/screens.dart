import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_state.dart';
import 'autostart.dart';
import 'notifications.dart';

String _p2(int v) => v.toString().padLeft(2, '0');
String _t12(int h, int m) =>
    '${h % 12 == 0 ? 12 : h % 12}:${_p2(m)}${h < 12 ? 'am' : 'pm'}';
String _fmt(DateTime d) =>
    '${d.year}-${_p2(d.month)}-${_p2(d.day)} ${_p2(d.hour)}:${_p2(d.minute)}';

// ---------------------------------------------------------------- shell

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) app.refreshOverlay();
  }

  Future<void> _boot() async {
    app.handleLaunch(); // cold start from a notification tap
    if (app.isRunning || !mounted) return;
    if (app.prefs.getBool('perms_asked') ?? false) {
      await _askAutostart(); // upgraded install: ask for the new permissions
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Permissions needed'),
        content: Text(
          'Notifications: to remind you at ${_t12(app.dailyHour, app.dailyMinute)}.\n\n'
          'Exact alarms: so the run fires on time, even when the phone is idle.\n\n'
          'Display over other apps (next screen): lets the app open itself at the daily time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    await Permission.notification.request();
    await Permission.scheduleExactAlarm.request();
    await app.prefs.setBool('perms_asked', true);
    await app.ensureDaily();
    if (!await Autostart.canOverlay()) await Autostart.openOverlaySettings();
  }

  Future<void> _askAutostart() async {
    await app.refreshOverlay();
    if (!app.autoStart || (app.overlayOk && app.fsiOk) || !mounted) return;
    final asks = app.prefs.getInt('autostart_asks') ?? 0;
    if (asks >= 3) return; // don't nag; the Home screen still shows a warning
    await app.prefs.setInt('autostart_asks', asks + 1);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Allow autostart'),
        content: Text([
          'To open itself at the daily time, Android needs:',
          if (!app.overlayOk) '• Display over other apps',
          if (!app.fsiOk) '• Full-screen notifications',
          '\nThe next screen opens the setting. Turn it on, then come back.',
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Open settings')),
        ],
      ),
    );
    if (!app.overlayOk) {
      await Autostart.openOverlaySettings();
    } else if (!app.fsiOk) {
      await Autostart.openFullScreenSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: app.tab,
      builder: (context, i, _) => Scaffold(
        body: SafeArea(
          bottom: false, // the navigation bar draws behind the gesture area itself
          child: IndexedStack(
            index: i,
            children: const [
              HomeScreen(),
              AccountsScreen(),
              RunScreen(),
              HistoryScreen(),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: (v) => app.tab.value = v,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home'),
            NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'Accounts'),
            NavigationDestination(
                icon: Icon(Icons.play_circle_outline),
                selectedIcon: Icon(Icons.play_circle),
                label: 'Run'),
            NavigationDestination(
                icon: Icon(Icons.history),
                selectedIcon: Icon(Icons.history_toggle_off),
                label: 'History'),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ shared ui

const _pad = EdgeInsets.fromLTRB(16, 8, 16, 24);

class _Title extends StatelessWidget {
  const _Title(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 16),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: cs.outline),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- home

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String _next() {
    final now = DateTime.now();
    var n = DateTime(now.year, now.month, now.day, app.dailyHour, app.dailyMinute);
    final today = n.isAfter(now);
    if (!today) n = n.add(const Duration(days: 1));
    final d = n.difference(now);
    final h = d.inHours, m = d.inMinutes % 60;
    return '${today ? 'Today' : 'Tomorrow'}  ·  in ${h > 0 ? '${h}h ' : ''}${m}m';
  }

  Future<void> _pick(BuildContext context) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: app.dailyHour, minute: app.dailyMinute),
    );
    if (t != null) await app.setDailyTime(t.hour, t.minute);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final dailyOk = app.pendingIds.contains(kDailyId);
        final h12 = app.dailyHour % 12 == 0 ? 12 : app.dailyHour % 12;
        final ampm = app.dailyHour < 12 ? 'AM' : 'PM';
        final ready = app.accountIds.where((i) => app.sessionSaved[i] == true).length;
        return ListView(
          padding: _pad,
          children: [
            const _Title('Daily Login Runner'),

            // ---- hero: next run
            Container(
              padding: const EdgeInsets.all(24),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(dailyOk ? Icons.alarm_on : Icons.alarm_off,
                          size: 20, color: cs.onPrimaryContainer),
                      const SizedBox(width: 8),
                      Text(dailyOk ? 'Scheduled' : 'Not scheduled',
                          style: tt.labelLarge?.copyWith(color: cs.onPrimaryContainer)),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Reschedule',
                        visualDensity: VisualDensity.compact,
                        color: cs.onPrimaryContainer,
                        icon: const Icon(Icons.refresh),
                        onPressed: app.ensureDaily,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: '$h12:${_p2(app.dailyMinute)}',
                          style: tt.displayLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.onPrimaryContainer)),
                      TextSpan(
                          text: ' $ampm',
                          style: tt.headlineSmall
                              ?.copyWith(color: cs.onPrimaryContainer)),
                    ]),
                  ),
                  Text(_next(),
                      style: tt.titleMedium?.copyWith(
                          color: cs.onPrimaryContainer.withValues(alpha: 0.8))),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: app.isRunning ? null : () => _pick(context),
                        icon: const Icon(Icons.schedule),
                        label: const Text('Change time'),
                      ),
                      const Spacer(),
                      Text('Autostart',
                          style: tt.labelLarge?.copyWith(color: cs.onPrimaryContainer)),
                      const SizedBox(width: 8),
                      Switch(
                        value: app.autoStart,
                        onChanged: app.isRunning ? null : app.setAutoStart,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (app.autoStart && !app.overlayOk)
              Card(
                color: cs.errorContainer,
                child: ListTile(
                  leading: Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
                  title: Text('Allow "Display over other apps"',
                      style: TextStyle(color: cs.onErrorContainer)),
                  subtitle: Text('Needed to open the app from the background',
                      style: TextStyle(color: cs.onErrorContainer)),
                  trailing: Icon(Icons.chevron_right, color: cs.onErrorContainer),
                  onTap: Autostart.openOverlaySettings,
                ),
              ),

            if (app.autoStart && app.overlayOk && !app.fsiOk)
              Card(
                color: cs.errorContainer,
                child: ListTile(
                  leading: Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
                  title: Text('Allow full-screen notifications',
                      style: TextStyle(color: cs.onErrorContainer)),
                  subtitle: Text('Fallback that wakes the screen and opens the app',
                      style: TextStyle(color: cs.onErrorContainer)),
                  trailing: Icon(Icons.chevron_right, color: cs.onErrorContainer),
                  onTap: Autostart.openFullScreenSettings,
                ),
              ),

            // ---- stats
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    icon: Icons.verified_user_outlined,
                    value: '$ready/${app.accountIds.length}',
                    label: 'Sessions ready',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Stat(
                    icon: Icons.task_alt,
                    value: app.lastSummary ??
                        (app.history.isEmpty
                            ? '—'
                            : '${app.history.first.okCount}/${app.history.first.results.length}'),
                    label: 'Last run',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SettingsCard(),
            _TestCard(),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.onSecondaryContainer),
          const SizedBox(height: 12),
          Text(value,
              style: tt.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600, color: cs.onSecondaryContainer)),
          Text(label, style: tt.bodyMedium?.copyWith(color: cs.onSecondaryContainer)),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timer_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Wait between accounts',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Text('${app.gapSeconds}s',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            Slider(
              value: app.gapSeconds.toDouble(),
              min: 0,
              max: 120,
              divisions: 24,
              label: '${app.gapSeconds}s',
              onChanged: app.isRunning ? null : (v) => app.setGap(v.round()),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final busy = app.isRunning;
    final none = app.selected.isEmpty;
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.science_outlined),
          title: const Text('Test tools'),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final id in app.accountIds)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(app.names[id] ?? id),
                value: app.selected.contains(id),
                onChanged: busy ? null : (v) => app.toggleSelected(id, v ?? false),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Quick waits'),
              subtitle: const Text('3s pre-logout wait, 3s between accounts, 40s login timeout'),
              value: app.quickWaits,
              onChanged: busy ? null : app.setQuick,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: busy || none || app.countdown > 0
                        ? null
                        : () => app.scheduleTest(),
                    child: Text(app.countdown > 0
                        ? 'Fires in ${app.countdown}s'
                        : 'Test in 30s'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy || none ? null : () => app.triggerRun('run-now'),
                    child: const Text('Run now'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Registered notification ids: ${app.pendingIds.isEmpty ? 'none' : app.pendingIds.join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- accounts

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  Future<void> _rename(BuildContext context, String id) async {
    final ctl = TextEditingController(text: app.names[id]);
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Account name'),
        content: TextField(controller: ctl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Save')),
        ],
      ),
    );
    if (v != null) await app.rename(id, v);
  }

  Future<void> _add(BuildContext context) async {
    final ctl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New account'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name (e.g. my-github-2)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Add')),
        ],
      ),
    );
    if (v != null) await app.addAccount(v);
  }

  Future<void> _delete(BuildContext context, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${app.names[id] ?? id}?'),
        content: Text('Its saved GitHub session will be deleted from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await app.removeAccount(id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => ListView(
        padding: _pad,
        children: [
          _Title(
            'Accounts',
            trailing: FilledButton.icon(
              onPressed: app.isRunning ? null : () => _add(context),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ),
          if (app.accountIds.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: _Empty(Icons.people_outline, 'No accounts yet'),
            ),
          for (final id in app.accountIds)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: _tone(cs, id).$2,
                          foregroundColor: _tone(cs, id).$3,
                          child: Text(
                            (app.names[id] ?? id).trim().isEmpty
                                ? '?'
                                : (app.names[id] ?? id).trim()[0].toUpperCase(),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(app.names[id] ?? id,
                                  style: tt.titleMedium,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(_tone(cs, id).$4,
                                      size: 16, color: _tone(cs, id).$5),
                                  const SizedBox(width: 6),
                                  Text(_tone(cs, id).$1,
                                      style: tt.bodyMedium
                                          ?.copyWith(color: _tone(cs, id).$5)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Rename',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _rename(context, id),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: app.isRunning ? null : () => _delete(context, id),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: app.isRunning
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => SetupScreen(id: id)),
                                ),
                        icon: Icon(app.sessionSaved[id] == true
                            ? Icons.refresh
                            : Icons.login),
                        label: Text(app.sessionSaved[id] == true
                            ? 'Re-login'
                            : 'Set up'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// (label, avatar bg, avatar fg, icon, text colour)
  (String, Color, Color, IconData, Color) _tone(ColorScheme cs, String id) {
    if (app.needsRelogin[id] == true) {
      return ('Needs re-login', cs.errorContainer, cs.onErrorContainer,
          Icons.warning_amber_rounded, cs.error);
    }
    if (app.sessionSaved[id] == true) {
      return ('Session saved', cs.primaryContainer, cs.onPrimaryContainer,
          Icons.check_circle, cs.primary);
    }
    return ('Not set up', cs.surfaceContainerHighest, cs.onSurfaceVariant,
        Icons.radio_button_unchecked, cs.onSurfaceVariant);
  }
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.id});
  final String id;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  InAppWebViewController? _c;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _prep();
  }

  Future<void> _prep() async {
    // start from a clean jar so the previous account's session isn't reused
    await CookieManager.instance().deleteAllCookies();
    try {
      await WebStorageManager.instance().deleteAllData();
    } catch (_) {}
    if (mounted) setState(() => _ready = true);
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    final r = await app.cookies.save(widget.id);
    if (!mounted) return;
    if (!r.hasSession) {
      _snack('No GitHub session found. Log in to GitHub first.');
      return;
    }
    await app.markSaved(widget.id);
    if (!mounted) return;
    _snack('Session saved (${r.count} cookies)');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Set up ${app.names[widget.id] ?? widget.id}'),
        actions: [
          IconButton(
            tooltip: 'Open agentrouter login (to approve GitHub Authorize once)',
            icon: const Icon(Icons.login),
            onPressed: () => _c?.loadUrl(
                urlRequest:
                    URLRequest(url: WebUri('https://agentrouter.org/login'))),
          ),
          TextButton(onPressed: _save, child: const Text('Save session')),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: InAppWebView(
                initialUrlRequest:
                    URLRequest(url: WebUri('https://github.com/login')),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  thirdPartyCookiesEnabled: true,
                ),
                onWebViewCreated: (c) => _c = c,
              ),
            ),
    );
  }
}

// ------------------------------------------------------------------ run

class RunScreen extends StatelessWidget {
  const RunScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri('about:blank')),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  thirdPartyCookiesEnabled: true,
                  supportMultipleWindows: false,
                ),
                onWebViewCreated: (c) {
                  app.engine.web = c;
                  if (!app.webReady.isCompleted) app.webReady.complete();
                },
                onLoadStop: (c, u) => app.engine.onLoadStop(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: app,
            builder: (context, _) => Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: app.isRunning ? cs.primaryContainer : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  if (app.isRunning)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  else
                    Icon(Icons.bedtime_outlined, size: 20, color: cs.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      app.isRunning ? 'Running: ${app.currentLabel ?? '...'}' : 'Idle',
                      style: TextStyle(
                          color: app.isRunning
                              ? cs.onPrimaryContainer
                              : cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
              ),
              child: ListenableBuilder(
                listenable: app,
                builder: (context, _) {
                  final lines = app.logLines.reversed.toList();
                  if (lines.isEmpty) {
                    return const _Empty(Icons.terminal, 'No log yet');
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: lines.length,
                    itemBuilder: (c, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        lines[i],
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- history

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  IconData _icon(String s) => switch (s) {
        'success' => Icons.check_circle,
        'timeout' => Icons.timer_off,
        'relogin' => Icons.warning_amber_rounded,
        _ => Icons.error,
      };

  Color _color(ColorScheme cs, String s) => switch (s) {
        'success' => cs.primary,
        'timeout' => cs.tertiary,
        'relogin' => cs.tertiary,
        _ => cs.error,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        return ListView(
          padding: _pad,
          children: [
            const _Title('History'),
            if (app.history.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: _Empty(Icons.history, 'No runs yet'),
              ),
            for (final r in app.history)
              Card(
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: r.okCount == r.results.length
                          ? cs.primaryContainer
                          : cs.errorContainer,
                      foregroundColor: r.okCount == r.results.length
                          ? cs.onPrimaryContainer
                          : cs.onErrorContainer,
                      child: Icon(r.okCount == r.results.length
                          ? Icons.check
                          : Icons.priority_high),
                    ),
                    title: Text(_fmt(r.startedAt)),
                    subtitle: Text(
                        '${r.isTest ? 'test · ' : ''}${r.source} · ${r.okCount}/${r.results.length} done'),
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    children: [
                      for (final a in r.results)
                        ListTile(
                          dense: true,
                          leading: Icon(_icon(a.status), color: _color(cs, a.status)),
                          title: Text('${a.name}: ${a.status}'),
                          subtitle: Text(
                              'step: ${a.step}${a.note != null ? ' · ${a.note}' : ''} · ${_fmt(a.at)}'),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}