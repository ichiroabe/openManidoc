import 'dart:convert';
import 'dart:io';

import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';
import '../models/tag_definition.dart';
import 'html_exporter.dart';
import 'workspace_service.dart';

/// Web一括出力: 全プロジェクトをHTML化し、一覧ポータル(index.html)を生成する。
class PortalExporter {
  final WorkspaceService workspace;

  PortalExporter(this.workspace);

  String _esc(String s) => const HtmlEscape().convert(s);
  String _escAttr(String s) =>
      const HtmlEscape(HtmlEscapeMode.attribute).convert(s);

  Future<String> export(List<ManidocProject> projects, String title,
      {bool includeToc = true,
      bool numbering = true,
      bool tts = false,
      double ttsSpeed = 1.0,
      double articleFontSize = 14,
      String indexTheme = 'Light',
      String customCssPath = '',
      String titleUrl = '',
      bool? useGrouping}) async {
    // 本家互換: ワークスペース直下の固定 weboutput フォルダ配下に
    // Export_yyyy.MM.dd_HHmmss のサブフォルダを作って出力する。
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = 'Export_${now.year}.${two(now.month)}.${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final sep = Platform.pathSeparator;
    final outDir = '${workspace.workspacePath}${sep}weboutput$sep$stamp';
    await Directory(outDir).create(recursive: true);

    // フォルダ名(本家互換のサニタイズ)を先に確定し、全プロジェクトへの
    // リンクメニュー(各ページ右上☰「プロジェクト一覧」)を組み立てる。
    String safeNameOf(ManidocProject p) =>
        p.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final projectLinks = [
      for (final p in projects)
        (
          name: p.name,
          url: '../${Uri.encodeComponent(safeNameOf(p))}/index.html',
        )
    ];

    // 1. 共通の workspace.css をルートに書き出す (ベースCSS)
    // 一覧が2件以上でなくても本家同様メニューは出す(自分含む全プロジェクト)。
    final exporter = HtmlExporter(workspace);
    final baseCss = exporter.getBaseCss(
      includeToc: includeToc,
      tts: tts,
      articleFontSize: articleFontSize,
      hasProjectLinks: projectLinks.isNotEmpty,
    );
    await File('$outDir${Platform.pathSeparator}workspace.css')
        .writeAsString(baseCss, encoding: utf8);

    // グループ化の判定(本家互換: 明示指定が無ければ、タグ付きが1件でもあれば階層化)
    final anyTag = projects.any((p) => p.tag.trim().isNotEmpty);
    final grouping = useGrouping ?? anyTag;

    // タグ順序: ワークスペースのタグ定義順を優先、未定義の使用タグは末尾へ。
    final tagDefs = await workspace.loadTags();
    final usedTags = <String>{
      for (final p in projects)
        if (p.tag.trim().isNotEmpty) p.tag.trim()
    };
    final orderedTags = <String>[
      for (final d in tagDefs)
        if (usedTags.contains(d.name)) d.name,
    ];
    for (final t in usedTags) {
      if (!orderedTags.contains(t)) orderedTags.add(t);
    }
    final tagFolders = {
      for (var i = 0; i < orderedTags.length; i++) orderedTags[i]: 'tag_$i'
    };

    // 各プロジェクトを個別フォルダへ出力し、カード用の情報を集める。
    final infos = <_Info>[];
    for (final project in projects) {
      final safeName = safeNameOf(project);
      final tag = project.tag.trim();
      // 戻る先: グループ化中のタグ付きはタグ別サブページ、他はトップ
      final backUrl = grouping && tag.isNotEmpty
          ? '../${tagFolders[tag]}/index.html'
          : '../index.html';

      await exporter.export(
        project,
        '$outDir${Platform.pathSeparator}$safeName',
        includeToc: includeToc,
        numbering: numbering,
        tts: tts,
        ttsSpeed: ttsSpeed,
        articleFontSize: articleFontSize,
        themeCss: await workspace.readThemeCss(project.themeCssFileName),
        isBulkExport: true,
        projectLinks: projectLinks,
        backLinkUrl: backUrl,
      );

      final thumbName = await _copyThumbnail(project, outDir, safeName);
      infos.add(_Info(
        name: project.name,
        safeName: safeName,
        thumb: thumbName,
        tag: tag,
        updated: project.lastModifiedAt.toLocal().toString().substring(0, 16),
      ));
    }

    // ポータル用CSS(全ページ共通。タグ別サブページも同じCSSを使う)
    final portalCss = await _buildPortalCss(indexTheme, customCssPath);

    if (grouping) {
      // タグ別サブページを生成し、トップ用のタグタイル情報を集める。
      final tagTiles = StringBuffer();
      for (final tagName in orderedTags) {
        final folder = tagFolders[tagName]!;
        final tagDir = '$outDir${Platform.pathSeparator}$folder';
        await Directory(tagDir).create(recursive: true);

        TagDefinition? tagDef;
        for (final d in tagDefs) {
          if (d.name == tagName) {
            tagDef = d;
            break;
          }
        }
        final tagImg =
            tagDef == null ? null : await _copyTagImage(tagDef, tagDir);

        final members = infos.where((e) => e.tag == tagName).toList();
        await _writeTagSubPage(tagDir, tagName, title, members, portalCss);

        final tileThumb = tagImg != null ? '$folder/$tagImg' : null;
        tagTiles.writeln(_cardHtml(
          href: '$folder/index.html',
          thumbRef: tileThumb,
          title: tagName,
          subtitle: '${members.length} 個のプロジェクト',
        ));
      }
      // タグなしプロジェクトはトップに直接
      final untagged = StringBuffer();
      for (final e in infos.where((e) => e.tag.isEmpty)) {
        untagged.writeln(_cardHtml(
          href: './${Uri.encodeComponent(e.safeName)}/index.html',
          thumbRef: e.thumb != null ? './${e.thumb}' : null,
          title: e.name,
          subtitle: '更新: ${e.updated}',
        ));
      }
      final body = '''
<header><h1>${_titleH1(title, titleUrl)}</h1></header>
<div class="grid">
$tagTiles$untagged</div>
<footer>Generated by openManidoc</footer>''';
      await File('$outDir${Platform.pathSeparator}index.html')
          .writeAsString(_pageHtml(title, portalCss, body), encoding: utf8);
    } else {
      // フラット出力: 全プロジェクトを1枚のグリッドに
      final cards = StringBuffer();
      for (final e in infos) {
        cards.writeln(_cardHtml(
          href: './${Uri.encodeComponent(e.safeName)}/index.html',
          thumbRef: e.thumb != null ? './${e.thumb}' : null,
          title: e.name,
          subtitle: e.tag.isEmpty
              ? '更新: ${e.updated}'
              : '${e.tag} | 更新: ${e.updated}',
        ));
      }
      final body = '''
<header><h1>${_titleH1(title, titleUrl)}</h1></header>
<div class="grid">
$cards</div>
<footer>Generated by openManidoc</footer>''';
      await File('$outDir${Platform.pathSeparator}index.html')
          .writeAsString(_pageHtml(title, portalCss, body), encoding: utf8);
    }
    return outDir;
  }

