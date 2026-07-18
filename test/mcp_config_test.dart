import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/services/mcp_service.dart';

void main() {
  group('McpConfig.parse', () {
    test('Claude Desktop互換形式をパースできる', () {
      const raw = '''
{
  "mcpServers": {
    "manidoc_main": {
      "command": "dotnet",
      "args": ["C:\\\\x\\\\ManidocMCP.dll"],
      "env": { "MANIDOC_WORKSPACE": "G:\\\\ws1" }
    },
    "manidoc_android": {
      "command": "dotnet",
      "args": ["C:\\\\x\\\\ManidocMCP.dll"],
      "env": { "MANIDOC_WORKSPACE": "G:\\\\ws2" },
      "allowedTools": ["list_projects", "search_fulltext"]
    }
  }
}
''';
      final configs = McpConfig.parse(raw);
      expect(configs, hasLength(2));
      expect(configs[0].name, 'manidoc_main');
      expect(configs[0].command, 'dotnet');
      expect(configs[0].args, ['C:\\x\\ManidocMCP.dll']);
      expect(configs[0].env['MANIDOC_WORKSPACE'], 'G:\\ws1');
      expect(configs[0].allowedTools, isNull); // 未指定=全ツール公開
      expect(configs[1].allowedTools, ['list_projects', 'search_fulltext']);
    });

    test('雛形はそのままパースできる', () {
      final configs = McpConfig.parse(McpConfig.template);
      expect(configs, hasLength(1));
      expect(configs[0].name, 'manidoc');
      expect(configs[0].allowedTools, contains('search_fulltext'));
    });

    test('argsとenvは省略できる', () {
      final configs = McpConfig.parse(
          '{"mcpServers": {"a": {"command": "node"}}}');
      expect(configs.single.args, isEmpty);
      expect(configs.single.env, isEmpty);
    });

    test('不正入力はvalidateがエラーメッセージを返す', () {
      expect(McpConfig.validate('{'), isNotNull); // 構文エラー
      expect(McpConfig.validate('[]'), isNotNull); // ルートが配列
      expect(McpConfig.validate('{}'), isNotNull); // mcpServersなし
      expect(McpConfig.validate('{"mcpServers": {"a": {}}}'),
          isNotNull); // commandなし
      expect(
          McpConfig.validate(
              '{"mcpServers": {"日本語名": {"command": "x"}}}'),
          isNotNull); // サーバー名の文字種違反(ツール名規則に適合しない)
      expect(
          McpConfig.validate(
              '{"mcpServers": {"a": {"command": "x", "args": "notalist"}}}'),
          isNotNull); // argsが配列でない
      // 正常形はnull
      expect(McpConfig.validate('{"mcpServers": {"a": {"command": "x"}}}'),
          isNull);
    });
  });

  group('mcpSplitToolName', () {
    test('サーバー名__ツール名 を分解できる', () {
      expect(mcpSplitToolName('manidoc_main${mcpNsSep}search_fulltext'),
          ('manidoc_main', 'search_fulltext'));
    });

    test('区切りが無い/端にある名前はnull', () {
      expect(mcpSplitToolName('nounderscore'), isNull);
      expect(mcpSplitToolName('${mcpNsSep}tool'), isNull);
      expect(mcpSplitToolName('server$mcpNsSep'), isNull);
    });

    test('サーバー名にアンダースコアを含む場合は最初の区切りで分解', () {
      // manidoc_main__list_nodes → (manidoc_main, list_nodes)
      final r = mcpSplitToolName('manidoc_main__list_nodes');
      expect(r, ('manidoc_main', 'list_nodes'));
    });
  });
}
