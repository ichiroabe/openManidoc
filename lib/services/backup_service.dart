import 'dart:io';

import 'package:archive/archive_io.dart';

import '../models/manidoc_project.dart';
import 'workspace_service.dart';

/// プロジェクトのZIPバックアップと復元。
/// ZIP内レイアウト: {projectId}.json + {projectId}/images/*
class BackupService {
  final WorkspaceService workspace;

  BackupService(this.workspace);

  String get backupDir =>
      '${workspace.workspacePath}${Platform.pathSeparator}backups';

  Future<String> backupProject(ManidocProject project) async {
    await Directory(backupDir).create(recursive: true);
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    final safeName = project.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final zipPath =
        '$backupDir${Platform.pathSeparator}${safeName}_$stamp.zip';

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    await encoder.addFile(File(workspace.projectFilePath(project.id)));
    final assetDir = Directory(
        '${workspace.workspacePath}${Platform.pathSeparator}${project.id}');
    if (await assetDir.exists()) {
      await encoder.addDirectory(assetDir);
    }
    await encoder.close();
    return zipPath;
  }

  /// ZIPをワークスペースへ展開して復元(同名プロジェクトは上書き)
  Future<void> restoreFromZip(String zipPath) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final entry in archive) {
      if (!entry.isFile) continue;
      // Zip Slip対策: ワークスペース外への書き込みを拒否
      final normalized = entry.name.replaceAll('\\', '/');
      if (normalized.contains('..')) continue;
      final outPath =
          '${workspace.workspacePath}${Platform.pathSeparator}${normalized.replaceAll('/', Platform.pathSeparator)}';
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(entry.content as List<int>);
    }
  }
}
