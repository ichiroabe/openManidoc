import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

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

  const WysiwygEditor({
    super.key,
    required this.initialMarkdown,
    required this.onChanged,
    this.height = 260,
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
    _editorState = EditorState(document: doc);
    _scrollController = EditorScrollController(editorState: _editorState);
    // 実際の編集が起きたときだけMarkdownを親へ返す(単なる表示では発火しない)
    _editorState.transactionStream.listen((_) {
      if (!mounted) return;
      widget.onChanged(documentToMarkdown(_editorState.document));
    });
  }

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
        ),
      ),
    );
  }
}
