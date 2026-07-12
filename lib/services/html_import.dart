import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';
import 'workspace_service.dart';

/// HTML文字列/WebページをManidocのツリーへ変換する。
/// h1〜h6を階層ノードに、それ以外のテキストをMarkdown風の本文に変換。
/// 画像は resolveImage で images/ フォルダへ取り込み、参照を差し替える。
class HtmlImport {
  /// ローカルHTMLファイルをプロジェクト化(同フォルダの画像をコピー)
  static Future<ManidocProject> importHtmlFile(
      WorkspaceService workspace, String filePath) async {
    final content = await File(filePath).readAsString();
    final baseDir = File(filePath).parent.path;
    final name = filePath
        .split(Platform.pathSeparator)
        .last
        .replaceAll(RegExp(r'\.(html?|xhtml)$', caseSensitive: false), '');
    final project = ManidocProject(name: name);
    await _parseInto(project, content, (src) async {
      if (src.startsWith('http')) return _download(workspace, project.id, src);
      final local = File(
          '$baseDir${Platform.pathSeparator}${Uri.decodeComponent(src).replaceAll('/', Platform.pathSeparator)}');
      if (!await local.exists()) return null;
      return workspace.importImage(project.id, local.path);
    });
    return project;
  }

  /// WebページのURLをプロジェクト化(画像もダウンロード)
  static Future<ManidocProject> importUrl(
      WorkspaceService workspace, String url) async {
    final response =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw Exception('ページの取得に失敗しました (${response.statusCode})');
    }
    final content = utf8.decode(response.bodyBytes, allowMalformed: true);
    final doc = html_parser.parse(content);
    final title = doc.querySelector('title')?.text.trim();
    final project = ManidocProject(
        name: (title == null || title.isEmpty) ? url : title);
    await _parseInto(project, content, (src) async {
      final resolved = Uri.parse(url).resolve(src).toString();
      return _download(workspace, project.id, resolved);
    });
    return project;
  }

  static Future<String?> _download(
      WorkspaceService workspace, String projectId, String url) async {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      final ext = url.toLowerCase().contains('.jpg') ||
              url.toLowerCase().contains('.jpeg')
          ? '.jpg'
          : url.toLowerCase().contains('.gif')
              ? '.gif'
              : url.toLowerCase().contains('.webp')
                  ? '.webp'
                  : '.png';
      return await workspace.importImageBytes(projectId, response.bodyBytes,
          ext: ext);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _parseInto(
      ManidocProject project,
      String htmlContent,
      Future<String?> Function(String src) resolveImage) async {
    final doc = html_parser.parse(htmlContent);
    final body = doc.body;
    if (body == null) return;

    final stack = <(int, ManidocNode)>[];
    ManidocNode? current;
    final buffer = StringBuffer();
    var firstImageForNode = true;

    void flush() {
      final text = buffer.toString().trim();
      if (current != null) {
        current!.article = text;
      } else if (text.isNotEmpty) {
        project.rootNodes.add(ManidocNode(title: 'はじめに')..article = text);
      }
      buffer.clear();
    }

    void setImage(String rel) {
      final node = current;
      if (node != null && firstImageForNode && node.imagePath.isEmpty) {
        node.imagePath = rel;
        firstImageForNode = false;
      } else {
        buffer.writeln('![]($rel)\n');
      }
    }

    Future<void> walk(dom.Element element) async {
      for (final child in element.children) {
        final tag = child.localName ?? '';
        final headingMatch = RegExp(r'^h([1-6])$').firstMatch(tag);
        if (headingMatch != null) {
          flush();
          final level = int.parse(headingMatch.group(1)!);
          final node = ManidocNode(title: child.text.trim());
          while (stack.isNotEmpty && stack.last.$1 >= level) {
            stack.removeLast();
          }
          if (stack.isEmpty) {
            project.rootNodes.add(node);
          } else {
            stack.last.$2.children.add(node);
          }
          stack.add((level, node));
          current = node;
          firstImageForNode = true;
          continue;
        }
        switch (tag) {
          case 'p':
            final text = child.text.trim();
            if (text.isNotEmpty) buffer.writeln('$text\n');
            await _images(child, resolveImage, buffer, setImage);
          case 'ul':
            for (final li in child.querySelectorAll('li')) {
              buffer.writeln('- ${li.text.trim()}');
            }
            buffer.writeln();
          case 'ol':
            var i = 1;
            for (final li in child.querySelectorAll('li')) {
              buffer.writeln('${i++}. ${li.text.trim()}');
            }
            buffer.writeln();
          case 'pre':
            buffer.writeln('```\n${child.text.trimRight()}\n```\n');
          case 'table':
            for (final row in child.querySelectorAll('tr')) {
              final cells = row
                  .querySelectorAll('th,td')
                  .map((c) => c.text.trim())
                  .toList();
              buffer.writeln('| ${cells.join(' | ')} |');
            }
            buffer.writeln();
          case 'img':
            await _images(child, resolveImage, buffer, setImage);
          case 'script':
          case 'style':
          case 'nav':
          case 'footer':
          case 'header':
            break; // 本文と無関係な要素はスキップ
          default:
            await walk(child); // div/section/article等は中へ
        }
      }
    }

    await walk(body);
    flush();
    if (project.rootNodes.isEmpty) {
      project.rootNodes.add(ManidocNode(title: project.name));
    }
  }

  static Future<void> _images(
      dom.Element element,
      Future<String?> Function(String src) resolveImage,
      StringBuffer buffer,
      void Function(String rel) onImage) async {
    final imgs = element.localName == 'img'
        ? [element]
        : element.querySelectorAll('img');
    for (final img in imgs) {
      final src = img.attributes['src'];
      if (src == null || src.isEmpty || src.startsWith('data:')) continue;
      final rel = await resolveImage(src);
      if (rel != null) onImage(rel);
    }
  }
}
