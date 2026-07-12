import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/models/manidoc_node.dart';
import 'package:open_manidoc/models/manidoc_project.dart';

void main() {
  test('project JSON round-trip keeps tree structure', () {
    final project = ManidocProject(name: 'テスト')
      ..rootNodes = [
        ManidocNode(title: '第1章', article: '# 見出し\n本文', comment: 'メモ')
          ..children = [ManidocNode(title: '1-1', imagePath: 'images/a.png')],
        ManidocNode(title: '第2章'),
      ];

    final decoded = ManidocProject.fromJson(
        jsonDecode(jsonEncode(project.toJson())) as Map<String, dynamic>);

    expect(decoded.name, 'テスト');
    expect(decoded.rootNodes.length, 2);
    expect(decoded.rootNodes[0].children.length, 1);
    expect(decoded.rootNodes[0].children[0].imagePath, 'images/a.png');
    expect(decoded.rootNodes[0].article, '# 見出し\n本文');
  });

  test('old Manidoc JSON (Newtonsoft dates etc.) can be imported', () {
    const legacyJson = '''
    {
      "id": "abc-123",
      "name": "旧プロジェクト",
      "createdAt": "2026-03-19T12:34:56.789+09:00",
      "lastModifiedAt": "2026-03-20T01:02:03+09:00",
      "description": "",
      "lastSelectedNodeId": "n1",
      "sortOrder": 2,
      "themeCssFileName": "aurora.css",
      "tag": "仕事",
      "rootNodes": [
        {"id": "n1", "title": "章", "comment": "", "article": "本文",
         "imagePath": "images/x.png", "aiPrompt": "", "children": []}
      ]
    }
    ''';
    final project = ManidocProject.fromJson(
        jsonDecode(legacyJson) as Map<String, dynamic>);
    expect(project.id, 'abc-123');
    expect(project.sortOrder, 2);
    expect(project.rootNodes.single.imagePath, 'images/x.png');
    expect(project.createdAt.year, 2026);
  });
}
