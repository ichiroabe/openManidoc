import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/services/html_import.dart';
import 'package:open_manidoc/services/workspace_service.dart';

void main() {
  test('HTMLの表はヘッダー直後に区切り行を入れたMarkdown表になる', () async {
    final tmp = await Directory.systemTemp.createTemp('himport_');
    addTearDown(() => tmp.delete(recursive: true));
    final ws = WorkspaceService(tmp.path);

    const html = '''
<html><body>
<h1>メモリ要件</h1>
<p>以下は目安です。</p>
<table>
  <tr><th>モデルサイズ</th><th>必要メモリ</th></tr>
  <tr><td>7B〜8B</td><td>5〜8 GB</td></tr>
  <tr><td>70B</td><td>40〜48 GB</td></tr>
</table>
</body></html>
''';
    final file = File('${tmp.path}/doc.html');
    await file.writeAsString(html);

    final project = await HtmlImport.importHtmlFile(ws, file.path);
    final article = project.rootNodes.first.article;

    // ヘッダー行の直後に区切り行(| --- | --- |)が入っていること。
    // これが無いとMarkdownとして表に描画されない(今回の不具合)。
    expect(article, contains('| モデルサイズ | 必要メモリ |'));
    expect(article, contains('| --- | --- |'));
    expect(article, contains('| 7B〜8B | 5〜8 GB |'));

    // 区切り行はヘッダーの直後(先頭データ行より前)にあること。
    final headerIdx = article.indexOf('| モデルサイズ | 必要メモリ |');
    final sepIdx = article.indexOf('| --- | --- |');
    final firstDataIdx = article.indexOf('| 7B〜8B | 5〜8 GB |');
    expect(headerIdx, lessThan(sepIdx));
    expect(sepIdx, lessThan(firstDataIdx));
  });

  test('セル内の | と改行は表を壊さないようエスケープ/整形される', () async {
    final tmp = await Directory.systemTemp.createTemp('himport_');
    addTearDown(() => tmp.delete(recursive: true));
    final ws = WorkspaceService(tmp.path);

    const html = '''
<html><body>
<h1>T</h1>
<table>
  <tr><th>A</th><th>B</th></tr>
  <tr><td>x | y</td><td>line1
line2</td></tr>
</table>
</body></html>
''';
    final file = File('${tmp.path}/doc.html');
    await file.writeAsString(html);

    final project = await HtmlImport.importHtmlFile(ws, file.path);
    final article = project.rootNodes.first.article;

    // セル内の | はエスケープされ、改行は空白へ潰れる。
    expect(article, contains(r'x \| y'));
    expect(article, contains('| line1 line2 |'));
    // データ行が1行に収まっている(改行で行が割れていない)。
    expect(article, isNot(contains('line1\nline2')));
  });
}
