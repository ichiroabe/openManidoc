import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/models/manidoc_project.dart';
import 'package:open_manidoc/services/exports_manager.dart';
import 'package:open_manidoc/services/workspace_service.dart';

void main() {
  test('countHtml/deleteOldestHtml work for Japanese project names', () async {
    final tmp = await Directory.systemTemp.createTemp('om_exports_test');
    final ws = WorkspaceService(tmp.path);
    final project = ManidocProject(name: '背景色テスト');

    final exportsDir =
        Directory('${tmp.path}${Platform.pathSeparator}exports');
    // 3件のHTML出力フォルダ(タイムスタンプ違い)を用意
    for (final stamp in [
      '2026-07-13T10-00-00',
      '2026-07-13T11-00-00',
      '2026-07-13T12-00-00',
    ]) {
      final d = Directory(
          '${exportsDir.path}${Platform.pathSeparator}背景色テスト_$stamp');
      await d.create(recursive: true);
      await File('${d.path}${Platform.pathSeparator}index.html')
          .writeAsString('<html></html>');
    }

    final manager = ExportsManager(ws);
    expect(manager.countHtml(project), 3, reason: 'count should see 3 dirs');

    final deleted = await manager.deleteOldestHtml(project);
    expect(deleted, true, reason: 'oldest should be deleted');
    expect(manager.countHtml(project), 2);

    // 消えたのが一番古い 10-00-00 であること
    final remaining = Directory(exportsDir.path)
        .listSync()
        .whereType<Directory>()
        .map((d) => d.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
        .toList()
      ..sort();
    expect(remaining.first.contains('11-00-00'), true);

    await tmp.delete(recursive: true);
  });
}
