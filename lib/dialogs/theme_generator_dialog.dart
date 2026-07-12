import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n/strings.dart';

/// 🎨 テーマジェネレータ。アクセント色・フォント・文字サイズからHTML出力用の
/// テーマCSSを生成し、workspace/themes/ へ保存してファイル名を返す(キャンセルはnull)。
Future<String?> showThemeGeneratorDialog(
    BuildContext context, AppState app, String defaultName) {
  const presetColors = <Color>[
    Color(0xFF4361EE),
    Color(0xFF7B2FF7),
    Color(0xFF2EC4B6),
    Color(0xFFE63946),
    Color(0xFFFF9F1C),
    Color(0xFF06D6A0),
    Color(0xFF118AB2),
    Color(0xFF222222),
  ];
  const fonts = <String>[
    '"Segoe UI", "Hiragino Sans", "Noto Sans JP", sans-serif',
    '"Georgia", "Yu Mincho", serif',
    '"Consolas", "Courier New", monospace',
    '"Yu Gothic UI", "Meiryo", sans-serif',
  ];

  var accent = presetColors.first;
  var font = fonts.first;
  var fontSize = 16.0;
  final nameController = TextEditingController(text: defaultName);
  final hexController =
      TextEditingController(text: _hex(accent).substring(1)); // 先頭#は除く

  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        String buildCss() => '''
/* openManidoc theme: ${nameController.text} */
:root { --accent: ${_hex(accent)}; }
body { font-family: $font; font-size: ${fontSize.round()}px; }
h1, header h1 { color: ${_hex(accent)}; }
h2, h3, h4, h5, h6 { border-left-color: ${_hex(accent)}; }
nav#toc a:hover { background: ${_hex(accent)}; }
''';

        return AlertDialog(
          title: Text(L.t('theme_gen_title')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: L.t('theme_name'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Text(L.t('accent_color'),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final color in presetColors)
                        InkWell(
                          onTap: () => setState(() {
                            accent = color;
                            hexController.text = _hex(color).substring(1);
                          }),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: accent == color
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: hexController,
                          decoration: const InputDecoration(
                            prefixText: '#',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            final c = _parseHex(v);
                            if (c != null) setState(() => accent = c);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(L.t('font_family'),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  DropdownButton<String>(
                    value: font,
                    isExpanded: true,
                    items: [
                      for (final f in fonts)
                        DropdownMenuItem(
                          value: f,
                          child: Text(f.split(',').first.replaceAll('"', ''),
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => font = v!),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(L.t('base_font_size')),
                      Expanded(
                        child: Slider(
                          value: fontSize,
                          min: 12,
                          max: 22,
                          divisions: 10,
                          label: '${fontSize.round()}px',
                          onChanged: (v) => setState(() => fontSize = v),
                        ),
                      ),
                      Text('${fontSize.round()}px'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // プレビュー
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            border: Border(
                                left: BorderSide(color: accent, width: 5)),
                          ),
                          child: Text('1. 見出しサンプル',
                              style: TextStyle(
                                  color: accent,
                                  fontSize: fontSize + 4,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 6),
                        Text('本文サンプルテキスト abc 123',
                            style: TextStyle(fontSize: fontSize)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(L.t('cancel'))),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim().isEmpty
                    ? defaultName
                    : nameController.text.trim();
                final fileName =
                    await app.workspace!.saveThemeCss(name, buildCss());
                if (context.mounted) Navigator.pop(context, fileName);
              },
              child: Text(L.t('generate')),
            ),
          ],
        );
      },
    ),
  );
}

String _hex(Color c) =>
    '#${((c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round()).toRadixString(16).padLeft(6, '0')}';

Color? _parseHex(String v) {
  var s = v.replaceAll('#', '').trim();
  if (s.length != 6) return null;
  final n = int.tryParse(s, radix: 16);
  if (n == null) return null;
  return Color(0xFF000000 | n);
}
