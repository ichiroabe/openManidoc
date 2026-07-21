import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/services/ai_service.dart';

/// ローカルLLMのモデル一覧取得。実サーバー(localhost)を立てて経路ごと検証する。
void main() {
  late HttpServer server;
  late String origin;
  // テストごとに差し替えるハンドラ
  late void Function(HttpRequest) handler;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin = 'http://127.0.0.1:${server.port}';
    server.listen((request) => handler(request));
  });

  tearDown(() async => server.close(force: true));

  test('OpenAI互換の /models から取得する', () async {
    handler = (request) {
      expect(request.uri.path, '/v1/models');
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'data': [
            {'id': 'qwen3-coder:30b'},
            {'id': 'gemma4:latest'},
          ]
        }))
        ..close();
    };

    final models = await AiService.listLocalModels('$origin/v1');
    expect(models, ['gemma4:latest', 'qwen3-coder:30b']); // ソート済み
  });

  test('/models が使えなければ Ollama の /api/tags にフォールバックする', () async {
    final paths = <String>[];
    handler = (request) {
      paths.add(request.uri.path);
      if (request.uri.path == '/api/tags') {
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'models': [
              {'name': 'gemma4:26b-mlx'},
              {'name': 'gemma4:latest'},
            ]
          }))
          ..close();
        return;
      }
      request.response
        ..statusCode = 404
        ..close();
    };

    // 末尾の /v1 を落として /api/tags を叩けること
    final models = await AiService.listLocalModels('$origin/v1/');
    expect(paths, ['/v1/models', '/api/tags']);
    expect(models, ['gemma4:26b-mlx', 'gemma4:latest']);
  });

  test('どちらも失敗したら AiException', () async {
    handler = (request) => request.response
      ..statusCode = 500
      ..close();

    expect(
      () => AiService.listLocalModels('$origin/v1'),
      throwsA(isA<AiException>()),
    );
  });

  test('エンドポイント未入力は AiException', () async {
    expect(
      () => AiService.listLocalModels('   '),
      throwsA(isA<AiException>()),
    );
  });
}
