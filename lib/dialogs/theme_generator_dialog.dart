import 'dart:convert';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n/strings.dart';
import '../services/ai_service.dart';

/// 🎨 テーマジェネレータ。本家互換の15種類のCSS変数をサポート。
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

  // 本家互換の全15プロパティマップ
  final props = <String, String>{
    '--main-bg-color': '#fcfcfc',
    '--text-main': '#1a1a1a',
    '--text-muted': '#444444',
    '--primary-color': '#0056b3',
    '--h1-gradient-start': '#0056b3',
    '--h1-gradient-end': '#00b4db',
    '--border-color': '#eeeeee',
    '--comment-bg': 'rgba(255, 255, 255, 0.7)',
    '--table-header-bg': '#f8f9fa',
    '--code-bg': '#f1f3f5',
    '--code-color': '#e03131',
    '--pre-bg': '#1a1a1b',
    '--pre-color': '#f8f8f2',
    '--article-font-size': '16px',
    '--comment-font-size': '16px',
  };

  final controllers = <String, TextEditingController>{};
  props.forEach((key, val) {
    controllers[key] = TextEditingController(text: val);
  });

  var accent = presetColors.first;
  var font = fonts.first;
  var fontSize = 16.0;
  final nameController = TextEditingController(text: defaultName);
  final hexController =
      TextEditingController(text: _hex(accent).substring(1)); // 先頭#は除く
  final promptController = TextEditingController();
  var isGenerating = false;

  // 初期値の同期
  props['--primary-color'] = _hex(accent);
  props['--h1-gradient-start'] = _hex(accent);
  props['--h1-gradient-end'] = _hex(accent);
  controllers['--primary-color']!.text = _hex(accent);
  controllers['--h1-gradient-start']!.text = _hex(accent);
  controllers['--h1-gradient-end']!.text = _hex(accent);

  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        // 本家互換の変数体系(--primary-color 等)で出力する
        String buildCss() {
          final sb = StringBuffer();
          sb.writeln('/* openManidoc theme: ${nameController.text} */');
          sb.writeln(':root {');
          props.forEach((key, val) {
            sb.writeln('  $key: $val;');
          });
          sb.writeln('}');
          sb.writeln('body { font-family: $font; }');
          return sb.toString();
        }

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
                  // ✨ AIデザインアシスタント
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: promptController,
                          enabled: !isGenerating,
                          decoration: InputDecoration(
                            labelText: L.t('ai_theme_prompt'),
                            hintText: '例: ダークテーマ、コードは緑、文字サイズ大',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: isGenerating || !app.settings.hasGeminiKey
                            ? null
                            : () async {
                                final pr = promptController.text.trim();
                                if (pr.isEmpty) return;
                                setState(() => isGenerating = true);
                                try {
                                  final ai = AiService(app.settings);
                                  final keys = props.keys.toList();
                                  final systemInstruction = '''
あなたは熟練のフロントエンドエンジニア・Webデザイナーです。
ユーザーの指示に従い、サイトのテーマとなるCSS変数の値を決定してください。

【対象となる変数のリスト】
${keys.join(', ')}

【注意】
- CSSやマークダウンブロック自体は出力しないでください。
- かならず、キーに変数の名前 (e.g. "--primary-color") 、値に変更後の色やサイズ（px単位、数値のみ、または "16px" などの形式）の文字列を入れた純粋なJSONオブジェクトのみを出力してください。
例:
{
  "--main-bg-color": "#121212",
  "--text-main": "#eeeeee",
  "--primary-color": "#bb86fc",
  "--article-font-size": "16px"
}
''';
                                  var res = await ai.generateText(pr,
                                      systemInstruction: systemInstruction);
                                  res = res
                                      .replaceAll('```json', '')
                                      .replaceAll('```', '')
                                      .trim();
                                  final data =
                                      jsonDecode(res) as Map<String, dynamic>;

                                  // パース結果を props および controllers に反映
                                  data.forEach((k, v) {
                                    if (props.containsKey(k)) {
                                      props[k] = v.toString();
                                      controllers[k]!.text = v.toString();

                                      // 個別変数への反映連動
                                      if (k == '--primary-color') {
                                        final c = _parseHex(v.toString());
                                        if (c != null) {
                                          accent = c;
                                          hexController.text = v
                                              .toString()
                                              .replaceAll('#', '');
                                        }
                                      }
                                      if (k == '--article-font-size') {
                                        final numStr = v
                                            .toString()
                                            .replaceAll('px', '')
                                            .trim();
                                        final size = double.tryParse(numStr);
                                        if (size != null) {
                                          fontSize =
                                              size.clamp(12.0, 22.0);
                                        }
                                      }
                                    }
                                  });

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content:
                                              Text(L.t('ai_theme_applied'))),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Error'),
                                        content: Text(
                                            L.t('ai_theme_failed', [e])),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('OK'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                } finally {
                                  setState(() => isGenerating = false);
                                }
                              },
                        icon: isGenerating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_awesome),
                        label: Text(L.t('generate')),
                      ),
                    ],
                  ),
                  if (!app.settings.hasGeminiKey)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        L.t('ai_unset_tip'),
                        style:
                            const TextStyle(color: Colors.orange, fontSize: 11),
                      ),
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
                            final hex = _hex(color);
                            hexController.text = hex.substring(1);
                            props['--primary-color'] = hex;
                            props['--h1-gradient-start'] = hex;
                            props['--h1-gradient-end'] = hex;
                            controllers['--primary-color']!.text = hex;
                            controllers['--h1-gradient-start']!.text = hex;
                            controllers['--h1-gradient-end']!.text = hex;
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
                            final c = _parseHex('#$v');
                            if (c != null) {
                              setState(() {
                                accent = c;
                                final hex = '#$v';
                                props['--primary-color'] = hex;
                                props['--h1-gradient-start'] = hex;
                                props['--h1-gradient-end'] = hex;
                                controllers['--primary-color']!.text = hex;
                                controllers['--h1-gradient-start']!.text = hex;
                                controllers['--h1-gradient-end']!.text = hex;
                              });
                            }
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
                          onChanged: (v) => setState(() {
                            fontSize = v;
                            final szStr = '${v.round()}px';
                            props['--article-font-size'] = szStr;
                            props['--comment-font-size'] = szStr;
                            controllers['--article-font-size']!.text = szStr;
                            controllers['--comment-font-size']!.text = szStr;
                          }),
                        ),
                      ),
                      Text('${fontSize.round()}px'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 15のプロパティ詳細設定
                  ExpansionTile(
                    title: const Text('詳細設定 (全15プロパティ)'),
                    children: [
                      for (final entry in props.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 160,
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (entry.key.contains('-color') ||
                                  entry.key.contains('-bg') ||
                                  entry.key.contains('gradient'))
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: _parseHex(entry.value) ??
                                        Colors.transparent,
                                    border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SizedBox(
                                  height: 32,
                                  child: TextField(
                                    controller: controllers[entry.key],
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                    ),
                                    onChanged: (val) {
                                      props[entry.key] = val;
                                      // プライマリカラーの同期
                                      if (entry.key == '--primary-color') {
                                        final c = _parseHex(val);
                                        if (c != null) {
                                          accent = c;
                                          hexController.text = val
                                              .replaceAll('#', '')
                                              .trim();
                                        }
                                      }
                                      setState(() {});
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // プレビュー
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _parseHex(props['--main-bg-color']!) ??
                          Colors.transparent,
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
                            style: TextStyle(
                                fontSize: fontSize,
                                color: _parseHex(props['--text-main']!) ??
                                    Theme.of(context)
                                        .colorScheme
                                        .onSurface)),
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
  if (s.length != 6) {
    if (s.startsWith('rgba')) {
      // rgba(r,g,b,a) 形式の簡易パース (透明度を除外して色を取得)
      final reg = RegExp(r'rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,.+\)');
      final match = reg.firstMatch(s);
      if (match != null) {
        final r = int.tryParse(match.group(1) ?? '0') ?? 0;
        final g = int.tryParse(match.group(2) ?? '0') ?? 0;
        final b = int.tryParse(match.group(3) ?? '0') ?? 0;
        return Color.fromARGB(255, r, g, b);
      }
    }
    return null;
  }
  final n = int.tryParse(s, radix: 16);
  if (n == null) return null;
  return Color(0xFF000000 | n);
}
