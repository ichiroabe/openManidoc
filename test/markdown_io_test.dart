import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/services/markdown_io.dart';

void main() {
  test('MD import builds heading hierarchy', () {
    const md = '''
前書きの文章です。

# 第1章

第1章の本文。

## 1-1節

節の本文。

# 第2章

第2章の本文。
''';
    final project = MarkdownIo.importAsProject('テスト', md);
    // 前書き + 第1章 + 第2章
    expect(project.rootNodes.length, 3);
    expect(project.rootNodes[0].title, 'はじめに');
    expect(project.rootNodes[1].title, '第1章');
    expect(project.rootNodes[1].children.single.title, '1-1節');
    expect(project.rootNodes[1].children.single.article, '節の本文。');
    expect(project.rootNodes[2].article, '第2章の本文。');
  });

  test('MD import routes blockquotes into the comment field', () {
    const md = '## 章1\n本文です。\n\n> これは注意書き\n> 続き\n';
    final project = MarkdownIo.importAsProject('Doc', md);
    final section = project.rootNodes.firstWhere((n) => n.title == '章1');
    expect(section.article, '本文です。');
    expect(section.comment, 'これは注意書き\n続き');
  });

  test('MD export produces numbered headings and comment quotes', () {
    final project = MarkdownIo.importAsProject('Doc', '# 章\n本文');
    project.rootNodes[0].comment = '注意点';
    final md = MarkdownIo.exportToMarkdown(project);
    expect(md, contains('## 1. 章'));
    expect(md, contains('> 注意点'));
  });
}
