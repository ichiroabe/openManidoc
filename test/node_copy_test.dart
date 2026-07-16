import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/models/manidoc_node.dart';
import 'package:open_manidoc/services/node_copy_service.dart';
import 'package:open_manidoc/services/workspace_service.dart';

void main() {
  test('deepCopy assigns new ids and preserves fields/children', () {
    final source = ManidocNode(
        title: '親', article: '本文', comment: '注記', aiPrompt: 'p')
      ..children = [
        ManidocNode(title: '子1', imagePath: 'images/a.png'),
        ManidocNode(title: '子2')..children = [ManidocNode(title: '孫')],
      ];

    final copy = NodeCopyService.deepCopy(source);

    expect(copy.id, isNot(source.id));
    expect(copy.title, '親');
    expect(copy.article, '本文');
    expect(copy.comment, '注記');
    expect(copy.aiPrompt, 'p');
    expect(copy.children.length, 2);
    expect(copy.children[0].id, isNot(source.children[0].id));
    expect(copy.children[0].imagePath, 'images/a.png');
    expect(copy.children[1].children.single.title, '孫');
    // 複製後の変更が元に波及しない
    copy.children[1].children.single.title = '変更';
    expect(source.children[1].children.single.title, '孫');
  });

  test('referencedImageNames collects node image and inline markdown images',
      () {
    final node = ManidocNode(
        title: 't',
        imagePath: 'images/main.png',
        article: '説明 ![図](images/fig1.png) と ![](images/fig2.jpg)',
        comment: '> 参照 images/note.png');
    expect(NodeCopyService.referencedImageNames(node),
        {'main.png', 'fig1.png', 'fig2.jpg', 'note.png'});
  });

  test('copyNodeBetweenProjects copies images and renames on collision',
      () async {
    final tmp = await Directory.systemTemp.createTemp('om_nodecopy_test');
    final ws = WorkspaceService(tmp.path);
    const srcId = 'proj-src';
    const dstId = 'proj-dst';

    // 取り込み元の画像2枚 + 取り込み先に同名の別画像1枚(衝突)
    final srcImages = Directory(ws.imagesDirPath(srcId));
    await srcImages.create(recursive: true);
    await File('${srcImages.path}${Platform.pathSeparator}a.png')
        .writeAsString('src-a');
    await File('${srcImages.path}${Platform.pathSeparator}b.png')
        .writeAsString('src-b');
    final dstImages = Directory(ws.imagesDirPath(dstId));
    await dstImages.create(recursive: true);
    await File('${dstImages.path}${Platform.pathSeparator}a.png')
        .writeAsString('dst-a-existing');

    final source = ManidocNode(
        title: '取込元',
        imagePath: 'images/a.png',
        article: '本文 ![b](images/b.png)');

    final copy = await NodeCopyService.copyNodeBetweenProjects(
        ws, source, srcId, dstId);

    // 衝突しないbはそのままコピー
    expect(copy.article, contains('images/b.png'));
    expect(
        await File('${dstImages.path}${Platform.pathSeparator}b.png')
            .readAsString(),
        'src-b');

    // 衝突したaはリネームされ、参照も書き換わる
    expect(copy.imagePath, isNot('images/a.png'));
    expect(copy.imagePath, startsWith('images/a_'));
    final renamed = copy.imagePath.split('/').last;
    expect(
        await File('${dstImages.path}${Platform.pathSeparator}$renamed')
            .readAsString(),
        'src-a');
    // 既存ファイルは上書きされない
    expect(
        await File('${dstImages.path}${Platform.pathSeparator}a.png')
            .readAsString(),
        'dst-a-existing');

    await tmp.delete(recursive: true);
  });
}
