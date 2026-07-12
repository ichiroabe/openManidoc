import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/start_screen.dart';
import 'services/link_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // エディタ内リンク(Ctrl/ダブルクリック)を openManidoc 側で処理する。
  // #node:id はノード遷移、http(s) はブラウザ起動(activeLinkHandlerが振り分ける)。
  editorLaunchUrl = (href) async {
    final handler = activeLinkHandler;
    if (href != null && handler != null) {
      handler(href);
      return true;
    }
    return false;
  };
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
