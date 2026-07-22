import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await themeController.load();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const NqeApp());
}

class NqeApp extends StatelessWidget {
  const NqeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'NQE',
          debugShowCheckedModeBanner: false,
          theme: buildNqeTheme(Brightness.light),
          darkTheme: buildNqeTheme(Brightness.dark),
          themeMode: themeController.mode,
          home: const SplashScreen(),
        );
      },
    );
  }
}
