import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../widgets/wysiwyg_editor.dart';

/// 📝 編集拡大: 画面いっぱいの独立エディタ。確定したMarkdownを返す(キャンセルはnull)。
/// 通常編集と同じ WYSIWYG(WysiwygEditor)を使う。`[[` でノードリンクも挿入可。
Future<String?> showExpandedEditDialog(
  BuildContext context,
  String title,
  String initialText, {
  Future<({String id, String title})?> Function()? onPickNodeLink,
}) {
  // WysiwygEditor は onChanged で最新Markdownを返す(未編集なら初期値のまま)
  var current = initialText;
  return showDialog<String>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text('📝 $title'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context, current),
              child: Text(L.t('reflect_close')),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) => WysiwygEditor(
              initialMarkdown: initialText,
              height: constraints.maxHeight,
              onChanged: (md) => current = md,
              onPickNodeLink: onPickNodeLink,
            ),
          ),
        ),
      ),
    ),
  );
}
