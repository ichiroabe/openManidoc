import 'package:flutter/material.dart';
// colorFromHex 等の名前が color_utils と衝突するため、使うウィジェットだけ取り込む
import 'package:flutter_colorpicker/flutter_colorpicker.dart' show ColorPicker;

import '../app_state.dart';
import '../l10n/strings.dart';
import '../services/color_utils.dart';

/// カラーピッカーの結果。hexは '#rrggbb'、空文字は「既定(テーマ色)」。
/// 一括設定では applyFore / applyBack のチェックが付いた側だけ反映する。
class CardColorResult {
  final String fore;
  final String back;
  final bool applyFore;
  final bool applyBack;

  const CardColorResult({
    required this.fore,
    required this.back,
    this.applyFore = true,
    this.applyBack = true,
  });
}

/// プロジェクトタイルの文字色/背景色を選ぶダイアログ。
/// [bulkCount] が null 以外なら一括設定モード(適用対象のチェックを出す)。
Future<CardColorResult?> showCardColorDialog(
  BuildContext context,
  AppState app, {
  String initialFore = '',
  String initialBack = '',
  int? bulkCount,
}) {
  return showDialog<CardColorResult>(
    context: context,
    builder: (context) => _CardColorDialog(
      app: app,
      initialFore: initialFore,
      initialBack: initialBack,
      bulkCount: bulkCount,
    ),
  );
}

class _CardColorDialog extends StatefulWidget {
  final AppState app;
  final String initialFore;
  final String initialBack;
  final int? bulkCount;

  const _CardColorDialog({
    required this.app,
    required this.initialFore,
    required this.initialBack,
    required this.bulkCount,
  });

  @override
  State<_CardColorDialog> createState() => _CardColorDialogState();
}

class _CardColorDialogState extends State<_CardColorDialog> {
  late String _fore = widget.initialFore;
  late String _back = widget.initialBack;
  bool _editingBack = true; // 編集対象: true=背景色, false=文字色
  bool _applyFore = true;
  bool _applyBack = true;

  bool get _isBulk => widget.bulkCount != null;

  String get _current => _editingBack ? _back : _fore;

  set _current(String hex) {
    if (_editingBack) {
      _back = hex;
    } else {
      _fore = hex;
    }
  }

  /// 編集中の色(未設定ならテーマの既定色)
  Color get _currentColor =>
      colorFromHex(_current) ??
      (_editingBack
          ? Theme.of(context).colorScheme.surfaceContainerLow
          : Theme.of(context).colorScheme.onSurface);

