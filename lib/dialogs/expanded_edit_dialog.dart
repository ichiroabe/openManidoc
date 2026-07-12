import 'package:flutter/material.dart';

import '../l10n/strings.dart';

/// 📝 編集拡大: 画面いっぱいの独立エディタ。確定した文字列を返す(キャンセルはnull)。
Future<String?> showExpandedEditDialog(
    BuildContext context, String title, String initialText) {
  final controller = TextEditingController(text: initialText);
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
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(L.t('reflect_close')),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
      ),
    ),
  );
}
