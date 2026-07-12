import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/start_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState();
  await appState.init();
  runApp(OpenManidocApp(appState: appState));
}

class OpenManidocApp extends StatelessWidget {
  final AppState appState;

  const OpenManidocApp({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => MaterialApp(
        title: 'openManidoc',
        debugShowCheckedModeBanner: false,
        themeMode: appState.themeMode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4361EE)),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF7B9AFF),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: StartScreen(appState: appState),
      ),
    );
  }
}
