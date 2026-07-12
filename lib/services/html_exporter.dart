import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:markdown/markdown.dart' as md;

import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';
import 'workspace_service.dart';

/// プロジェクトを単一フォルダ（index.html + images/）へ書き出す。
///
/// 出力HTMLの構造・クラス名・CSS変数は **本家 Manidoc と互換**にしてある。
/// そのため本家で作った既存テーマCSS（`--primary-color` 等の :root 変数と
/// `.article-body` / `.comment-box` / `.node-container` 等のセレクタ）がそのまま効く。
class HtmlExporter {
  final WorkspaceService workspace;

  HtmlExporter(this.workspace);

  bool _includeToc = true;
  bool _numbering = true;
  bool _tts = false;
  double _ttsSpeed = 1.0;
  double _articleSize = 14;
  String? _themeCss;

  /// 書き出し先フォルダのパスを返す
  Future<String> export(ManidocProject project, String outputDir,
      {bool includeToc = true,
      bool numbering = true,
      bool tts = false,
      double ttsSpeed = 1.0,
      bool optimize = false,
      int jpegQuality = 80,
      int maxDimension = 1920,
      double articleFontSize = 14,
      String? themeCss}) async {
    _includeToc = includeToc;
    _numbering = numbering;
    _tts = tts;
    _ttsSpeed = ttsSpeed;
    _articleSize = articleFontSize;
    _themeCss = themeCss;

    final dir = Directory(outputDir);
    await dir.create(recursive: true);

    // 画像をコピー(オプションで縮小・再圧縮。ファイル名は保持する)
    final srcImages = Directory(workspace.imagesDirPath(project.id));
    final destImages = Directory('$outputDir${Platform.pathSeparator}images');
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
    await File('$outputDir${Platform.pathSeparator}index.html')
        .writeAsString(html);
    return outputDir;
  }

  /// 長辺がmaxDimensionを超える画像を縮小し、JPEGは再圧縮してコピーする(拡張子は維持)
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
  String _md(String text) => md.markdownToHtml(text,
      extensionSet: md.ExtensionSet.gitHubFlavored);

  // ---------- HTML本体 ----------

  String _buildHtml(ManidocProject project) {
    final toc = StringBuffer();
    final body = StringBuffer();

    if (_includeToc) {
      var i = 1;
      for (final node in project.rootNodes) {
        _buildToc(node, '$i.', toc);
        i++;
      }
    }

    var chapter = 1;
    for (final node in project.rootNodes) {
      _buildNode(node, 2, '$chapter.', body);
      chapter++;
    }

    final themeBlock = (_themeCss != null && _themeCss!.trim().isNotEmpty)
        ? '<style data-theme-css>\n${_themeCss!}\n</style>'
        : '';

    final tocMarkup = _includeToc
        ? '''
  <button id="menu-toggle" title="目次を表示">☰</button>
  <div id="sidebar-overlay"></div>
  <nav id="sidebar">
    <h2>目次</h2>
    <ul>
$toc    </ul>
  </nav>'''
        : '';

    return '''
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${_esc(project.name)}</title>
<style>
${_baseCss()}
</style>
$themeBlock
</head>
<body>
$tocMarkup
  <div id="main-content" class="content-wrapper">
    <h1>${_esc(project.name)}</h1>
    <hr>
$body  </div>
${_script()}
</body>
</html>
''';
  }

  void _buildToc(ManidocNode node, String prefix, StringBuffer sb) {
    final label = _numbering ? '$prefix ' : '';
    sb.writeln(
        '      <li><a href="#node-${node.id}">$label${_esc(node.title)}</a></li>');
    if (node.children.isNotEmpty) {
      sb.writeln('      <li class="toc-child"><ul>');
      var i = 1;
      for (final child in node.children) {
        _buildToc(child, '$prefix$i.', sb);
        i++;
      }
      sb.writeln('      </ul></li>');
    }
  }

  void _buildNode(
      ManidocNode node, int headingLevel, String prefix, StringBuffer sb) {
    final level = headingLevel > 6 ? 6 : headingLevel;
    final label = _numbering ? '$prefix ' : '';
    final ttsBtn = _tts
        ? '<button class="tts-btn" onclick="toggleTTS(\'node-${node.id}\', this)" title="読み上げ">🔊</button>'
        : '';

    sb.writeln('    <div class="node-container" id="node-${node.id}">');
    sb.writeln('      <h$level>$label${_esc(node.title)}$ttsBtn</h$level>');
    if (node.article.trim().isNotEmpty) {
      sb.writeln('      <div class="article-body">${_md(node.article)}</div>');
    }
    if (node.imagePath.trim().isNotEmpty) {
      sb.writeln(
          '      <img src="${_esc(node.imagePath)}" alt="${_esc(node.title)}">');
    }
    if (node.comment.trim().isNotEmpty) {
      sb.writeln('      <div class="comment-box">${_md(node.comment)}</div>');
    }
    if (node.children.isNotEmpty) {
      sb.writeln('      <div class="child-nodes">');
      var i = 1;
      for (final child in node.children) {
        _buildNode(child, headingLevel + 1, '$prefix$i.', sb);
        i++;
      }
      sb.writeln('      </div>');
    }
    sb.writeln('    </div>');
  }

