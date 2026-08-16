import 'package:flutter/material.dart';

/// 色と '#RRGGBB' 文字列の相互変換ユーティリティ。
/// テーマCSS(テーマジェネレータ)とプロジェクトタイル色の両方から使う。

/// Color → '#rrggbb'(小文字、アルファは捨てる)
String hexFromColor(Color c) =>
    '#${((c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round()).toRadixString(16).padLeft(6, '0')}';

/// '#rrggbb' / 'rrggbb' / 'rgb(...)' / 'rgba(...)' → Color。解釈できなければ null。
Color? colorFromHex(String value) {
  final s = value.replaceAll('#', '').trim();
  if (s.length != 6) {
    if (s.startsWith('rgba') || s.startsWith('rgb')) {
      final match =
          RegExp(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)').firstMatch(s);
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

/// 2色のコントラスト比(WCAG)。1(同色)〜21(黒と白)。
/// 本文として読める目安は4.5以上、大きい文字なら3以上。
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// 本文として読める最低ライン(WCAG AA)
const double kReadableContrast = 4.5;

/// 背景色の上で読みやすい文字色(黒 or 白)。
/// 輝度の閾値ではなく、白・黒それぞれのコントラスト比を比べて高い方を返す
/// (閾値方式だと中間の明るさの背景で読みにくい方を選ぶことがある)。
Color contrastForegroundFor(Color background) =>
    contrastRatio(Colors.white, background) >=
            contrastRatio(Colors.black, background)
        ? Colors.white
        : Colors.black;

/// 背景色から計算した文字色の候補。
class ForegroundSuggestion {
  /// 種類のキー('white' / 'black' / 'same' / 'complement' / 'muted')
  final String kind;
  final Color color;
  final double ratio;

  /// 最もコントラストが高い候補(白か黒)につく印
  final bool recommended;

  const ForegroundSuggestion(this.kind, this.color, this.ratio,
      {this.recommended = false});
}

/// 色相・彩度は保ったまま明度だけ動かし、目標のコントラスト比を満たす色を探す。
/// 暗い方・明るい方の両方を試して、満たした方(両方満たすなら比が高い方)を返す。
/// 明度で向きを決めると、紫のように「HSL上は明るいが実際は暗い」色で失敗する。
Color? _adjustLightness(Color background, double hue, double saturation,
    {double target = kReadableContrast}) {
  Color? scan(bool darker) {
    for (var i = 0; i <= 100; i++) {
      final t = i / 100;
      final lightness = darker ? 0.5 - t * 0.5 : 0.5 + t * 0.5;
      final candidate =
          HSLColor.fromAHSL(1, hue % 360, saturation, lightness).toColor();
      if (contrastRatio(candidate, background) >= target) return candidate;
    }
    return null;
  }

  final dark = scan(true);
  final light = scan(false);
  if (dark == null) return light;
  if (light == null) return dark;
  return contrastRatio(dark, background) >= contrastRatio(light, background)
      ? dark
      : light;
}

/// 背景色から文字色の候補を作る。目標のコントラスト比を満たすものだけ返す
/// (白・黒は基準として満たさなくても常に含める)。
List<ForegroundSuggestion> suggestForegrounds(Color background,
    {double target = kReadableContrast}) {
  final hsl = HSLColor.fromColor(background);
  final result = <ForegroundSuggestion>[];

  // 白・黒はコントラスト比の高い順。先頭が「推奨」。
  final white = contrastRatio(Colors.white, background);
  final black = contrastRatio(Colors.black, background);
  if (white >= black) {
    result.add(ForegroundSuggestion('white', Colors.white, white,
        recommended: true));
    result.add(ForegroundSuggestion('black', Colors.black, black));
  } else {
    result.add(ForegroundSuggestion('black', Colors.black, black,
        recommended: true));
    result.add(ForegroundSuggestion('white', Colors.white, white));
  }

  void addAdjusted(String kind, double hue, double saturation) {
    final color = _adjustLightness(background, hue, saturation, target: target);
    if (color == null) return;
    result.add(
        ForegroundSuggestion(kind, color, contrastRatio(color, background)));
  }

  addAdjusted('same', hsl.hue, hsl.saturation.clamp(0.0, 0.7)); // なじむ
  addAdjusted('complement', hsl.hue + 180,
      hsl.saturation.clamp(0.4, 0.8)); // 際立つ
  addAdjusted('muted', hsl.hue, 0.15); // 落ち着く

  // 同じ色が並ばないようにする
  final seen = <int>{};
  return [
    for (final s in result)
      if (seen.add(s.color.toARGB32())) s,
  ];
}

/// 2色を混ぜた「不透明な」色を作る。
/// withValues(alpha:)で薄い文字色を作ると内蔵GPU機でVRAMを食うため、
/// 半透明ではなく背景色に畳んだ実色を使う。
Color blendOpaque(Color foreground, Color background, double t) =>
    Color.lerp(background, foreground, t)!.withAlpha(255);
