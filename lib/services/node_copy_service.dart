import 'dart:io';

import '../models/manidoc_node.dart';
import 'workspace_service.dart';

/// 他プロジェクトからのノード取り込み(本家 DeepCopyNode / CopyNodeImage 準拠)。
/// サブツリーを新しいidで複製し、参照している画像を取り込み先のimagesへコピーする。
class NodeCopyService {
  static final _imageRefRe = RegExp(r'images/([^)\s"]+)');

  static Future<ManidocNode> copyNodeBetweenProjects(
    WorkspaceService workspace,
    ManidocNode source,
    String sourceProjectId,
    String targetProjectId,
  ) async {
    final copy = deepCopy(source);
    await _adoptImages(workspace, copy, sourceProjectId, targetProjectId);
    return copy;
  }

  /// idを振り直してサブツリーを複製する
  static ManidocNode deepCopy(ManidocNode node) => ManidocNode(
        title: node.title,
        comment: node.comment,
        article: node.article,
        imagePath: node.imagePath,
        aiPrompt: node.aiPrompt,
        isExpanded: node.isExpanded,
        children: node.children.map(deepCopy).toList(),
      );

  /// サブツリーが参照する画像ファイル名(images/xxx)を集める
  static Set<String> referencedImageNames(ManidocNode node) {
    final names = <String>{};
    void walk(ManidocNode n) {
      if (n.imagePath.isNotEmpty) names.add(n.imagePath.split('/').last);
      for (final text in [n.article, n.comment]) {
        for (final m in _imageRefRe.allMatches(text)) {
          names.add(m.group(1)!);
        }
      }
      n.children.forEach(walk);
    }

    walk(node);
    return names;
  }

  static Future<void> _adoptImages(
    WorkspaceService workspace,
    ManidocNode copy,
    String sourceProjectId,
    String targetProjectId,
  ) async {
    final names = referencedImageNames(copy);
    if (names.isEmpty) return;

    final destDir = Directory(workspace.imagesDirPath(targetProjectId));
    final renames = <String, String>{};
    for (final name in names) {
      final src =
          File(workspace.resolveImagePath(sourceProjectId, 'images/$name'));
      if (!await src.exists()) continue;
      await destDir.create(recursive: true);
      var dest = File('${destDir.path}${Platform.pathSeparator}$name');
      if (await dest.exists()) {
        // 同名ファイルがある場合はリネームして参照を書き換える(本家準拠)
        final dot = name.lastIndexOf('.');
        final base = dot > 0 ? name.substring(0, dot) : name;
        final ext = dot > 0 ? name.substring(dot) : '';
        var newName = '${base}_${DateTime.now().millisecondsSinceEpoch}$ext';
        var candidate = File('${destDir.path}${Platform.pathSeparator}$newName');
        var seq = 1;
        while (await candidate.exists()) {
          newName = '${base}_${DateTime.now().millisecondsSinceEpoch}_$seq$ext';
          candidate = File('${destDir.path}${Platform.pathSeparator}$newName');
          seq++;
        }
        dest = candidate;
        renames[name] = newName;
      }
      await src.copy(dest.path);
    }
    if (renames.isNotEmpty) _rewriteImageRefs(copy, renames);
  }

  static void _rewriteImageRefs(ManidocNode node, Map<String, String> renames) {
    void walk(ManidocNode n) {
      for (final entry in renames.entries) {
        final oldRef = 'images/${entry.key}';
        final newRef = 'images/${entry.value}';
        if (n.imagePath.split('/').last == entry.key) {
          n.imagePath = newRef;
        }
        n.article = n.article.replaceAll(oldRef, newRef);
        n.comment = n.comment.replaceAll(oldRef, newRef);
      }
      n.children.forEach(walk);
    }

    walk(node);
  }
}
