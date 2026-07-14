import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import '../services/markdown_io.dart';

/// テーブルはテキストブロックでないため、ドキュメントの先頭/末尾/テーブル同士の
/// 間にテーブルが来るとカーソルを置ける段落が無く「上下を編集できない」状態になる。
/// そうした位置に空の段落を挿入し、常にテーブルの前後に書けるようにする。
void ensureEditableEdgesAroundTables(Document doc) {
  bool isTable(Node? n) => n != null && n.type == TableBlockKeys.type;
  final nodes = doc.root.children.toList();

  // 元の並びを基準に「段落を挿入すべき位置(そのindexの直前)」を集める。
  // index == nodes.length は末尾への追加を意味する。
  final positions = <int>{};
  for (var i = 0; i < nodes.length; i++) {
    if (!isTable(nodes[i])) continue;
    // テーブルの前が編集可能でなければ、その前に段落を入れる
    if (i == 0 || isTable(nodes[i - 1])) positions.add(i);
    // テーブルの後が編集可能でなければ、その後に段落を入れる
    if (i == nodes.length - 1 || isTable(nodes[i + 1])) positions.add(i + 1);
  }

  // 後ろの位置から挿入すれば、前方のindexがずれない
  final sorted = positions.toList()..sort((a, b) => b.compareTo(a));
  for (final p in sorted) {
    doc.insert([p], [paragraphNode()]);
  }
}

/// 選択時に出るツールバー項目(見出し/太字/斜体/リスト/引用/リンク)
final List<ToolbarItem> _wysiwygToolbarItems = [
  paragraphItem,
  ...headingItems,
  placeholderItem,
  ...markdownFormatItems,
  placeholderItem,
  quoteItem,
  bulletedListItem,
  numberedListItem,
  placeholderItem,
  linkItem,
];

/// Markdownを内部データとして扱う WYSIWYG(見たまま)エディタ。
/// - 表示時: Markdown → ドキュメント
/// - 編集時: ドキュメント → Markdown を onChanged で返す
/// リンクは装飾表示され、選択すると太字/見出し/リスト/リンク等のツールバーが出る。
///
/// ノードが切り替わるたびに作り直したいので、親側で `key: ValueKey(nodeId)` を付けて使う。
class WysiwygEditor extends StatefulWidget {
  final String initialMarkdown;
  final ValueChanged<String> onChanged;

  /// エディタの固定高さ(内部でスクロール)
  final double height;

  /// `[[` 入力時に呼ばれ、選ばれたノードの id/title を返す(キャンセルはnull)。
  /// 返ってきたら `[title](#node:id)` リンクとして挿入する。
  final Future<({String id, String title})?> Function()? onPickNodeLink;

  const WysiwygEditor({
    super.key,
    required this.initialMarkdown,
    required this.onChanged,
    this.height = 260,
    this.onPickNodeLink,
  });

  @override
  State<WysiwygEditor> createState() => _WysiwygEditorState();
}

class _WysiwygEditorState extends State<WysiwygEditor> {
  late EditorState _editorState;
  late EditorScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    final md = widget.initialMarkdown.trim();
    final doc = md.isEmpty
        ? Document.blank(withInitialText: true)
        : markdownToDocument(md);
    ensureEditableEdgesAroundTables(doc);
    _editorState = EditorState(document: doc);
    _scrollController = EditorScrollController(editorState: _editorState);
    // 実際の編集が起きたときだけMarkdownを親へ返す(単なる表示では発火しない)
    _editorState.transactionStream.listen((_) {
      if (!mounted) return;
      widget.onChanged(
          fixTableMarkdownSpacing(documentToMarkdown(_editorState.document)));
    });
  }

  /// `[[` を検出してノードリンクを挿入する文字ショートカット
  late final CharacterShortcutEvent _nodeLinkShortcut = CharacterShortcutEvent(
    key: 'node link',
    character: '[',
    handler: (editorState) async {
      final onPick = widget.onPickNodeLink;
      if (onPick == null) return false;
      final sel = editorState.selection;
      if (sel == null || !sel.isCollapsed) return false;
      final node = editorState.getNodeAtPath(sel.end.path);
      final delta = node?.delta;
      if (node == null || delta == null) return false;
      final plain = delta.toPlainText();
      final offset = sel.end.offset;
      // 直前の文字が '[' のとき(= '[[')だけ発火。それ以外は通常入力。
      if (offset <= 0 || offset > plain.length || plain[offset - 1] != '[') {
        return false;
      }
      final picked = await onPick();
      if (picked == null || !mounted) return false; // キャンセル→'['を通常入力
      final tr = editorState.transaction;
      // 直前の '[' をリンク付きタイトルに置換する
      tr.replaceText(node, offset - 1, 1, picked.title,
          attributes: {AppFlowyRichTextKeys.href: '#node:${picked.id}'});
      await editorState.apply(tr);
      return true; // 2つ目の '[' は消費
    },
  );

  @override
  void dispose() {
    _scrollController.dispose();
    _editorState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = EditorStyle.desktop(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.28),
      textStyleConfiguration: TextStyleConfiguration(
        text: TextStyle(fontSize: 15, color: scheme.onSurface, height: 1.5),
        href: TextStyle(
          color: scheme.primary,
          decoration: TextDecoration.underline,
        ),
      ),
    );

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: FloatingToolbar(
        items: _wysiwygToolbarItems,
        editorState: _editorState,
        editorScrollController: _scrollController,
        textDirection: TextDirection.ltr,
        child: AppFlowyEditor(
          editorState: _editorState,
          editorScrollController: _scrollController,
          editable: true,
          editorStyle: style,
          characterShortcutEvents: [
            _nodeLinkShortcut,
            ...standardCharacterShortcutEvents,
          ],
        ),
      ),
    );
  }
}
