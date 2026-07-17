import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../app_state.dart';
import '../l10n/strings.dart';
import '../services/ai_service.dart';
import '../services/html_exporter.dart';

/// 🎨 テーマジェネレータ(本家Manidoc互換)。
/// 保存済みテーマの一覧・読み込み・編集(上書き保存)・削除・新規に対応。
/// 生成されるCSSは本家と同じ自己完結型フルCSS(:root + 全スタイル)。
/// 戻り値: 最後に保存/選択したテーマのファイル名(何もせず閉じたら null)。
Future<String?> showThemeGeneratorDialog(
    BuildContext context, AppState app, String defaultName) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        _ThemeGeneratorDialog(app: app, defaultName: defaultName),
  );
}

/// テーマの1プロパティ(本家 ThemeProperty 相当)
class _ThemeProp {
  _ThemeProp(this.key, this.displayName, this.defaultValue,
      {this.isColor = true})
      : value = defaultValue;
  final String key;
  final String displayName;
  final String defaultValue;
  final bool isColor;
  String value;
  bool enabled = true;
}

class _ThemeGeneratorDialog extends StatefulWidget {
  const _ThemeGeneratorDialog({required this.app, required this.defaultName});
  final AppState app;
  final String defaultName;

  @override
  State<_ThemeGeneratorDialog> createState() => _ThemeGeneratorDialogState();
}

class _ThemeGeneratorDialogState extends State<_ThemeGeneratorDialog> {
  // 本家互換の全15プロパティ
  late final List<_ThemeProp> _props;
  final Map<String, TextEditingController> _valueCtrls = {};

  // Inter既定 + openManidocの選択肢
  static const _interFont =
      "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Hiragino Kaku Gothic ProN', Meiryo, sans-serif";
  final List<String> _fonts = const [
    _interFont,
    '"Segoe UI", "Hiragino Sans", "Noto Sans JP", sans-serif',
    '"Georgia", "Yu Mincho", serif',
    '"Consolas", "Courier New", monospace',
    '"Yu Gothic UI", "Meiryo", sans-serif',
  ];
  late String _font = _fonts.first;

  final _nameCtrl = TextEditingController();
  final _promptCtrl = TextEditingController();
  final _rawCssCtrl = TextEditingController();

  List<String> _themeFiles = [];
  String? _selectedFile;
  String _currentCss = '';
  String _status = '';
  bool _isGenerating = false;
  int _tab = 0; // 0=ビジュアル, 1=生CSS

  String? _resultFileName;

  @override
  void initState() {
    super.initState();
    _props = _buildDefaultProps();
    for (final p in _props) {
      _valueCtrls[p.key] = TextEditingController(text: p.value);
    }
    _nameCtrl.text = widget.defaultName;
    _rebuildCss();
    _loadThemeList();
  }

  @override
  void dispose() {
    for (final c in _valueCtrls.values) {
      c.dispose();
    }
    _nameCtrl.dispose();
    _promptCtrl.dispose();
    _rawCssCtrl.dispose();
    super.dispose();
  }

  static String _dn(String ja, String en) => L.isJa ? ja : en;

  List<_ThemeProp> _buildDefaultProps() => [
        _ThemeProp('--main-bg-color', _dn('背景色', 'Background'), '#fcfcfc'),
        _ThemeProp('--text-main', _dn('本文の色', 'Text'), '#1a1a1a'),
        _ThemeProp('--text-muted', _dn('補足の色', 'Muted text'), '#444444'),
        _ThemeProp('--primary-color', _dn('アクセント色', 'Primary'), '#0056b3'),
        _ThemeProp('--h1-gradient-start', _dn('H1 開始色', 'H1 start'), '#0056b3'),
        _ThemeProp('--h1-gradient-end', _dn('H1 終了色', 'H1 end'), '#00b4db'),
        _ThemeProp('--border-color', _dn('境界線の色', 'Border'), '#eeeeee'),
        _ThemeProp('--comment-bg', _dn('コメント背景', 'Comment bg'),
            'rgba(255, 255, 255, 0.7)'),
        _ThemeProp('--table-header-bg', _dn('表ヘッダ背景', 'Table header'),
            '#f8f9fa'),
        _ThemeProp('--code-bg', _dn('コード背景', 'Code bg'), '#f1f3f5'),
        _ThemeProp('--code-color', _dn('コード文字色', 'Code text'), '#e03131'),
        _ThemeProp('--pre-bg', _dn('コードブロック背景', 'Pre bg'), '#1a1a1b'),
        _ThemeProp('--pre-color', _dn('コードブロック文字', 'Pre text'), '#f8f8f2'),
        _ThemeProp('--article-font-size', _dn('本文サイズ', 'Article size'), '16px',
            isColor: false),
        _ThemeProp('--comment-font-size', _dn('コメントサイズ', 'Comment size'),
            '16px',
            isColor: false),
  ];

