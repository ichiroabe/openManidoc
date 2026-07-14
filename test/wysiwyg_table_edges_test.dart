import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/services/markdown_io.dart';
import 'package:open_manidoc/widgets/code_block_markdown.dart';
import 'package:open_manidoc/widgets/wysiwyg_editor.dart';

void main() {
  String typeAt(Document doc, int i) => doc.root.children.toList()[i].type;
  int count(Document doc) => doc.root.children.length;

  test('table at both edges gets an editable paragraph before and after', () {
    const md = '| A | B |\n|---|---|\n| 1 | 2 |';
    final doc = markdownToDocument(md);
    // 前提: テーブルが唯一の(=先頭かつ末尾の)トップレベルノード
    expect(count(doc), 1);
    expect(typeAt(doc, 0), TableBlockKeys.type);

    ensureEditableEdgesAroundTables(doc);

    // 段落 / テーブル / 段落 になり、上下に書けるようになる
    expect(count(doc), 3);
    expect(typeAt(doc, 0), ParagraphBlockKeys.type);
    expect(typeAt(doc, 1), TableBlockKeys.type);
    expect(typeAt(doc, 2), ParagraphBlockKeys.type);
  });

  test('paragraph inserted between two adjacent tables', () {
    const md = '| A |\n|---|\n| 1 |\n\n| B |\n|---|\n| 2 |';
    final doc = markdownToDocument(md);
    ensureEditableEdgesAroundTables(doc);
    final types = doc.root.children.toList().map((n) => n.type).toList();
    // 先頭段落 / 表 / 段落 / 表 / 末尾段落
    expect(types.first, ParagraphBlockKeys.type);
    expect(types.last, ParagraphBlockKeys.type);
    final tableIdx = [
      for (var i = 0; i < types.length; i++)
        if (types[i] == TableBlockKeys.type) i
    ];
    expect(tableIdx.length, 2);
    // 2つの表の間に非テーブル(段落)がある
    expect(tableIdx[1] - tableIdx[0], greaterThan(1));
  });

  test('normal text document is left unchanged', () {
    final doc = markdownToDocument('# 見出し\n\n本文です。');
    final before = doc.root.children.length;
    ensureEditableEdgesAroundTables(doc);
    expect(doc.root.children.length, before);
  });

  test('code block at both edges gets editable paragraphs (same as table)',
      () {
    const md = '```json\n{"a": 1}\n```';
    final doc = markdownToDocument(md,
        markdownParsers: const [CodeBlockMarkdownParser()]);
    expect(count(doc), 1);
    expect(typeAt(doc, 0), 'code');

    ensureEditableEdgesAroundTables(doc);

    // 段落 / code / 段落 になり、上下に書けるようになる
    expect(count(doc), 3);
    expect(typeAt(doc, 0), ParagraphBlockKeys.type);
    expect(typeAt(doc, 1), 'code');
    expect(typeAt(doc, 2), ParagraphBlockKeys.type);
  });

  test('paragraph inserted between adjacent code and table blocks', () {
    const md = '```\ncode\n```\n\n| A |\n|---|\n| 1 |';
    final doc = markdownToDocument(md,
        markdownParsers: const [CodeBlockMarkdownParser()]);
    ensureEditableEdgesAroundTables(doc);
    final types = doc.root.children.toList().map((n) => n.type).toList();
    // 先頭と末尾に段落、code と table の間にも段落が入る
    expect(types.first, ParagraphBlockKeys.type);
    expect(types.last, ParagraphBlockKeys.type);
    final codeIdx = types.indexOf('code');
    final tableIdx = types.indexOf(TableBlockKeys.type);
    expect(tableIdx - codeIdx, greaterThan(1));
  });

  test('blank line is inserted between a table and following text', () {
    const md = '|A|B|\n|-|-|\n|1|2|\nどないすんねん\nABC';
    final fixed = fixTableMarkdownSpacing(md);
    // テーブル直後(|1|2| の後)に空行が入り、後続テキストが分離される
    expect(fixed, contains('|1|2|\n\nどないすんねん'));
    // 後続テキストを再パースするとテーブルの外(独立ブロック)になる
    final doc = markdownToDocument(fixed);
    final types = doc.root.children.toList().map((n) => n.type).toList();
    expect(types.where((t) => t == TableBlockKeys.type).length, 1);
    // テーブルの後に段落が存在する
    expect(types.last, ParagraphBlockKeys.type);
  });

  test('blank line is inserted before a table that follows text', () {
    const md = '前の段落\n|A|B|\n|-|-|\n|1|2|';
    final fixed = fixTableMarkdownSpacing(md);
    expect(fixed, contains('前の段落\n\n|A|B|'));
  });

  test('pipes inside fenced code block are left untouched', () {
    const md = '```\n|A|B|\nafter\n```';
    final fixed = fixTableMarkdownSpacing(md);
    expect(fixed, md); // フェンス内は変更しない
  });
}