  Future<void> _saveToSlot(int index) async {
    final hex = _current;
    if (hex.isEmpty) return;
    setState(() => widget.app.settings.cardPaletteColors[index] = hex);
    await widget.app.saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.app.settings.cardPaletteColors;
    return AlertDialog(
      title: Text(L.t('card_color_title')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isBulk) ...[
                Text(L.t('card_color_bulk_target', [widget.bulkCount!]),
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
              ],
              _buildPreview(context),
              const SizedBox(height: 6),
              _buildContrastLine(context),
              const SizedBox(height: 12),
              // 編集対象の切替
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                      value: true, label: Text(L.t('card_color_back'))),
                  ButtonSegment(
                      value: false, label: Text(L.t('card_color_fore'))),
                ],
                selected: {_editingBack},
                onSelectionChanged: (s) =>
                    setState(() => _editingBack = s.first),
              ),
              const SizedBox(height: 12),
              // 背景から計算した文字色の候補(文字色を編集しているときだけ)
              if (!_editingBack) _buildSuggestions(context),
              // パレット
              Text(L.t('card_color_palette_hint'),
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < palette.length; i++)
                    _buildSwatch(context, palette[i], i),
                ],
              ),
              const SizedBox(height: 12),
              // portraitOnly=false だと色相スライダーとHex欄が横に並び、
              // ダイアログ幅では見切れるため縦積みにする。
              ColorPicker(
                pickerColor: _currentColor,
                onColorChanged: (c) =>
                    setState(() => _current = hexFromColor(c)),
                enableAlpha: false,
                hexInputBar: true,
                portraitOnly: true,
                colorPickerWidth: 420,
                pickerAreaHeightPercent: 0.5,
              ),
              Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: Text(L.t('card_color_reset')),
                    onPressed: () => setState(() => _current = ''),
                  ),
                  if (_editingBack)
                    TextButton.icon(
                      icon: const Icon(Icons.contrast, size: 18),
                      label: Text(L.t('card_color_suggest')),
                      onPressed: () {
                        final bg = colorFromHex(_back);
                        if (bg == null) return;
                        setState(() =>
                            _fore = hexFromColor(contrastForegroundFor(bg)));
                      },
                    ),
                ],
              ),
              if (_isBulk) ...[
                const Divider(),
                CheckboxListTile(
                  value: _applyBack,
                  onChanged: (v) => setState(() => _applyBack = v ?? false),
                  title: Text(L.t('card_color_apply_back')),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: _applyFore,
                  onChanged: (v) => setState(() => _applyFore = v ?? false),
                  title: Text(L.t('card_color_apply_fore')),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(L.t('cancel'))),
        FilledButton(
          onPressed: (_isBulk && !_applyFore && !_applyBack)
              ? null
              : () => Navigator.pop(
                  context,
                  CardColorResult(
                    fore: _fore,
                    back: _back,
                    applyFore: !_isBulk || _applyFore,
                    applyBack: !_isBulk || _applyBack,
                  )),
          child: Text(L.t('apply')),
        ),
      ],
    );
  }

  /// いま選んでいる組み合わせの読みやすさ(コントラスト比)
  Widget _buildContrastLine(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final back = colorFromHex(_back) ?? scheme.surfaceContainerLow;
    final fore = colorFromHex(_fore) ?? contrastForegroundFor(back);
    final ratio = contrastRatio(fore, back);
    final (label, color) = ratio >= kReadableContrast
        ? (L.t('contrast_ok'), scheme.primary)
        : ratio >= 3.0
            ? (L.t('contrast_large_only'), scheme.tertiary)
            : (L.t('contrast_low'), scheme.error);
    return Row(
      children: [
        Text(L.t('contrast_label', [ratio.toStringAsFixed(2)]),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: 8),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }

  /// 背景色から計算した文字色の候補。クリックでその色を採用する。
  Widget _buildSuggestions(BuildContext context) {
    final back = colorFromHex(_back);
    if (back == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(L.t('suggest_need_bg'),
            style: Theme.of(context).textTheme.bodySmall),
      );
    }
    final suggestions = suggestForegrounds(back);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L.t('suggest_from_bg'),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final s in suggestions) _buildSuggestion(context, s, back),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestion(
      BuildContext context, ForegroundSuggestion s, Color back) {
    final scheme = Theme.of(context).colorScheme;
    final hex = hexFromColor(s.color);
    final selected = _fore.toLowerCase() == hex.toLowerCase();
    final enough = s.ratio >= kReadableContrast;
    return Tooltip(
      message: '${L.t('suggest_kind_${s.kind}')}  ${s.ratio.toStringAsFixed(2)}:1'
          '${enough ? '' : '  ${L.t('contrast_low')}'}',
      child: InkWell(
        onTap: () => setState(() {
          _fore = hex;
          _editingBack = false;
        }),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 実際の背景の上に文字色を乗せた見え方でプレビューする
              Container(
                width: 40,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: back,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: Text('Aa',
                    style: TextStyle(
                        color: s.color,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 2),
              Text(
                s.recommended
                    ? '${L.t('suggest_kind_${s.kind}')}★'
                    : L.t('suggest_kind_${s.kind}'),
                style: const TextStyle(fontSize: 10),
              ),
              Text(
                s.ratio.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 10,
                  color: enough ? scheme.outline : scheme.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 実際のカードに近い見た目のプレビュー
  Widget _buildPreview(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final back = colorFromHex(_back) ?? scheme.surfaceContainerLow;
    final fore = colorFromHex(_fore) ?? scheme.onSurface;
    return Center(
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: back,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L.t('card_color_preview_name'),
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: fore)),
            const SizedBox(height: 8),
            Text(L.t('card_color_preview_meta'),
                style: TextStyle(
                    fontSize: 12, color: blendOpaque(fore, back, 0.7))),
          ],
        ),
      ),
    );
  }

  Widget _buildSwatch(BuildContext context, String hex, int index) {
    final color = colorFromHex(hex) ?? Colors.transparent;
    final selected = _current.toLowerCase() == hex.toLowerCase();
    return Tooltip(
      message: hex,
      child: InkWell(
        onTap: () => setState(() => _current = hex),
        onLongPress: () => _saveToSlot(index),
        customBorder: const CircleBorder(),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}
