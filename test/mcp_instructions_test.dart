import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/services/mcp_service.dart';

// MCPサーバーが initialize で返す instructions を、システムプロンプトに
// 足せる形にまとめられることを確認する。
// 実測(manidoc-cs v2.2.0)では 631文字の使い方説明が返っており、
// これを捨てていたためローカルLLMは save_article と append_article の
// 使い分けを知らないまま本文を上書きしていた。
void main() {
  final registry = McpRegistry.instance;

  setUp(() => registry.serverInstructions.clear());
  tearDown(() => registry.serverInstructions.clear());

  group('McpRegistry.instructionsBlock', () {
    test('指示文が無ければ null', () {
      expect(registry.instructionsBlock, isNull);
    });

    test('1サーバーならワークスペース名つきで本文が入る', () {
      registry.serverInstructions['manidoc_main'] =
          '追記したいときは append_article を使ってください。';

      final block = registry.instructionsBlock;
      expect(block, isNotNull);
      expect(block, contains('manidoc_main'));
      expect(block, contains('append_article'));
    });

    test('複数サーバーはどちらの指示も残る', () {
      registry.serverInstructions['manidoc_main'] = '本番の作法';
      registry.serverInstructions['manidoc_android'] = 'Android側の作法';

      final block = registry.instructionsBlock!;
      expect(block, contains('manidoc_main'));
      expect(block, contains('本番の作法'));
      expect(block, contains('manidoc_android'));
      expect(block, contains('Android側の作法'));
    });
  });
}
