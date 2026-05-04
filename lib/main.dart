import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'viewmodels/home_viewmodel.dart';
import 'screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/navigation_service.dart';
import 'screens/history_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {
    // .env 파일이 없어도 앱은 실행됩니다.
  }

  runApp(const HarugyeolApp());
}

class HarugyeolApp extends StatelessWidget {
  const HarugyeolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HomeViewModel(),
      child: const _HarugyeolShell(),
    );
  }
}

class _HarugyeolShell extends StatefulWidget {
  const _HarugyeolShell();

  @override
  State<_HarugyeolShell> createState() => _HarugyeolShellState();
}

class _HarugyeolShellState extends State<_HarugyeolShell> {
  bool _showOnboarding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool('onboarding_seen') ?? false;
      if (!mounted) return;
      setState(() => _showOnboarding = !seen);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '하루결',
      navigatorKey: NavigationService.navigatorKey,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (context, child) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: child,
        );
      },
      routes: {
        '/history': (_) => const HistoryScreen(autoOpenLatest: true),
      },
      home: _showOnboarding
          ? OnboardingScreen(
              onFinish: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('onboarding_seen', true);
                if (!mounted) return;
                setState(() => _showOnboarding = false);
              },
            )
          : const HomeScreen(),
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6F8F6C),
    brightness: brightness,
  );
  final actionColor =
      isDark ? const Color(0xFFC8E0BE) : const Color(0xFF315E39);
  final disabledColor =
      isDark ? const Color(0xFF6D746C) : const Color(0xFF9AA198);

  return ThemeData(
    colorScheme: scheme.copyWith(
      primary: actionColor,
      secondary: const Color(0xFFB56F4C),
      surface: isDark ? const Color(0xFF141812) : const Color(0xFFFFFAF3),
    ),
    useMaterial3: true,
    brightness: brightness,
    appBarTheme: AppBarTheme(
      backgroundColor:
          isDark ? const Color(0xFF141812) : const Color(0xFFFFFAF3),
      foregroundColor: actionColor,
      iconTheme: IconThemeData(color: actionColor, size: 25),
      actionsIconTheme: IconThemeData(color: actionColor, size: 25),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return disabledColor;
          return actionColor;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return Colors.transparent;
          if (states.contains(WidgetState.pressed)) {
            return actionColor.withValues(alpha: 0.16);
          }
          return Colors.transparent;
        }),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: actionColor,
        foregroundColor: isDark ? const Color(0xFF102014) : Colors.white,
        disabledBackgroundColor: disabledColor.withValues(alpha: 0.35),
        disabledForegroundColor: disabledColor,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: actionColor),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return actionColor;
        return disabledColor;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return actionColor.withValues(alpha: 0.35);
        }
        return disabledColor.withValues(alpha: 0.22);
      }),
    ),
  );
}