  // ---------- CSS(本家 GetFormattedCss と互換) ----------

  String _baseCss() {
    final tocCss = _includeToc ? _tocCss() : '';
    final ttsCss = _tts ? _ttsCss() : '';
    return '''
:root {
  --main-bg-color: #fcfcfc;
  --text-main: #1a1a1a;
  --text-muted: #444;
  --primary-color: #0056b3;
  --h1-gradient-start: #0056b3;
  --h1-gradient-end: #00b4db;
  --border-color: #eee;
  --comment-bg: rgba(255, 255, 255, 0.7);
  --table-header-bg: #f8f9fa;
  --code-bg: #f1f3f5;
  --code-color: #e03131;
  --pre-bg: #1a1a1b;
  --pre-color: #f8f8f2;
  --article-font-size: ${_articleSize}px;
  --comment-font-size: ${_articleSize}px;
}
body { font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Hiragino Kaku Gothic ProN', Meiryo, sans-serif; line-height: 1.6; color: var(--text-main); margin: 0; padding: 0; background-color: var(--main-bg-color); }
.content-wrapper { max-width: 960px; margin: 0 auto; padding: 40px 20px; box-sizing: border-box; transition: filter 0.3s; }
h1 { font-size: 2.8em; font-weight: 800; letter-spacing: -0.02em; margin-bottom: 0.5em; background: linear-gradient(135deg, var(--h1-gradient-start), var(--h1-gradient-end)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; border-bottom: none; }
h2 { font-size: 1.8em; font-weight: 700; margin-top: 1.5em; margin-bottom: 0.8em; color: var(--text-main); position: relative; padding-bottom: 8px; border-bottom: 2px solid var(--border-color); }
h2::after { content: ''; position: absolute; bottom: -2px; left: 0; width: 60px; height: 2px; background: var(--primary-color); }
h3 { font-size: 1.4em; font-weight: 600; color: var(--text-main); margin-top: 1.2em; }
p { margin-bottom: 1.2em; color: var(--text-muted); }
.article-body { margin-top: 20px; font-size: var(--article-font-size); line-height: 1.8; color: var(--text-main); }
.article-body ul, .article-body ol { padding-left: 20px; margin-bottom: 20px; }
.article-body li { margin-bottom: 8px; }
.article-body p:last-child, .comment-box p:last-child { margin-bottom: 0; }
a { color: var(--primary-color); text-decoration: none; border-bottom: 1px solid transparent; transition: border-color 0.2s; }
a:hover { border-bottom-color: var(--primary-color); }
.comment-box { background: var(--comment-bg); backdrop-filter: blur(10px); padding: 20px; border-radius: 12px; border: 1px solid rgba(0, 0, 0, 0.05); margin-bottom: 30px; box-shadow: 0 4px 20px rgba(0,0,0,0.03); font-size: var(--comment-font-size); position: relative; overflow: hidden; }
.comment-box::before { content: ''; position: absolute; left: 0; top: 0; height: 100%; width: 4px; background: var(--primary-color); }
img { max-width: 100%; height: auto; border: 1px solid var(--border-color); border-radius: 8px; box-shadow: 0 10px 30px rgba(0,0,0,0.08); margin: 20px 0 30px 0; display: block; }
hr { border: 0; height: 1px; background: linear-gradient(to right, var(--border-color), transparent); margin: 60px 0; }
.node-container { margin-bottom: 60px; scroll-margin-top: 100px; }
.child-nodes { margin-left: 0; border-left: none; padding-left: 0; margin-top: 40px; }
.child-nodes > .node-container { margin-left: 30px; padding-left: 20px; border-left: 2px solid var(--border-color); }
table { border-collapse: separate; border-spacing: 0; margin-bottom: 20px; width: 100%; border: 1px solid var(--border-color); border-radius: 8px; overflow: hidden; }
th, td { padding: 12px 15px; border-bottom: 1px solid var(--border-color); text-align: left; }
th { background-color: var(--table-header-bg); font-weight: 600; color: var(--text-main); }
tr:last-child td { border-bottom: none; }
blockquote { border-left: 4px solid var(--primary-color); margin: 20px 0; padding: 15px 20px; color: var(--text-muted); background: var(--comment-bg); border-radius: 0 8px 8px 0; font-style: italic; }
code { background-color: var(--code-bg); padding: 2px 6px; border-radius: 4px; font-family: 'Fira Code', monospace; color: var(--code-color); font-size: 0.9em; }
pre { background-color: var(--pre-bg); color: var(--pre-color); padding: 20px; border-radius: 12px; overflow-x: auto; box-shadow: 0 10px 30px rgba(0,0,0,0.15); margin: 20px 0; }
pre code { background-color: transparent; padding: 0; color: inherit; font-size: 0.85em; }
.back-link { position: fixed; top: 20px; left: 80px; background: var(--primary-color); color: white !important; padding: 0 20px; border-radius: 8px; text-decoration: none; font-weight: 600; font-size: 14px; height: 44px; display: flex; align-items: center; z-index: 1001; box-shadow: 0 4px 15px rgba(0,0,0,0.1); transition: all 0.3s ease; }
.back-link:hover { filter: brightness(0.9); transform: translateY(-2px); }
.blur { pointer-events: none; opacity: 0.6; transform: scale(0.98); transition: all 0.4s ease; }
$tocCss$ttsCss''';
  }

