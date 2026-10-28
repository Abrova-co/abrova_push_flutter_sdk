import 'package:flutter/material.dart';
import 'package:abrova_push/abrova_push.dart';

import 'screens/home_screen.dart';

import 'services/abrova_push_service.dart';

/// Global navigator key for navigation from callbacks
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AbrovaPushMessage? initialMessage;

  try {
    // Initialize AbrovaPush SDK
    debugPrint('[Example] Initializing AbrovaPush SDK...');
    await AbrovaPushService.instance.initialize();
    debugPrint('[Example] AbrovaPush SDK initialized successfully');

    // Check if app was launched from a notification
    initialMessage = await AbrovaPush.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[Example] App launched from notification: ${initialMessage.title}');
    }
  } catch (e, stackTrace) {
    debugPrint('[Example] Error during initialization: $e');
    debugPrint('[Example] Stack trace: $stackTrace');
  }

  runApp(AbrovaPushExampleApp(
    initialMessage: initialMessage,
  ));
}

class AbrovaPushExampleApp extends StatelessWidget {
  final AbrovaPushMessage? initialMessage;

  const AbrovaPushExampleApp({
    super.key,
    this.initialMessage,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'AbrovaPush Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      themeMode: ThemeMode.system,
      home: HomeScreen(initialMessage: initialMessage),
    );
  }
}
