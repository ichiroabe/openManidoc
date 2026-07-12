import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:markdown/markdown.dart' as md;

import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';
import 'workspace_service.dart';

/// プロジェクトを単一フォルダ（index.html + images/）へ書き出す。
class HtmlExporter {
  final WorkspaceService workspace;

  HtmlExporter(this.workspace);

  /// 書き出し先フォルダのパスを返す
  Future<String> export(ManidocProject project, String outputDir,
      {bool includeToc = true,
      bool numbering = true,
      bool tts = false,
      double ttsSpeed = 1.0,
      bool optimize = false,
      int jpegQuality = 80,
      int maxDimension = 1920,
      String? themeCss}) async {
    _includeToc = includeToc;
    _numbering = numbering;
    _tts = tts;
    _ttsSpeed = ttsSpeed;
    _themeCss = themeCss;
    final dir = Directory(outputDir);
    await dir.create(recursive: true);

    // 画像をコピー(オプションで縮小・再圧縮)
    final srcImages = Directory(workspace.imagesDirPath(project.id));
    final destImages =
        Directory('$outputDir${Platform.pathSeparator}images');
    if (await srcImages.exists()) {
      await destImages.create(recursive: true);
      await for (final entity in srcImages.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        final destPath = '${destImages.path}${Platform.pathSeparator}$name';
        if (optimize) {
          await _copyOptimized(entity, destPath, jpegQuality, maxDimension);
        } else {
          await entity.copy(destPath);
        }
      }
    }

    final html = _buildHtml(project);
    final indexFile = File('$outputDir${Platform.pathSeparator}index.html');
    await indexFile.writeAsString(html);
    return outputDir;
  }

  bool _includeToc = true;
  bool _numbering = true;
  bool _tts = false;
  double _ttsSpeed = 1.0;
  String? _themeCss;

  /// 長辺がmaxDimensionを超える画像を縮小し、JPEGは再圧縮してコピーする
  Future<void> _copyOptimized(
      File source, String destPath, int jpegQuality, int maxDimension) async {
    final lower = source.path.toLowerCase();
    final isJpeg = lower.endsWith('.jpg') || lower.endsWith('.jpeg');
    final isPng = lower.endsWith('.png');
    if (!isJpeg && !isPng) {
      await source.copy(destPath);
      return;
    }
    try {
      final decoded = img.decodeImage(await source.readAsBytes());
      if (decoded == null) {
        await source.copy(destPath);
        return;
      }
      var resized = decoded;
      final longSide =
          decoded.width > decoded.height ? decoded.width : decoded.height;
      if (longSide > maxDimension) {
        resized = decoded.width >= decoded.height
            ? img.copyResize(decoded, width: maxDimension)
            : img.copyResize(decoded, height: maxDimension);
      }
      final bytes = isJpeg
          ? img.encodeJpg(resized, quality: jpegQuality)
          : img.encodePng(resized);
      await File(destPath).writeAsBytes(bytes);
    } catch (_) {
      await source.copy(destPath);
    }
  }

  String _esc(String s) => const HtmlEscape().convert(s);

