import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'viewmodels/home_viewmodel.dart';
import 'services/background_service.dart';
import 'screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/navigation_service.dart';
import 'screens/history_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {
    // .env 파일이 없어도 앱은 실행되도록 허용
  }

  runApp(const AiDiaryApp());
}

class AiDiaryApp extends StatefulWidget {
  const AiDiaryApp({super.key});

  @override
  State<AiDiaryApp> createState() => _AiDiaryAppState();
}

class _AiDiaryAppState extends State<AiDiaryApp> {
  bool _showOnboarding = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vm = context.read<HomeViewModel>();
      BackgroundService.configure(vm);
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool('onboarding_seen') ?? false;
      setState(() => _showOnboarding = !seen);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HomeViewModel()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'AI 그림일기',
        navigatorKey: NavigationService.navigatorKey,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF82B1FF),
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF82B1FF),
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.system,
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
      ),
    );
  }
}