  // タイトル(任意でリンク化)。titleUrl 指定時は別タブで開くリンクにする。
  String _titleH1(String title, String titleUrl) => titleUrl.trim().isNotEmpty
      ? '<a href="${_escAttr(titleUrl.trim())}" target="_blank" '
          'rel="noopener noreferrer" '
          'style="color:inherit;text-decoration:none;">${_esc(title)}</a>'
      : _esc(title);

  // カード1枚(プロジェクト/タグタイル共通)
  String _cardHtml({
    required String href,
    required String? thumbRef,
    required String title,
    required String subtitle,
  }) {
    final initial = title.isNotEmpty ? title.substring(0, 1) : 'P';
    final thumb = thumbRef != null
        ? '<img src="$thumbRef" class="thumbnail" alt="${_escAttr(title)}">'
        : '<div class="no-image">${_esc(initial)}</div>';
    final sub = subtitle.isEmpty
        ? ''
        : '<div class="subtitle">${_esc(subtitle)}</div>';
    return '''
<a class="card" href="$href">
  <div class="thumbnail-container">
    $thumb
  </div>
  <div class="details"><div class="meta">
    <div class="title">${_esc(title)}</div>
    $sub
  </div></div>
</a>''';
  }

  // タグ別サブページ({outDir}/{tag_N}/index.html)。トップへ戻るリンク付き。
  Future<void> _writeTagSubPage(String tagDir, String tagName, String siteTitle,
      List<_Info> members, String portalCss) async {
    final cards = StringBuffer();
    for (final e in members) {
      cards.writeln(_cardHtml(
        // プロジェクトフォルダは root 直下 = サブページから1段上
        href: '../${Uri.encodeComponent(e.safeName)}/index.html',
        thumbRef: e.thumb != null ? '../${e.thumb}' : null,
        title: e.name,
        subtitle: '更新: ${e.updated}',
      ));
    }
    final siteTitleLine = siteTitle.trim().isEmpty
        ? ''
        : '<div style="font-size:12px;color:var(--text-secondary);margin-bottom:4px;">${_esc(siteTitle)}</div>';
    final body = '''
<a href="../index.html" class="back-link">← トップへ戻る</a>
<header>$siteTitleLine<h1>${_esc(tagName)}</h1></header>
<div class="grid">
$cards</div>
<footer>Generated by openManidoc</footer>''';
    await File('$tagDir${Platform.pathSeparator}index.html')
        .writeAsString(_pageHtml(tagName, portalCss, body), encoding: utf8);
  }

