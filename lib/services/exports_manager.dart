import 'dart:io';

import '../models/manidoc_project.dart';
import 'workspace_service.dart';

/// 出力整理: exportsフォルダ内のHTML/MD出力の件数把握と古い順削除
class ExportsManager {
  final WorkspaceService workspace;

  ExportsManager(this.workspace);

  String get exportsDir =>
      '${workspace.workspacePath}${Platform.pathSeparator}exports';

  static String safeName(ManidocProject project) =>
      project.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  List<Directory> _htmlDirs(ManidocProject project) {
    final dir = Directory(exportsDir);
    if (!dir.existsSync()) return [];
    final prefix = '${safeName(project)}_';
    final dirs = dir
        .listSync()
        .whereType<Directory>()
        .where((d) => d.uri.pathSegments
            .lastWhere((s) => s.isNotEmpty)
            .startsWith(prefix))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path)); // タイムスタンプ名なので辞書順=古い順
    return dirs;
  }

  List<File> _mdFiles(ManidocProject project) {
    final dir = Directory(exportsDir);
    if (!dir.existsSync()) return [];
    final prefix = '${safeName(project)}_';
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final name = f.uri.pathSegments.last;
          return name.startsWith(prefix) && name.endsWith('.md');
        })
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  int countHtml(ManidocProject project) => _htmlDirs(project).length;

  int countMd(ManidocProject project) => _mdFiles(project).length;

  /// 1番古いHTML出力フォルダを削除。削除したらtrue。
  Future<bool> deleteOldestHtml(ManidocProject project) async {
    final dirs = _htmlDirs(project);
    if (dirs.isEmpty) return false;
    await dirs.first.delete(recursive: true);
    return true;
  }

  Future<bool> deleteOldestMd(ManidocProject project) async {
    final files = _mdFiles(project);
    if (files.isEmpty) return false;
    await files.first.delete();
    return true;
  }
}
