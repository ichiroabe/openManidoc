import 'dart:io';

import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';

/// Markdownファイル ⇔ ノードツリーの相互変換
class MarkdownIo {
  /// 見出し(# ## ###…)の階層でノードツリーを構築してプロジェクト化する
  static ManidocProject importAsProject(String name, String markdown) {
    final project = ManidocProject(name: name);
    final headingRe = RegExp(r'^(#{1,6})\s+(.*)$');
    // (level, node) のスタックで親子を辿る
    final stack = <(int, ManidocNode)>[];
    ManidocNode? current;
    final buffer = StringBuffer();
    final commentBuffer = StringBuffer(); // 引用ブロック(>) はコメント欄へ

    void flush() {
      final node = current;
      final article = buffer.toString().trim();
      final comment = commentBuffer.toString().trim();
      if (node != null) {
        node.article = article;
        node.comment = comment;
      } else if (article.isNotEmpty || comment.isNotEmpty) {
        // 最初の見出しより前の本文は「はじめに」ノードへ
        project.rootNodes.add(ManidocNode(title: 'はじめに')
          ..article = article
          ..comment = comment);
      }
      buffer.clear();
      commentBuffer.clear();
    }

    for (final line in markdown.split('\n')) {
      final m = headingRe.firstMatch(line);
      if (m == null) {
        // 引用ブロック( > )はコメント欄へ振り分ける(本家準拠)
        final quote = RegExp(r'^\s*>\s?(.*)$').firstMatch(line);
        if (quote != null) {
          commentBuffer.writeln(quote.group(1));
        } else {
          buffer.writeln(line);
        }
        continue;
      }
      flush();
      final level = m.group(1)!.length;
      final node = ManidocNode(title: m.group(2)!.trim());
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
    }
    flush();
    if (project.rootNodes.isEmpty) {
      project.rootNodes.add(ManidocNode(title: name));
    }
    return project;
  }

  /// プロジェクト全体を1つのMarkdown文字列に変換する
  static String exportToMarkdown(ManidocProject project,
      {bool numbering = true}) {
    final buffer = StringBuffer('# ${project.name}\n\n');

    void walk(List<ManidocNode> nodes, int depth, String numberPrefix) {
      var index = 1;
      for (final node in nodes) {
        final number = numberPrefix.isEmpty ? '$index' : '$numberPrefix.$index';
        final hashes = '#' * (depth + 2).clamp(2, 6);
        final label = numbering ? '$number. ${node.title}' : node.title;
        buffer.writeln('$hashes $label\n');
        if (node.article.trim().isNotEmpty) {
          buffer.writeln('${node.article.trim()}\n');
        }
        if (node.imagePath.trim().isNotEmpty) {
          buffer.writeln('![${node.title}](${node.imagePath})\n');
        }
        if (node.comment.trim().isNotEmpty) {
          // コメントは引用ブロックとして出力
          for (final line in node.comment.trim().split('\n')) {
            buffer.writeln('> $line');
          }
          buffer.writeln();
        }
        walk(node.children, depth + 1, number);
        index++;
      }
    }

    walk(project.rootNodes, 0, '');
    return buffer.toString();
  }

  static Future<String> exportToFile(
      ManidocProject project, String outputDir, {bool numbering = true}) async {
    await Directory(outputDir).create(recursive: true);
    final safeName = project.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    final path = '$outputDir${Platform.pathSeparator}${safeName}_$stamp.md';
    await File(path)
        .writeAsString(exportToMarkdown(project, numbering: numbering));
    return path;
  }
}

/// GFMテーブルの前後に空行を保証する。
/// appflowy の documentToMarkdown はテーブルと前後ブロックの間に空行を入れないため、
/// GFMパーサ(プレビュー/HTML出力)が後続行をテーブルの行として吸収してしまう。
/// テーブル外のテキストが表に混ざらないよう、テーブルブロックの前後へ空行を挿入する。
/// (コードフェンス ```/~~~ の内側は対象外)
String fixTableMarkdownSpacing(String markdown) {
  final lines = markdown.split('\n');
  bool isRow(String l) {
    final t = l.trim();
    return t.length >= 2 && t.startsWith('|') && t.endsWith('|');
  }

  final out = <String>[];
  var inFence = false;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
      out.add(line);
      continue;
    }
    if (inFence) {
      out.add(line);
      continue;
    }
    final prev = out.isNotEmpty ? out.last : null;
    if (prev != null && prev.trim().isNotEmpty) {
      // テーブル開始の直前が非テーブル行 → 空行を挿入
      if (isRow(line) && !isRow(prev)) out.add('');
      // テーブル直後の非テーブル行 → 空行を挿入
      if (!isRow(line) && trimmed.isNotEmpty && isRow(prev)) out.add('');
    }
    out.add(line);
  }
  return out.join('\n');
}
