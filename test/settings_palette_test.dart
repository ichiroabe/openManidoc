import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/services/settings_service.dart';

void main() {
  test('bgPaletteColors round-trips via toJson/fromJson', () {
    final s = AppSettings();
    s.bgPaletteColors[0] = '#123456';
    s.bgPaletteColors[7] = '#abcdef';
    final restored = AppSettings.fromJson(s.toJson());
    expect(restored.bgPaletteColors[0], '#123456');
    expect(restored.bgPaletteColors[7], '#abcdef');
    expect(restored.bgPaletteColors.length,
        AppSettings.defaultBgPalette.length);
  });

  test('missing/short palette is padded with defaults', () {
    final restored = AppSettings.fromJson({
      'bgPaletteColors': ['#111111', '#222222'],
    });
    expect(restored.bgPaletteColors.length,
        AppSettings.defaultBgPalette.length);
    expect(restored.bgPaletteColors[0], '#111111');
    expect(restored.bgPaletteColors[1], '#222222');
    expect(restored.bgPaletteColors[2], AppSettings.defaultBgPalette[2]);
  });

  test('settings without palette key get the default palette', () {
    final restored = AppSettings.fromJson({});
    expect(restored.bgPaletteColors, AppSettings.defaultBgPalette);
  });
}
