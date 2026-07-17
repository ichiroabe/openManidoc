import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/services/html_exporter.dart';
import 'package:open_manidoc/services/workspace_service.dart';

/// テーマジェネレータ(本家互換)の「一覧→読込→編集→上書き保存→削除」データ経路を、
/// ダイアログが内部で使うのと同じ処理(buildThemeCss + :root パース + WorkspaceService)で検証する。
/// UIウィジェット層ではなく、編集ロジックそのものの回帰テスト。
void main() {
  late Directory tmp;
  late WorkspaceService ws;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('om_theme_edit');
    ws = WorkspaceService(tmp.path);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  // ダイアログ _parseRootVars と同一のロジック
  Map<String, String> parseRootVars(String css) {
    final out = <String, String>{};
    final root =
        RegExp(r':root\s*\{([^}]+)\}', dotAll: true).firstMatch(css);
    if (root == null) return out;
    for (final m in RegExp(r'(--[a-zA-Z0-9\-]+)\s*:\s*([^;]+);')
        .allMatches(root.group(1)!)) {
      out[m.group(1)!.trim()] = m.group(2)!.trim();
    }
    return out;
  }

  test('保存→一覧→読込→編集→上書き→削除 が一貫して動く', () async {
    // 1. 本家形式フルCSSテーマを保存
    final fn = await ws.saveThemeCss(
      '未来',
      HtmlExporter.buildThemeCss({
        '--main-bg-color': '#0A0E1A',
        '--text-main': '#E0E6F0',
        '--primary-color': '#5DE7F6',
        '--article-font-size': '18px',
      }),
    );
    expect(fn, '未来.css');

    // 2. 一覧に出る
    expect(await ws.listThemeCssFiles(), contains('未来.css'));

    // 3. 読込 → :root がパースでき、値がそのまま取り出せる(=編集フォームに載る)
    final loaded = await ws.readThemeCss('未来.css');
    expect(loaded, isNotNull);
    final vars = parseRootVars(loaded!);
    expect(vars['--primary-color'], '#5DE7F6');
    expect(vars['--article-font-size'], '18px');
    // 未指定の変数はテーマに含まれない(=フォームでは無効扱い)
    expect(vars.containsKey('--code-color'), isFalse);

    // 4. アクセント色を編集して再構築 → 上書き保存(同名)
    vars['--primary-color'] = '#123456';
    await ws.saveThemeCss('未来', HtmlExporter.buildThemeCss(vars));

    // 5. 再読込で編集が反映され、かつ本家形式(自己完結フルCSS)を保つ
    final reloaded = (await ws.readThemeCss('未来.css'))!;
    expect(reloaded, contains('--primary-color: #123456;'));
    expect(reloaded, contains('body { font-family:'));
    expect(reloaded, contains('#sidebar'));
    expect(reloaded, contains('.article-body'));
    // 上書きなのでファイルは1つのまま
    expect((await ws.listThemeCssFiles()).length, 1);

    // 6. 削除 → 一覧から消える
    await ws.deleteThemeCss('未来.css');
    expect(await ws.listThemeCssFiles(), isEmpty);
    expect(File('${tmp.path}/themes/未来.css').existsSync(), isFalse);
  });

  test('複数テーマの並列運用と個別削除', () async {
    await ws.saveThemeCss('a', HtmlExporter.buildThemeCss({'--primary-color': '#111111'}));
    await ws.saveThemeCss('b', HtmlExporter.buildThemeCss({'--primary-color': '#222222'}));
    await ws.saveThemeCss('c', HtmlExporter.buildThemeCss({'--primary-color': '#333333'}));
    expect((await ws.listThemeCssFiles()).length, 3);

    await ws.deleteThemeCss('b.css');
    final rest = await ws.listThemeCssFiles();
    expect(rest, containsAll(['a.css', 'c.css']));
    expect(rest, isNot(contains('b.css')));
  });
}
