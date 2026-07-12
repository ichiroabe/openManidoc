import 'package:uuid/uuid.dart';

import 'manidoc_node.dart';

const _uuid = Uuid();

/// プロジェクト全体。旧Manidocの {projectId}.json と互換。
class ManidocProject {
  String id;
  String name;
  DateTime createdAt;
  DateTime lastModifiedAt;
  String description;
  String lastSelectedNodeId;
  int sortOrder;
  String themeCssFileName;
  String tag;
  List<ManidocNode> rootNodes;

  ManidocProject({
    String? id,
    required this.name,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
    this.description = '',
    this.lastSelectedNodeId = '',
    this.sortOrder = 0,
    this.themeCssFileName = '',
    this.tag = '',
    List<ManidocNode>? rootNodes,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        lastModifiedAt = lastModifiedAt ?? DateTime.now(),
        rootNodes = rootNodes ?? [];

  static DateTime _parseDate(dynamic value) =>
      value is String ? (DateTime.tryParse(value) ?? DateTime.now()) : DateTime.now();

  factory ManidocProject.fromJson(Map<String, dynamic> json) => ManidocProject(
        id: json['id'] as String? ?? _uuid.v4(),
        name: json['name'] as String? ?? '(無題)',
        createdAt: _parseDate(json['createdAt']),
        lastModifiedAt: _parseDate(json['lastModifiedAt']),
        description: json['description'] as String? ?? '',
        lastSelectedNodeId: json['lastSelectedNodeId'] as String? ?? '',
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        themeCssFileName: json['themeCssFileName'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
        rootNodes: (json['rootNodes'] as List<dynamic>? ?? [])
            .map((e) => ManidocNode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'lastModifiedAt': lastModifiedAt.toIso8601String(),
        'description': description,
        'lastSelectedNodeId': lastSelectedNodeId,
        'sortOrder': sortOrder,
        'themeCssFileName': themeCssFileName,
        'tag': tag,
        'rootNodes': rootNodes.map((e) => e.toJson()).toList(),
      };
}
