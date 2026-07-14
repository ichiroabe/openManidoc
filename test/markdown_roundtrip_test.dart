import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/widgets/code_block_markdown.dart';

/// エディタ(WysiwygEditor)は markdownToDocument→編集→documentToMarkdown で
/// データを往復させる。ここで欠落があると編集保存時にデータが失われる。
/// 特に appflowy_editor 6.2.0 は fenced code block の読込パーサを持たないため、
/// CodeBlockMarkdownParser で補っている。その round-trip を保証する。
void main() {
  // WysiwygEditor と同じ設定で往復させる
  String roundTrip(String md) {
    final doc = markdownToDocument(md,
        markdownParsers: const [CodeBlockMarkdownParser()]);
    return documentToMarkdown(doc).trimRight();
  }

  List<String> types(String md) {
    final doc = markdownToDocument(md,
        markdownParsers: const [CodeBlockMarkdownParser()]);
    return doc.root.children.toList().map((n) => n.type).toList();
  }

  test('fenced code block survives round-trip (no data loss)', () {
    const md = '```\n%APPDATA%\\Claude\\config.json\n```';
    expect(types(md), ['code']);
    expect(roundTrip(md), md);
  });

  test('fenced code block with language keeps language', () {
    const md = '```json\n{\n  "a": 1\n}\n```';
    expect(types(md), ['code']);
    expect(roundTrip(md), md);
  });

  test('code block between paragraphs is preserved (regression)', () {
    // 以前は前後の段落だけ残りコードが丸ごと消えていた
    const md = '前文\n\n```\ncode line\n```\n\n後文';
    expect(types(md), ['paragraph', 'code', 'paragraph']);
    final back = roundTrip(md);
    expect(back, contains('```\ncode line\n```'));
    expect(back, contains('前文'));
    expect(back, contains('後文'));
  });

  test('headings/lists/inline-code still round-trip', () {
    expect(roundTrip('# 見出し'), '# 見出し');
    expect(types('- a\n- b'), ['bulleted_list', 'bulleted_list']);
    expect(roundTrip('これは `inline` です'), 'これは `inline` です');
  });
}
