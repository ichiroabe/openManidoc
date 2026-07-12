import 'package:flutter/material.dart';

/// Markdown挿入ツールバー。本家リッチエディタのツールバー相当:
/// B I S H1 H2 H3 ・ 1. 🔗 🖼 📅 🕒
class MarkdownToolbar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;
  final Future<String?> Function()? onPickImage; // 画像挿入(相対パスを返す)

  const MarkdownToolbar({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onPickImage,
  });

  /// 選択範囲を前後の記号で囲む(選択なしなら記号のみ挿入しカーソルを中へ)
  void _wrap(String before, [String? after]) {
    after ??= before;
    final text = controller.text;
    var sel = controller.selection;
    if (!sel.isValid) {
      sel = TextSelection.collapsed(offset: text.length);
    }
    final selected = sel.textInside(text);
    final replaced = '$before$selected$after';
    controller.value = TextEditingValue(
      text: sel.textBefore(text) + replaced + sel.textAfter(text),
      selection: TextSelection.collapsed(
          offset: sel.start + before.length + selected.length),
    );
    onChanged();
  }

  /// 選択範囲(または現在行)の各行頭にprefixを付ける。既に付いていれば外す。
  void _linePrefix(String Function(int index) prefix,
      {required Pattern removePattern}) {
    final text = controller.text;
    var sel = controller.selection;
    if (!sel.isValid) sel = TextSelection.collapsed(offset: text.length);
    // 行頭まで選択を広げる
    var start = sel.start;
    while (start > 0 && text[start - 1] != '\n') {
      start--;
    }
    var end = sel.end;
    while (end < text.length && text[end] != '\n') {
      end++;
    }
    final block = text.substring(start, end);
    final lines = block.split('\n');
    final allPrefixed =
        lines.every((l) => l.startsWith(removePattern) || l.trim().isEmpty);
    final newLines = <String>[];
    var counter = 1;
    for (final line in lines) {
      if (line.trim().isEmpty) {
        newLines.add(line);
      } else if (allPrefixed) {
        newLines.add(line.replaceFirst(removePattern, ''));
      } else {
        newLines.add('${prefix(counter++)}$line');
      }
    }
    final replaced = newLines.join('\n');
    controller.value = TextEditingValue(
      text: text.substring(0, start) + replaced + text.substring(end),
      selection: TextSelection.collapsed(offset: start + replaced.length),
    );
    onChanged();
  }

  void _insert(String snippet) {
    final text = controller.text;
    var sel = controller.selection;
    if (!sel.isValid) sel = TextSelection.collapsed(offset: text.length);
    controller.value = TextEditingValue(
      text: sel.textBefore(text) + snippet + sel.textAfter(text),
      selection: TextSelection.collapsed(offset: sel.start + snippet.length),
    );
    onChanged();
  }

  Widget _button(BuildContext context, String label, String tooltip,
      VoidCallback onPressed,
      {TextStyle? style}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Text(label,
              style: style ??
                  const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border:
            Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _button(context, 'B', '太字', () => _wrap('**')),
          _button(context, 'I', '斜体', () => _wrap('*'),
              style: const TextStyle(
                  fontSize: 13, fontStyle: FontStyle.italic)),
          _button(context, 'S', '取り消し線', () => _wrap('~~'),
              style: const TextStyle(
                  fontSize: 13,
                  decoration: TextDecoration.lineThrough)),
          const SizedBox(width: 4),
          _button(context, 'H1', '見出し1',
              () => _linePrefix((_) => '# ', removePattern: RegExp(r'^#{1,6} '))),
          _button(context, 'H2', '見出し2',
              () => _linePrefix((_) => '## ', removePattern: RegExp(r'^#{1,6} '))),
          _button(context, 'H3', '見出し3',
              () => _linePrefix((_) => '### ', removePattern: RegExp(r'^#{1,6} '))),
          const SizedBox(width: 4),
          _button(context, '・', '箇条書き',
              () => _linePrefix((_) => '- ', removePattern: RegExp(r'^- '))),
          _button(context, '1.', '番号付きリスト',
              () => _linePrefix((i) => '$i. ',
                  removePattern: RegExp(r'^\d+\. '))),
          const SizedBox(width: 4),
          _button(context, '🔗', 'リンク挿入', () => _wrap('[', '](URL)')),
          if (onPickImage != null)
            _button(context, '🖼', '画像を挿入', () async {
              final rel = await onPickImage!();
              if (rel != null) _insert('![]($rel)');
            }),
          const SizedBox(width: 4),
          _button(
              context,
              '📅',
              '日付を挿入',
              () => _insert(
                  '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}')),
          _button(
              context,
              '🕒',
              '日時を挿入',
              () => _insert(
                  '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}')),
        ],
      ),
    );
  }
}
