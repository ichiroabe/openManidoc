import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:markdown/markdown.dart' as md;

/// appflowy_editor 6.2.0 は fenced code block(``` ```)の **読み込みパーサを持たない**ため、
/// markdownToDocument でコードブロックが丸ごと欠落し、編集→保存でデータが失われていた。
/// ここで `<pre><code>` を type 'code' のノード(delta=コード本文, language=言語)に変換する。
/// 書き出し(documentToMarkdown)側は CodeBlockNodeParser が標準で 'code' → ``` に戻すため、
/// これを markdownToDocument に渡すだけで round-trip がロスレスになる。
class CodeBlockMarkdownParser extends CustomMarkdownParser {
  const CodeBlockMarkdownParser();

  @override
  List<Node> transform(
    md.Node element,
    List<CustomMarkdownParser> parsers, {
    MarkdownListType listType = MarkdownListType.unknown,
    int? startNumber,
  }) {
    if (element is! md.Element) return [];
    // fenced/indented code block は <pre><code>...</code></pre> になる
    if (element.tag != 'pre') return [];

    final codeEl = element.children
            ?.whereType<md.Element>()
            .where((e) => e.tag == 'code')
            .firstOrNull ??
        element;

    var text = codeEl.textContent;
    // markdown パッケージはコード末尾に改行を付けるので1つだけ除去
    if (text.endsWith('\n')) text = text.substring(0, text.length - 1);

    // class="language-xxx" から言語を取り出す
    var language = '';
    final cls = codeEl.attributes['class'];
    if (cls != null && cls.startsWith('language-')) {
      language = cls.substring('language-'.length);
    }

    return [codeBlockNodeFromText(text, language: language)];
  }
}

/// type 'code' のノードを生成(6.2.0 には helper が無いので自前で組む)
Node codeBlockNodeFromText(String text, {String language = ''}) {
  return Node(
    type: 'code',
    attributes: {
      blockComponentDelta: (Delta()..insert(text)).toJson(),
      'language': language,
    },
  );
}