  // タグ定義画像(絶対パス)をタグフォルダへコピー。ファイル名を返す(失敗時null)。
  Future<String?> _copyTagImage(TagDefinition def, String tagDir) async {
    if (def.imagePath.trim().isEmpty) return null;
    final src = File(def.imagePath);
    if (!await src.exists()) return null;
    final ext = def.imagePath.split('.').last;
    final name = 'tagimg.$ext';
    try {
      await src.copy('$tagDir${Platform.pathSeparator}$name');
      return name;
    } catch (_) {
      return null;
    }
  }

  // ポータルの共通CSS(テーマ + 任意のカスタムCSS + タイル崩れ防止)
  Future<String> _buildPortalCss(String indexTheme, String customCssPath) async {
    var portalCss = _getIndexCss(indexTheme);
    if (customCssPath.isNotEmpty) {
      final customFile = File(customCssPath);
      if (await customFile.exists()) {
        portalCss += '\n/* Custom theme CSS */\n${await customFile.readAsString()}';
        portalCss += '''
\n/* Tile Layout Fix */
.grid { display: grid !important; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)) !important; gap: 16px !important; row-gap: 40px !important; }
.card { display: flex !important; flex-direction: column !important; text-decoration: none !important; padding: 0 !important; margin: 0 !important; border: none !important; }
.card .thumbnail-container { overflow: hidden !important; aspect-ratio: 16/9 !important; position: relative !important; margin: 0 0 12px 0 !important; padding: 0 !important; }
.card .thumbnail { width: 100% !important; height: 100% !important; object-fit: cover !important; object-position: center !important; display: block !important; margin: 0 !important; padding: 0 !important; }''';
      }
    }
    return portalCss;
  }

  // 完全なポータルHTMLページ(index/タグサブページ共通)
  String _pageHtml(String pageTitle, String portalCss, String bodyInner) => '''
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${_esc(pageTitle)}</title>
<style>
$portalCss
</style>
</head>
<body>
$bodyInner
</body>
</html>
''';

