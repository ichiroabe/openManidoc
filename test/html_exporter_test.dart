import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/models/manidoc_node.dart';
import 'package:open_manidoc/models/manidoc_project.dart';
import 'package:open_manidoc/services/html_exporter.dart';
import 'package:open_manidoc/services/workspace_service.dart';

void main() {
  test('exported HTML uses Manidoc-compatible classes and applies theme CSS',
      () async {
    final tmp = await Directory.systemTemp.createTemp('om_export_test');
    final ws = WorkspaceService(tmp.path);

    final project = ManidocProject(name: 'テスト手順書')
      ..rootNodes = [
        ManidocNode(title: '導入', article: '本文です。', comment: '注意点')
          ..children = [ManidocNode(title: '前提', article: '準備事項')],
      ];
    await ws.saveProject(project);

    // 本家形式のテーマ: :root 変数を上書きする
    const theme = ':root { --primary-color: #ff00aa; }\n'
        '.article-body { font-weight: bold; }';

    final outDir = '${tmp.path}${Platform.pathSeparator}out';
    await HtmlExporter(ws).export(project, outDir, themeCss: theme);
    final html =
        await File('$outDir${Platform.pathSeparator}index.html').readAsString();

    // 本家互換のクラス名・構造
    expect(html, contains('class="node-container" id="node-'));
    expect(html, contains('class="article-body"'));
    expect(html, contains('class="comment-box"'));
    expect(html, contains('class="content-wrapper"'));
    expect(html, contains('<nav id="sidebar">'));
    expect(html, contains('class="toc-child"'));

    // ベースCSSの後にテーマCSSが注入され、変数を上書きできる
    final basePos = html.indexOf('--primary-color: #0056b3;');
    final themePos = html.indexOf('--primary-color: #ff00aa;');
    expect(basePos, greaterThanOrEqualTo(0));
    expect(themePos, greaterThan(basePos)); // テーマが後 = 上書きが効く

    await tmp.delete(recursive: true);
  });
}