  String _tocCss() => '''
#sidebar { position: fixed; top: 0; left: -320px; width: 320px; height: 100%; background: #fff; color: #333; transition: all 0.4s cubic-bezier(0.16, 1, 0.3, 1); overflow-y: auto; z-index: 1000; padding: 30px; box-sizing: border-box; box-shadow: 20px 0 50px rgba(0,0,0,0.05); border-right: 1px solid #eee; }
#sidebar.open { left: 0; }
#sidebar h2 { border: none; background: none; color: #111; font-size: 1.4em; margin-top: 10px; padding: 0; border-bottom: none; font-weight: 800; }
#sidebar ul { list-style: none; padding: 0; margin: 30px 0; }
#sidebar li { margin: 8px 0; }
#sidebar a { color: #666; text-decoration: none; transition: all 0.2s; font-size: 0.95em; display: block; padding: 6px 0; }
#sidebar a:hover { color: var(--primary-color); padding-left: 5px; }
.toc-child { margin-left: 20px; border-left: 1px solid var(--border-color); padding-left: 15px; }
#menu-toggle { position: fixed; top: 20px; left: 20px; width: 44px; height: 44px; background: var(--primary-color); color: white; border: none; border-radius: 8px; cursor: pointer; z-index: 1001; display: flex; align-items: center; justify-content: center; font-size: 20px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); transition: all 0.3s ease; }
#menu-toggle:hover { transform: scale(1.05); filter: brightness(0.9); }
#menu-toggle.open { left: 20px; background: #333; }
#sidebar-overlay { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.2); backdrop-filter: blur(4px); visibility: hidden; opacity: 0; transition: all 0.3s; z-index: 999; }
#sidebar-overlay.show { visibility: visible; opacity: 1; }
''';

  String _ttsCss() => '''
.tts-btn { background: #f0f4f8; border: none; border-radius: 6px; cursor: pointer; padding: 4px 10px; margin-left: 12px; font-size: 0.75em; transition: all 0.2s; vertical-align: middle; color: var(--primary-color); font-weight: 600; }
.tts-btn:hover { background: var(--primary-color); color: white; transform: translateY(-1px); }
.tts-btn.playing { background: #ff9f0a; color: white; animation: pulse 1.5s infinite; }
@keyframes pulse { 0% { opacity: 1; } 50% { opacity: 0.7; } 100% { opacity: 1; } }
''';

  // ---------- JS(本家互換: サイドバー開閉 + TTS) ----------

  String _script() {
    if (!_includeToc && !_tts) return '';
    final sidebarJs = _includeToc
        ? '''
    const mainContent = document.getElementById('main-content');
    const menuToggle = document.getElementById('menu-toggle');
    const sidebar = document.getElementById('sidebar');
    const overlay = document.getElementById('sidebar-overlay');
    function toggleMenu() {
      sidebar.classList.toggle('open');
      menuToggle.classList.toggle('open');
      overlay.classList.toggle('show');
      mainContent.classList.toggle('blur');
    }
    if (menuToggle) menuToggle.addEventListener('click', toggleMenu);
    if (overlay) overlay.addEventListener('click', toggleMenu);
    document.querySelectorAll('#sidebar a').forEach(link => {
      link.addEventListener('click', () => { if (sidebar.classList.contains('open')) toggleMenu(); });
    });'''
        : '';
    final ttsJs = _tts
        ? '''
    let currentUtterance = null;
    function toggleTTS(nodeId, btn) {
      if (window.speechSynthesis.speaking) {
        window.speechSynthesis.cancel();
        document.querySelectorAll('.tts-btn').forEach(b => b.classList.remove('playing'));
        if (currentUtterance && currentUtterance.nodeId === nodeId) { currentUtterance = null; return; }
      }
      const container = document.getElementById(nodeId);
      const title = container.querySelector('h1, h2, h3, h4, h5, h6').innerText.replace('🔊', '').trim();
      const article = container.querySelector('.article-body') ? container.querySelector('.article-body').innerText : '';
      const comment = container.querySelector('.comment-box') ? container.querySelector('.comment-box').innerText : '';
      const uttr = new SpeechSynthesisUtterance(`\${title}。 \${article}。 \${comment}`);
      uttr.lang = 'ja-JP';
      uttr.nodeId = nodeId;
      uttr.rate = $_ttsSpeed;
      uttr.onstart = () => btn.classList.add('playing');
      uttr.onend = () => btn.classList.remove('playing');
      uttr.onerror = () => btn.classList.remove('playing');
      window.speechSynthesis.speak(uttr);
      currentUtterance = uttr;
    }'''
        : '';
    return '  <script>\n$sidebarJs\n$ttsJs\n  </script>';
  }
}