  String? _findFirstImage(List<ManidocNode> nodes) {
    for (final node in nodes) {
      if (node.imagePath.trim().isNotEmpty) return node.imagePath;
      final childImg = _findFirstImage(node.children);
      if (childImg != null) return childImg;
    }
    return null;
  }

  Future<String?> _copyThumbnail(
      ManidocProject project, String outDir, String folderName) async {
    final firstImage = _findFirstImage(project.rootNodes);
    if (firstImage == null || firstImage.trim().isEmpty) return null;

    // imagePath は "images/foo.png" 形式。imagesDirPath は既に images フォルダを
    // 指すため、そこへ更に "images/" を足すと二重になり存在しなくなる。
    // ファイル名だけを取り出して結合する。
    final fileName = firstImage.split('/').last;
    final imagesDir = Directory(workspace.imagesDirPath(project.id));
    final sourceFile =
        File('${imagesDir.path}${Platform.pathSeparator}$fileName');
    if (!await sourceFile.exists()) return null;

    final ext = fileName.split('.').last;
    final thumbName = 'thumb_$folderName.$ext';
    final destFile = File('$outDir${Platform.pathSeparator}$thumbName');

    await sourceFile.copy(destFile.path);
    return thumbName;
  }

  String _getIndexCss(String theme) {
    var baseCss = '';
    if (theme == 'Dark') {
      baseCss = '''
:root { --bg-color: #0f0f0f; --text-primary: #f1f1f1; --text-secondary: #aaaaaa; --card-bg: #1a1a1a; --back-link-color: #4a6cf7; }
body { font-family: "Segoe UI", "Hiragino Sans", "Noto Sans JP", sans-serif; background-color: var(--bg-color); margin: 0; padding: 0 0 40px 0; color: var(--text-primary); }
header { max-width: 1080px; margin: 0 auto; padding: 40px 24px 24px; }
h1 { font-size: 24px; font-weight: 700; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 16px; row-gap: 40px; max-width: 1080px; margin: 0 auto; padding: 0 24px; }
.card { text-decoration: none; color: inherit; display: flex; flex-direction: column; cursor: pointer; transition: transform 0.2s ease, box-shadow 0.2s ease; border-radius: 12px; }
.card:hover { transform: translateY(-8px); box-shadow: 0 12px 32px rgba(0,0,0,0.5); }
.thumbnail-container { width: 100%; aspect-ratio: 16 / 9; background-color: #2a2a2a; border-radius: 12px; overflow: hidden; position: relative; margin-bottom: 12px; transition: border-radius 0.2s; }
.card:hover .thumbnail-container { border-radius: 4px; }
.thumbnail { width: 100%; height: 100%; object-fit: cover; }
.no-image { width: 100%; height: 100%; background: linear-gradient(135deg, #4a6cf7, #7a4aef); display: flex; align-items: center; justify-content: center; color: white; font-weight: bold; font-size: 32px; }
.details { display: flex; padding: 0 4px; }
.meta { display: flex; flex-direction: column; }
.title { font-size: 16px; font-weight: 600; line-height: 22px; margin-bottom: 4px; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.subtitle { font-size: 14px; color: var(--text-secondary); }
footer { text-align: center; color: var(--text-secondary); font-size: 0.85rem; padding: 40px 0; }''';
    } else if (theme == 'Minimal') {
      baseCss = '''
:root { --bg-color: #ffffff; --text-primary: #111111; --text-secondary: #555555; --back-link-color: #333333; }
body { font-family: "Georgia", serif; background-color: var(--bg-color); margin: 0; padding: 0 0 40px 0; color: var(--text-primary); }
header { max-width: 1080px; margin: 0 auto; padding: 40px 24px 24px; border-bottom: 1px solid #ddd; }
h1 { font-size: 20px; font-weight: 400; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 24px; max-width: 1080px; margin: 40px auto 0; padding: 0 24px; }
.card { text-decoration: none; color: inherit; display: flex; flex-direction: column; cursor: pointer; border: 1px solid #e0e0e0; padding: 10px; transition: transform 0.2s ease, border-color 0.2s ease; }
.card:hover { transform: translateY(-4px); border-color: #999; }
.thumbnail-container { width: 100%; aspect-ratio: 16 / 9; background-color: #f0f0f0; overflow: hidden; position: relative; margin-bottom: 8px; }
.thumbnail { width: 100%; height: 100%; object-fit: cover; }
.no-image { width: 100%; height: 100%; background: #e8e8e8; display: flex; align-items: center; justify-content: center; color: #999; font-weight: bold; font-size: 28px; }
.details { display: flex; padding: 0; }
.meta { display: flex; flex-direction: column; }
.title { font-size: 14px; font-weight: 600; line-height: 20px; margin-bottom: 2px; }
.subtitle { font-size: 12px; color: var(--text-secondary); }
footer { text-align: center; color: var(--text-secondary); font-size: 0.85rem; padding: 40px 0; }''';
    } else {
      // Light
      baseCss = '''
:root { --bg-color: #f9f9f9; --text-primary: #0f0f0f; --text-secondary: #606060; --card-bg: #ffffff; --back-link-color: #0056b3; }
body { font-family: "Segoe UI", "Hiragino Sans", "Noto Sans JP", sans-serif; background-color: var(--bg-color); margin: 0; padding: 0 0 40px 0; color: var(--text-primary); }
header { max-width: 1080px; margin: 0 auto; padding: 40px 24px 24px; }
h1 { font-size: 24px; font-weight: 700; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 16px; row-gap: 40px; max-width: 1080px; margin: 0 auto; padding: 0 24px; }
.card { text-decoration: none; color: inherit; display: flex; flex-direction: column; cursor: pointer; transition: transform 0.2s ease, box-shadow 0.2s ease; border-radius: 12px; background: var(--card-bg); box-shadow: 0 2px 8px rgba(0,0,0,0.06); }
.card:hover { transform: translateY(-8px); box-shadow: 0 12px 32px rgba(0,0,0,0.12); }
.thumbnail-container { width: 100%; aspect-ratio: 16 / 9; background-color: #e5e5e5; border-radius: 12px 12px 0 0; overflow: hidden; position: relative; transition: border-radius 0.2s; }
.card:hover .thumbnail-container { border-radius: 12px 12px 0 0; }
.thumbnail { width: 100%; height: 100%; object-fit: cover; }
.no-image { width: 100%; height: 100%; background: linear-gradient(135deg, #6e8efb, #a777e3); display: flex; align-items: center; justify-content: center; color: white; font-weight: bold; font-size: 32px; }
.details { display: flex; padding: 12px 16px; }
.meta { display: flex; flex-direction: column; }
.title { font-size: 16px; font-weight: 600; line-height: 22px; margin-bottom: 4px; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.subtitle { font-size: 14px; color: var(--text-secondary); }
footer { text-align: center; color: var(--text-secondary); font-size: 0.85rem; padding: 40px 0; }''';
    }

    baseCss += '''
\n.back-link { position: fixed; top: 20px; left: 20px; background: var(--back-link-color, var(--primary-color, #0056b3)); color: white !important; padding: 0 20px; border-radius: 8px; text-decoration: none !important; font-weight: 600; font-size: 14px; height: 44px; display: flex; align-items: center; z-index: 1001; box-shadow: 0 4px 15px rgba(0,0,0,0.15); transition: all 0.3s ease; }
.back-link:hover { filter: brightness(0.9); transform: translateY(-2px); }''';

    return baseCss;
  }
}

/// ポータルのカード生成に使うプロジェクトの出力情報
class _Info {
  final String name;
  final String safeName;
  final String? thumb; // ルート直下のサムネイルファイル名(無ければnull)
  final String tag;
  final String updated;
  _Info({
    required this.name,
    required this.safeName,
    required this.thumb,
    required this.tag,
    required this.updated,
  });
}