  String _buildHtml(ManidocProject project) {
    final tocBuffer = StringBuffer();
    final bodyBuffer = StringBuffer();
    var counter = 0;

    void walk(List<ManidocNode> nodes, int depth, String numberPrefix) {
      var index = 1;
      for (final node in nodes) {
        counter++;
        final anchor = 'sec-$counter';
        final number = numberPrefix.isEmpty ? '$index' : '$numberPrefix.$index';
        final headingLevel = (depth + 2).clamp(2, 6); // h2〜h6
        final label =
            _numbering ? '$number. ${_esc(node.title)}' : _esc(node.title);

        tocBuffer.writeln(
            '<li class="toc-depth-$depth"><a href="#$anchor">$label</a></li>');

        bodyBuffer.writeln('<section id="$anchor" class="node-section">');
        final ttsButton = _tts
            ? ' <button class="tts-btn" data-sec="$anchor" title="読み上げ">🔊</button>'
            : '';
        bodyBuffer
            .writeln('<h$headingLevel>$label$ttsButton</h$headingLevel>');
        if (node.article.trim().isNotEmpty) {
          bodyBuffer.writeln('<div class="article">'
              '${md.markdownToHtml(node.article, extensionSet: md.ExtensionSet.gitHubFlavored)}'
              '</div>');
        }
        if (node.imagePath.trim().isNotEmpty) {
          bodyBuffer.writeln(
              '<figure><img src="${_esc(node.imagePath)}" alt="${_esc(node.title)}" loading="lazy"></figure>');
        }
        if (node.comment.trim().isNotEmpty) {
          bodyBuffer.writeln('<aside class="comment">'
              '${md.markdownToHtml(node.comment, extensionSet: md.ExtensionSet.gitHubFlavored)}'
              '</aside>');
        }
        bodyBuffer.writeln('</section>');

        walk(node.children, depth + 1, number);
        index++;
      }
    }

    walk(project.rootNodes, 0, '');

    final menuButton = _includeToc
        ? '<button id="menu-btn" aria-label="目次">☰</button>'
        : '';
    final tocNav = _includeToc
        ? '<nav id="toc"><ul>\n$tocBuffer\n</ul></nav>\n<div id="overlay"></div>'
        : '';
    final ttsScript = _tts
        ? '''
<script>
document.querySelectorAll('.tts-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    speechSynthesis.cancel();
    const sec = document.getElementById(btn.dataset.sec);
    const u = new SpeechSynthesisUtterance(sec.innerText.replace('🔊',''));
    u.lang = 'ja-JP';
    u.rate = $_ttsSpeed;
    speechSynthesis.speak(u);
  });
});
</script>'''
        : '';
    final tocScript = _includeToc
        ? '''
<script>
const toc = document.getElementById('toc');
const overlay = document.getElementById('overlay');
const toggle = (open) => {
  toc.classList.toggle('open', open);
  overlay.classList.toggle('show', open);
};
document.getElementById('menu-btn').addEventListener('click', () => toggle(!toc.classList.contains('open')));
overlay.addEventListener('click', () => toggle(false));
toc.addEventListener('click', (e) => { if (e.target.tagName === 'A') toggle(false); });
</script>'''
        : '';

    return '''
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${_esc(project.name)}</title>
<style>
:root {
  --bg: #ffffff; --fg: #1a1a2e; --accent: #4361ee; --muted: #6c757d;
  --card: #f8f9fa; --border: #dee2e6; --comment-bg: #fff8e1; --comment-border: #ffca28;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #16161e; --fg: #e8e8f0; --accent: #7b9aff; --muted: #9aa0a6;
    --card: #1f1f2b; --border: #33333f; --comment-bg: #2a2618; --comment-border: #b8901f;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0; background: var(--bg); color: var(--fg);
  font-family: "Segoe UI", "Hiragino Sans", "Noto Sans JP", sans-serif;
  line-height: 1.8;
}
header {
  position: sticky; top: 0; z-index: 10; display: flex; align-items: center; gap: 1rem;
  background: var(--card); border-bottom: 1px solid var(--border); padding: 0.6rem 1rem;
}
header h1 { font-size: 1.1rem; margin: 0; }
#menu-btn {
  font-size: 1.4rem; background: none; border: none; color: var(--fg); cursor: pointer;
}
nav#toc {
  position: fixed; top: 0; left: 0; bottom: 0; width: 300px; max-width: 85vw;
  background: var(--card); border-right: 1px solid var(--border);
  transform: translateX(-100%); transition: transform 0.25s ease; z-index: 20;
  overflow-y: auto; padding: 1rem;
}
nav#toc.open { transform: translateX(0); }
nav#toc ul { list-style: none; margin: 0; padding: 0; }
nav#toc li { margin: 0.2rem 0; }
nav#toc a { color: var(--fg); text-decoration: none; display: block; padding: 0.25rem 0.5rem; border-radius: 6px; }
nav#toc a:hover { background: var(--accent); color: #fff; }
.toc-depth-1 { padding-left: 1rem; }
.toc-depth-2 { padding-left: 2rem; }
.toc-depth-3 { padding-left: 3rem; }
.toc-depth-4 { padding-left: 4rem; }
#overlay {
  display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.4); z-index: 15;
}
#overlay.show { display: block; }
main { max-width: 860px; margin: 0 auto; padding: 1rem 1.2rem 4rem; }
.node-section { margin-bottom: 2.5rem; scroll-margin-top: 4rem; }
h2, h3, h4, h5, h6 {
  border-left: 5px solid var(--accent); padding-left: 0.6rem; line-height: 1.4;
}
figure { margin: 1rem 0; text-align: center; }
figure img {
  max-width: 100%; border: 1px solid var(--border); border-radius: 8px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.12);
}
.article img { max-width: 100%; }
.article pre {
  background: var(--card); border: 1px solid var(--border); border-radius: 8px;
  padding: 0.8rem; overflow-x: auto;
}
.article code { background: var(--card); padding: 0.1em 0.35em; border-radius: 4px; }
.article pre code { background: none; padding: 0; }
.article table { border-collapse: collapse; }
.article th, .article td { border: 1px solid var(--border); padding: 0.35em 0.7em; }
.comment {
  background: var(--comment-bg); border-left: 4px solid var(--comment-border);
  border-radius: 0 8px 8px 0; padding: 0.6rem 1rem; margin: 1rem 0; font-size: 0.95rem;
}
footer { text-align: center; color: var(--muted); font-size: 0.85rem; padding: 2rem 0; }
.tts-btn { background: none; border: none; cursor: pointer; font-size: 0.9em; opacity: 0.6; }
.tts-btn:hover { opacity: 1; }
html { scroll-behavior: smooth; }
</style>
${_themeCss != null && _themeCss!.trim().isNotEmpty ? '<style data-theme-css>\n${_themeCss!}\n</style>' : ''}
</head>
<body>
<header>
  $menuButton
  <h1>${_esc(project.name)}</h1>
</header>
$tocNav
<main>
$bodyBuffer
</main>
<footer>Generated by openManidoc</footer>
$tocScript
$ttsScript
</body>
</html>
''';
  }
}
