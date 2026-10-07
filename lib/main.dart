import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // draw behind the status bar and the navigation/gesture bar
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await app.init();
  runApp(const App());
}

/// Transparent system bars whose icons follow the theme brightness.
SystemUiOverlayStyle overlayFor(Brightness b) {
  final icons = b == Brightness.dark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: icons,
    statusBarBrightness: b, // iOS
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: icons,
    systemNavigationBarContrastEnforced: false,
  );
}

ThemeData _theme(ColorScheme cs) {
  const radius = BorderRadius.all(Radius.circular(24));
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: cs.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      systemOverlayStyle: overlayFor(cs.brightness),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cs.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.only(bottom: 12),
      shape: const RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cs.surfaceContainer,
      indicatorColor: cs.secondaryContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

class App extends StatelessWidget {
  const App({super.key});

  static const _seed = Colors.indigo;

  @override
  Widget build(BuildContext context) {
    // Material You colors from the wallpaper (Android 12+), indigo fallback.
    return DynamicColorBuilder(
      builder: (lightDyn, darkDyn) {
        final light = lightDyn?.harmonized() ??
            ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.light);
        final dark = darkDyn?.harmonized() ??
            ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark);
        return MaterialApp(
          title: 'Daily Login Runner',
          debugShowCheckedModeBanner: false,
          theme: _theme(light),
          darkTheme: _theme(dark),
          themeMode: ThemeMode.system, // follows the device light/dark mode
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayFor(Theme.of(context).brightness),
            child: child!,
          ),
          home: const Shell(),
        );
      },
    );
  }
}