  // ---------- CSS 構築・解析 ----------

  void _rebuildCss() {
    final vars = <String, String>{};
    for (final p in _props.where((p) => p.enabled)) {
      vars[p.key] = p.value;
    }
    _currentCss = HtmlExporter.buildThemeCss(vars, font: _font);
    _rawCssCtrl.text = _currentCss;
  }

  Map<String, String> _parseRootVars(String css) {
    final result = <String, String>{};
    final rootMatch =
        RegExp(r':root\s*\{([^}]+)\}', dotAll: true).firstMatch(css);
    if (rootMatch == null) return result;
    final body = rootMatch.group(1) ?? '';
    for (final m
        in RegExp(r'(--[a-zA-Z0-9\-]+)\s*:\s*([^;]+);').allMatches(body)) {
      result[m.group(1)!.trim()] = m.group(2)!.trim();
    }
    return result;
  }

  String? _parseFont(String css) {
    final m =
        RegExp(r'body\s*\{[^}]*font-family\s*:\s*([^;]+);', dotAll: true)
            .firstMatch(css);
    return m?.group(1)?.trim();
  }

  // ---------- テーマ一覧・読込・保存・削除・新規 ----------

  Future<void> _loadThemeList() async {
    final ws = widget.app.workspace;
    if (ws == null) return;
    final files = await ws.listThemeCssFiles();
    if (!mounted) return;
    setState(() => _themeFiles = files);
  }

  Future<void> _loadTheme(String fileName) async {
    final ws = widget.app.workspace;
    if (ws == null) return;
    final css = await ws.readThemeCss(fileName);
    if (css == null || !mounted) return;

    final vars = _parseRootVars(css);
    for (final p in _props) {
      if (vars.containsKey(p.key)) {
        p.enabled = true;
        p.value = vars[p.key]!;
        _valueCtrls[p.key]!.text = p.value;
      } else {
        p.enabled = false;
      }
    }
    final font = _parseFont(css);
    if (font != null) {
      // 既知フォントに一致すればドロップダウンに反映(先頭トークン比較)
      final firstTok = font.split(',').first.trim();
      final match = _fonts.firstWhere(
          (f) => f.split(',').first.trim() == firstTok,
          orElse: () => '');
      if (match.isNotEmpty) _font = match;
    }
    setState(() {
      _selectedFile = fileName;
      _nameCtrl.text = fileName.replaceAll(RegExp(r'\.css$'), '');
      _rebuildCss();
      _status = L.t('theme_loaded', [fileName]);
    });
  }

