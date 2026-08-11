import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/services/mcp_service.dart';

// ルート直下の allowedTools は Claude 系(Agent SDK / Claude Code)と同じ書式。
// 同じ設定ファイルを Claude Desktop とそのままやり取りできるようにするための対応。
//
//   "allowedTools": ["mcp__manidoc-cs__list_*", "mcp__other__*"]
void main() {
  group('parseGlobalAllowedTools', () {
    test('未指定なら null(制限なし)', () {
      expect(
          McpConfig.parseGlobalAllowedTools(
              '{"mcpServers": {"a": {"command": "x"}}}'),
          isNull);
    });

    test('配列を読み取れる', () {
      const raw = '''
{
  "mcpServers": { "manidoc-cs": { "command": "x" } },
  "allowedTools": ["mcp__manidoc-cs__list_*", "mcp__other__*"]
}
''';
      expect(McpConfig.parseGlobalAllowedTools(raw),
          ['mcp__manidoc-cs__list_*', 'mcp__other__*']);
    });

    test('配列でなければエラー', () {
      expect(
          () => McpConfig.parseGlobalAllowedTools(
              '{"mcpServers": {}, "allowedTools": "x"}'),
          throwsFormatException);
      expect(
          McpConfig.validate('{"mcpServers": {"a": {"command": "x"}},'
              ' "allowedTools": "x"}'),
          isNotNull);
    });
  });

  group('matchesGlobalAllowed', () {
    test('null は制限なし', () {
      expect(McpConfig.matchesGlobalAllowed(null, 'manidoc-cs', 'save_article'),
          isTrue);
    });

    test('完全一致', () {
      const p = ['mcp__manidoc-cs__list_projects'];
      expect(
          McpConfig.matchesGlobalAllowed(p, 'manidoc-cs', 'list_projects'), isTrue);
      expect(McpConfig.matchesGlobalAllowed(p, 'manidoc-cs', 'save_article'),
          isFalse);
    });

    test('ワイルドカードで前方一致', () {
      const p = ['mcp__manidoc-cs__list_*'];
      expect(
          McpConfig.matchesGlobalAllowed(p, 'manidoc-cs', 'list_nodes'), isTrue);
      expect(McpConfig.matchesGlobalAllowed(p, 'manidoc-cs', 'get_article'),
          isFalse);
    });

    test('サーバー丸ごと許可', () {
      const p = ['mcp__other__*'];
      expect(McpConfig.matchesGlobalAllowed(p, 'other', 'anything'), isTrue);
      expect(
          McpConfig.matchesGlobalAllowed(p, 'manidoc-cs', 'anything'), isFalse);
    });

    test('ハイフンを含むサーバー名でも壊れない(正規表現エスケープ)', () {
      const p = ['mcp__manidoc-cs__*'];
      expect(McpConfig.matchesGlobalAllowed(p, 'manidoc-cs', 'add_node'), isTrue);
      // "-" が正規表現として解釈されると manidocXcs 等に誤マッチしうる
      expect(McpConfig.matchesGlobalAllowed(p, 'manidocXcs', 'add_node'), isFalse);
    });

    test('複数パターンはいずれかに当たればよい', () {
      const p = ['mcp__manidoc-cs__add_node', 'mcp__manidoc-cs__append_article'];
      expect(McpConfig.matchesGlobalAllowed(p, 'manidoc-cs', 'add_node'), isTrue);
      expect(McpConfig.matchesGlobalAllowed(p, 'manidoc-cs', 'append_article'),
          isTrue);
      expect(McpConfig.matchesGlobalAllowed(p, 'manidoc-cs', 'save_article'),
          isFalse);
    });
  });
}
