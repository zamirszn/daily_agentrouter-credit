import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Bridge to the native alarm that launches the app by itself (Android only).
class Autostart {
  static const _c = MethodChannel('autostart');
  static bool get _on => Platform.isAndroid;

  static void listen(void Function() onAutorun) {
    if (!_on) return;
    _c.setMethodCallHandler((call) async {
      if (call.method == 'autorun') onAutorun();
    });
  }

  static Future<void> schedule(int hour, int minute) async {
    if (_on) await _c.invokeMethod('schedule', {'hour': hour, 'minute': minute});
  }

  static Future<void> cancel() async {
    if (_on) await _c.invokeMethod('cancel');
  }

  /// True once if this launch was started by the alarm.
  static Future<bool> consumeAutorun() async =>
      _on && (await _c.invokeMethod<bool>('consumeAutorun') ?? false);

  static Future<bool> canOverlay() async =>
      !_on || (await _c.invokeMethod<bool>('canOverlay') ?? false);

  static Future<void> openOverlaySettings() async {
    if (_on) await _c.invokeMethod('openOverlaySettings');
  }

  /// Real touch tap at (x, y) in physical pixels, relative to the visible WebView.
  static Future<bool> tap(double x, double y) async =>
      _on && (await _c.invokeMethod<bool>('tap', {'x': x, 'y': y}) ?? false);

  static Future<bool> canFullScreen() async =>
      !_on || (await _c.invokeMethod<bool>('canFullScreen') ?? true);

  static Future<void> openFullScreenSettings() async {
    if (_on) await _c.invokeMethod('openFullScreenSettings');
  }

  static Future<void> bringToFront() async {
    if (_on) await _c.invokeMethod('bringToFront');
  }

  static Future<void> keepAwake(bool on) async {
    if (_on) await _c.invokeMethod('keepAwake', {'on': on});
  }
}