  Future<void> _save() async {
    final ws = widget.app.workspace;
    if (ws == null) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _status = L.t('theme_name_empty'));
      return;
    }
    // 生CSSタブで手編集された場合はその内容を、そうでなければ再構築結果を保存
    final css = _tab == 1 ? _rawCssCtrl.text : _currentCss;
    final fileName = await ws.saveThemeCss(name, css);
    _resultFileName = fileName;
    await _loadThemeList();
    if (!mounted) return;
    setState(() {
      _selectedFile = fileName;
      _status = L.t('theme_saved', [fileName]);
    });
  }

  Future<void> _deleteTheme() async {
    final ws = widget.app.workspace;
    if (ws == null || _selectedFile == null) return;
    final target = _selectedFile!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(L.t('theme_delete_confirm', [target])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(L.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(L.t('tg_delete_theme'))),
        ],
      ),
    );
    if (ok != true) return;
    await ws.deleteThemeCss(target);
    if (_resultFileName == target) _resultFileName = null;
    await _loadThemeList();
    if (!mounted) return;
    setState(() {
      _selectedFile = null;
      _status = L.t('theme_deleted', [target]);
    });
  }

  void _newTheme() {
    for (final p in _props) {
      p.enabled = true;
      p.value = p.defaultValue;
      _valueCtrls[p.key]!.text = p.value;
    }
    // ユニークな名前を生成
    final base = L.t('tg_new_theme_base');
    var name = base;
    var i = 1;
    while (_themeFiles.contains('$name.css')) {
      name = '${base}_${i++}';
    }
    setState(() {
      _font = _fonts.first;
      _selectedFile = null;
      _nameCtrl.text = name;
      _rebuildCss();
      _status = L.t('theme_reset_done');
    });
  }

  void _resetToDefault() {
    for (final p in _props) {
      p.enabled = true;
      p.value = p.defaultValue;
      _valueCtrls[p.key]!.text = p.value;
    }
    setState(() {
      _font = _fonts.first;
      _rebuildCss();
      _status = L.t('theme_reset_done');
    });
  }

  // ---------- AI 生成 ----------

  Future<void> _generateWithAi() async {
    final pr = _promptCtrl.text.trim();
    if (pr.isEmpty) return;
    setState(() => _isGenerating = true);
    try {
      final ai = AiService(widget.app.settings);
      final keys = _props.map((p) => p.key).toList();
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
      var res =
          await ai.generateText(pr, systemInstruction: systemInstruction);
      res = res.replaceAll('```json', '').replaceAll('```', '').trim();
      final data = jsonDecode(res) as Map<String, dynamic>;
      for (final entry in data.entries) {
        for (final p in _props) {
          if (p.key == entry.key) {
            p.enabled = true;
            p.value = entry.value.toString();
            _valueCtrls[p.key]!.text = p.value;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _rebuildCss();
        _status = L.t('ai_theme_applied');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = L.t('ai_theme_failed', [e]));
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  // ---------- カラーピッカー ----------

  Future<void> _pickColor(_ThemeProp p) async {
    final initial = _parseHex(p.value) ?? Colors.white;
    var current = initial;
    final result = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.t('pick_color')),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: initial,
            onColorChanged: (c) => current = c,
            enableAlpha: false,
            hexInputBar: true,
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(L.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, current),
              child: Text(L.t('apply'))),
        ],
      ),
    );
    if (result == null) return;
    final hex = _hex(result);
    p.value = hex;
    _valueCtrls[p.key]!.text = hex;
    setState(_rebuildCss);
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(L.t('theme_gen_title'),
                      style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 200, child: _buildThemeListPane()),
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: _buildEditorPane()),
                    const SizedBox(width: 12),
                    SizedBox(width: 220, child: _buildPreviewPane()),
                  ],
                ),
              ),
              const Divider(height: 24),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemeListPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L.t('tg_saved_themes'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _newTheme,
                icon: const Icon(Icons.add, size: 16),
                label: Text(L.t('tg_new_theme')),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: L.t('tg_delete_theme'),
              onPressed: _selectedFile == null ? null : _deleteTheme,
              icon: const Icon(Icons.delete_outline),
              color: Colors.redAccent,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _themeFiles.isEmpty
                ? Center(
                    child: Text('—',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.outline)))
                : ListView.builder(
                    itemCount: _themeFiles.length,
                    itemBuilder: (context, i) {
                      final f = _themeFiles[i];
                      final sel = f == _selectedFile;
                      return ListTile(
                        dense: true,
                        selected: sel,
                        selectedTileColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        title: Text(f,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                        onTap: () => _loadTheme(f),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditorPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // AIデザインアシスタント
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _promptCtrl,
                enabled: !_isGenerating,
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
              onPressed: _isGenerating || !widget.app.settings.hasGeminiKey
                  ? null
                  : _generateWithAi,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(L.t('generate')),
            ),
          ],
        ),
        if (!widget.app.settings.hasGeminiKey)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(L.t('ai_unset_tip'),
                style: const TextStyle(color: Colors.orange, fontSize: 11)),
          ),
        const SizedBox(height: 12),
        // フォント + サイズ
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _font,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: L.t('font_family'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final f in _fonts)
                    DropdownMenuItem(
                      value: f,
                      child: Text(f.split(',').first.replaceAll('"', ''),
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _font = v;
                    _rebuildCss();
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // タブ切替
        Row(
          children: [
            _tabButton(0, L.t('tg_tab_visual')),
            const SizedBox(width: 8),
            _tabButton(1, L.t('tg_tab_raw_css')),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: _tab == 0 ? _buildVisualGrid() : _buildRawCssEditor()),
      ],
    );
  }

  Widget _tabButton(int index, String label) {
    final sel = _tab == index;
    return TextButton(
      onPressed: () => setState(() {
        // 生CSSタブから離れる際、手編集を _currentCss に取り込む
        if (_tab == 1 && index != 1) _currentCss = _rawCssCtrl.text;
        _tab = index;
      }),
      style: TextButton.styleFrom(
        backgroundColor: sel
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
      ),
      child: Text(label,
          style: TextStyle(
              fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
    );
  }

  Widget _buildVisualGrid() {
    return Container(
      decoration: BoxDecoration(
        border:
            Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _props.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final p = _props[i];
          return Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Checkbox(
                    value: p.enabled,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) => setState(() {
                      p.enabled = v ?? true;
                      _rebuildCss();
                    }),
                  ),
                ),
                SizedBox(
                  width: 92,
                  child: Text(p.displayName,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
                if (p.isColor) ...[
                  InkWell(
                    onTap: () => _pickColor(p),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _parseHex(p.value) ?? Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else
                  const SizedBox(width: 30),
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: TextField(
                      controller: _valueCtrls[p.key],
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                      ),
                      onChanged: (val) {
                        p.value = val;
                        setState(_rebuildCss);
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Text(p.key,
                      style: const TextStyle(
                          fontSize: 10, fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRawCssEditor() {
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: _rawCssCtrl,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: _resetToDefault,
              child: Text(L.t('tg_reset_default')),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => setState(() {
                _currentCss = _rawCssCtrl.text;
                _status = L.t('tg_apply_preview');
              }),
              child: Text(L.t('tg_apply_preview')),
            ),
          ],
        ),
      ],
    );
  }

  String _val(String key) =>
      _props.firstWhere((p) => p.key == key).value;

  Widget _buildPreviewPane() {
    final bg = _parseHex(_val('--main-bg-color')) ?? Colors.white;
    final textMain = _parseHex(_val('--text-main')) ?? Colors.black;
    final muted = _parseHex(_val('--text-muted')) ?? Colors.grey;
    final accent = _parseHex(_val('--primary-color')) ?? Colors.blue;
    final codeBg = _parseHex(_val('--code-bg')) ?? Colors.grey.shade200;
    final codeCol = _parseHex(_val('--code-color')) ?? Colors.red;
    final fs = double.tryParse(
            _val('--article-font-size').replaceAll(RegExp(r'[^0-9.]'), '')) ??
        16;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L.t('tg_preview'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('見出しタイトル',
                      style: TextStyle(
                          color: accent,
                          fontSize: (fs + 8).clamp(14, 40),
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                        border: Border(
                            left: BorderSide(color: accent, width: 4))),
                    child: Text('第1章 見出しレベル2',
                        style: TextStyle(
                            color: textMain,
                            fontSize: (fs + 2).clamp(12, 30),
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 8),
                  Text('本文サンプル。人間とAIが同じツリーに書き込む知性です。',
                      style: TextStyle(color: textMain, fontSize: fs)),
                  const SizedBox(height: 6),
                  Text('補足コメント (muted)',
                      style: TextStyle(
                          color: muted,
                          fontSize: fs - 2,
                          fontStyle: FontStyle.italic)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                        color: codeBg,
                        borderRadius: BorderRadius.circular(4)),
                    child: Text('code()',
                        style: TextStyle(
                            color: codeCol,
                            fontSize: fs - 2,
                            fontFamily: 'monospace')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Row(
      children: [
        Expanded(
          child: Text(_status,
              style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.outline)),
        ),
        SizedBox(
          width: 180,
          child: TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: L.t('theme_name'),
              suffixText: '.css',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 12),
        TextButton(
          onPressed: () => Navigator.pop(context, _resultFileName),
          child: Text(L.t('tg_close')),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _save,
          child: Text(L.t('tg_save')),
        ),
      ],
    );
  }
}

String _hex(Color c) =>
    '#${((c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round()).toRadixString(16).padLeft(6, '0')}';

Color? _parseHex(String v) {
  var s = v.replaceAll('#', '').trim();
  if (s.length != 6) {
    if (s.startsWith('rgba') || s.startsWith('rgb')) {
      final reg = RegExp(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)');
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
