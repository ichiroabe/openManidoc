import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/services/html_exporter.dart';

void main() {
  group('HtmlExporter.buildThemeCss (本家互換フルCSS)', () {
    final vars = {
      '--main-bg-color': '#0A0E1A',
      '--text-main': '#E0E6F0',
      '--primary-color': '#5DE7F6',
      '--article-font-size': '18px',
    };

    test('injects the given :root variables', () {
      final css = HtmlExporter.buildThemeCss(vars);
      expect(css, contains(':root {'));
      expect(css, contains('--main-bg-color: #0A0E1A;'));
      expect(css, contains('--primary-color: #5DE7F6;'));
      expect(css, contains('--article-font-size: 18px;'));
    });

    test('is self-contained: body + full styles + sidebar + tts', () {
      final css = HtmlExporter.buildThemeCss(vars);
      // body rule with font-family
      expect(css, contains('body { font-family:'));
      // core article/layout styles (本家 class names)
      expect(css, contains('.content-wrapper'));
      expect(css, contains('.article-body'));
      expect(css, contains('.comment-box'));
      expect(css, contains('.child-nodes'));
      // sidebar (TOC) and TTS blocks are always present, like 本家 themes
      expect(css, contains('#sidebar'));
      expect(css, contains('.tts-btn'));
    });

    test('honours a custom font family', () {
      final css = HtmlExporter.buildThemeCss(vars, font: '"Georgia", serif');
      expect(css, contains('body { font-family: "Georgia", serif;'));
    });

    test('a generated theme round-trips through :root parsing', () {
      final css = HtmlExporter.buildThemeCss(vars);
      final rootMatch =
          RegExp(r':root\s*\{([^}]+)\}', dotAll: true).firstMatch(css);
      expect(rootMatch, isNotNull);
      final parsed = <String, String>{};
      for (final m in RegExp(r'(--[a-zA-Z0-9\-]+)\s*:\s*([^;]+);')
          .allMatches(rootMatch!.group(1)!)) {
        parsed[m.group(1)!.trim()] = m.group(2)!.trim();
      }
      // every var we put in comes back out identically
      vars.forEach((k, v) => expect(parsed[k], v));
    });
  });
}
