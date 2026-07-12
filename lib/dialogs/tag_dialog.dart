import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n/strings.dart';

/// 🏷 タグ設定ダイアログ。既存タグから選ぶか、新規入力する。
/// 確定したタグ文字列を返す(キャンセルはnull)。空文字=タグなし。
Future<String?> showTagDialog(
    BuildContext context, AppState app, String currentTag) {
  final controller = TextEditingController(text: currentTag);
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(L.t('tag_manage')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: L.t('tag_label'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (app.allTags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(L.t('tag_existing'),
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in app.allTags)
                      ActionChip(
                        label: Text(tag),
                        onPressed: () => setState(() => controller.text = tag),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(L.t('cancel'))),
          if (currentTag.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: Text(L.t('tag_none')),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(L.t('save')),
          ),
        ],
      ),
    ),
  );
}
