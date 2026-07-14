import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import 'code_block_markdown.dart';

/// `/` スラッシュメニューの「コードブロック」項目。
/// 空のコードブロックを挿入し、続けて書けるよう直後に空段落も入れる
/// (divider_menu_item と同じ挿入パターン)。内容は✏️/ダブルクリックで編集する。
SelectionMenuItem codeBlockMenuItem = SelectionMenuItem(
  getName: () => L.t('code_block'),
  icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
    icon: Icons.code,
    isSelected: isSelected,
    style: style,
  ),
  keywords: ['code', 'codeblock', 'code block', 'コード'],
  handler: (editorState, _, _) {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) return;
    final path = selection.end.path;
    final node = editorState.getNodeAtPath(path);
    final delta = node?.delta;
    if (node == null || delta == null) return;
    final insertedPath = delta.isEmpty ? path : path.next;
    final transaction = editorState.transaction
      ..insertNode(insertedPath, codeBlockNodeFromText(''))
      ..insertNode(insertedPath.next, paragraphNode())
      ..afterSelection =
          Selection.collapsed(Position(path: insertedPath.next));
    editorState.apply(transaction);
  },
);

/// appflowy_editor 6.2.0 は type 'code' の描画ビルダーを持たないため、
/// コードブロックがエディタ上でエラー表示になっていた。ここで読み取り専用の
/// コードブロック描画を提供する(等幅・背景付き。ブロックとして選択/削除は可能)。
///
/// divider_block_component と同じ SelectableMixin パターンで、テキスト編集はせず
/// ブロック単位の選択・カーソル移動のみ対応する(内容編集は将来対応)。
/// データ自体は [CodeBlockMarkdownParser] と標準エンコーダで保持される。
class CodeBlockComponentBuilder extends BlockComponentBuilder {
  CodeBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return CodeBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => true;
}

class CodeBlockComponentWidget extends BlockComponentStatefulWidget {
  const CodeBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<CodeBlockComponentWidget> createState() =>
      _CodeBlockComponentWidgetState();
}

class _CodeBlockComponentWidgetState extends State<CodeBlockComponentWidget>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  final codeKey = GlobalKey();
  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  String get _code => node.delta?.toPlainText() ?? '';
  String get _language => (node.attributes['language'] as String?) ?? '';

  /// ✏️ コード編集ダイアログ(等幅TextField + 言語欄)。確定でノードを更新する。
  Future<void> _editCode() async {
    final editorState = context.read<EditorState>();
    final codeController = TextEditingController(text: _code);
    final langController = TextEditingController(text: _language);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.t('edit_code')),
        content: SizedBox(
          width: 640,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: langController,
                decoration: InputDecoration(
                  labelText: L.t('code_language'),
                  hintText: 'json / powershell / text ...',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 320,
                child: TextField(
                  controller: codeController,
                  autofocus: true,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration:
                      const InputDecoration(border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(L.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(L.t('apply'))),
        ],
      ),
    );
    if (result != true || !mounted) return;
    final tr = editorState.transaction;
    tr.updateNode(node, {
      blockComponentDelta: (Delta()..insert(codeController.text)).toJson(),
      'language': langController.text.trim(),
    });
    await editorState.apply(tr);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget child = GestureDetector(
      onDoubleTap: _editCode, // ダブルクリックでも編集
      child: Container(
        key: codeKey,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_language.isNotEmpty)
                  Text(
                    _language,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const Spacer(),
                Tooltip(
                  message: L.t('edit_code_tip'),
                  child: InkWell(
                    onTap: _editCode,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.edit,
                          size: 16, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            ),
            SelectableText(
              _code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.4,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );

    child = Padding(padding: padding, child: child);

    final editorState = context.read<EditorState>();
    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      cursorColor: editorState.editorStyle.cursorColor,
      selectionColor: editorState.editorStyle.selectionColor,
      supportTypes: const [
        BlockSelectionType.block,
        BlockSelectionType.cursor,
        BlockSelectionType.selection,
      ],
      child: child,
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    return child;
  }

  // --- SelectableMixin(divider と同じブロック選択の実装)---

  @override
  Position start() => Position(path: widget.node.path, offset: 0);

  @override
  Position end() => Position(path: widget.node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) {
    return getRectsInSelection(Selection.invalid()).firstOrNull ?? Rect.zero;
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    if (_renderBox == null) return null;
    return getRectsInSelection(
      Selection.collapsed(position),
      shiftWithBaseOffset: shiftWithBaseOffset,
    ).firstOrNull;
  }

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    if (_renderBox == null) return [];
    final parentBox = context.findRenderObject();
    final codeBox = codeKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && codeBox is RenderBox) {
      return [
        (shiftWithBaseOffset
                ? codeBox.localToGlobal(Offset.zero, ancestor: parentBox)
                : Offset.zero) &
            codeBox.size,
      ];
    }
    return [Offset.zero & _renderBox!.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) => Selection.single(
        path: widget.node.path,
        startOffset: 0,
        endOffset: 1,
      );

  @override
  Offset localToGlobal(Offset offset, {bool shiftWithBaseOffset = false}) =>
      _renderBox!.localToGlobal(offset);

  @override
  TextDirection textDirection() => TextDirection.ltr;
}
