import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/app_state.dart';
import 'package:open_manidoc/dialogs/settings_dialog.dart';
import 'package:open_manidoc/l10n/strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ⚙設定ダイアログのローカルLLM欄: 🔄ボタン→一覧取得→ドロップダウン選択
void main() {
  late HttpServer server;
  late String origin;
  late List<String> served;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({}); // 保存はメモリ上のみ
    L.lang = 'ja';
    // flutter_test は既定でHTTPを塞ぐため、実サーバーに繋げるよう解除する
    HttpOverrides.global = null;
    served = ['gemma4:latest', 'qwen3-coder:30b'];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin = 'http://127.0.0.1:${server.port}';
    server.listen((request) {
      if (served.isEmpty) {
        request.response
          ..statusCode = 500
          ..close();
        return;
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'data': [for (final m in served) {'id': m}]
        }))
        ..close();
    });
  });

  tearDown(() async => server.close(force: true));

  Future<AppState> pumpSettings(WidgetTester tester) async {
    final app = AppState();
    app.settings
      ..aiProvider = 'LocalLLM'
      ..localLlmEndpoint = '$origin/v1'
      ..localLlmModel = '';

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showSettingsDialog(context, app),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return app;
  }

  // AIプロバイダ側にも DropdownButtonFormField があるのでキーで特定する
  final modelDropdown = find.byKey(const Key('local_model_dropdown'));

  /// 取得完了(CircularProgressIndicatorが消える)まで進める。
  /// 実HTTPは擬似時間では進まないので runAsync で実時間を渡す。
  Future<void> settleFetch(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
    }
    fail('モデル一覧の取得が終わらなかった');
  }

  testWidgets('🔄で取得したモデルがドロップダウンに並び、選ぶと設定に入る',
      (tester) async {
    final app = await pumpSettings(tester);

    // 取得前は手入力のTextField(ドロップダウンは出ていない)
    expect(modelDropdown, findsNothing);

    await tester.tap(find.byIcon(Icons.refresh));
    await settleFetch(tester);

    // ドロップダウンに変わる。未設定なので選択は「カスタム」のまま
    expect(modelDropdown, findsOneWidget);
    expect(find.text('カスタム (手入力)'), findsOneWidget);

    // 開くとサーバーのモデルが並ぶ → qwen3-coder:30b を選ぶ
    await tester.tap(modelDropdown);
    await tester.pumpAndSettle();
    expect(find.text('gemma4:latest'), findsWidgets);
    await tester.tap(find.text('qwen3-coder:30b').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(app.settings.localLlmModel, 'qwen3-coder:30b');
  });

  testWidgets('取得し直して一覧が入れ替わっても壊れない', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byIcon(Icons.refresh));
    await settleFetch(tester);
    await tester.tap(modelDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('qwen3-coder:30b').last);
    await tester.pumpAndSettle();

    // 別サーバーに繋ぎ替えた想定: 選択中のモデルが一覧から消える
    served = ['llama3.1:8b'];
    await tester.tap(find.byIcon(Icons.refresh));
    await settleFetch(tester);

    expect(tester.takeException(), isNull);
    expect(modelDropdown, findsOneWidget);
    // 一覧から消えた選択はカスタム扱いに落ち、モデル名は手入力欄に残る
    expect(find.text('カスタム (手入力)'), findsOneWidget);
    expect(find.text('qwen3-coder:30b'), findsOneWidget);
    // 新しい一覧から選び直せる
    await tester.tap(modelDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('llama3.1:8b').last);
    await tester.pumpAndSettle();
    expect(find.text('llama3.1:8b'), findsOneWidget);
  });

  testWidgets('取得に失敗したらエラー文言を出して手入力のまま', (tester) async {
    served = []; // サーバーが両経路とも500を返す
    await pumpSettings(tester);

    await tester.tap(find.byIcon(Icons.refresh));
    await settleFetch(tester);

    expect(modelDropdown, findsNothing);
    expect(find.textContaining('モデル一覧を取得できませんでした'), findsOneWidget);
  });
}
