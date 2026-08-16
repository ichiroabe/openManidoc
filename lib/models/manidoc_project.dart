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

  /// 一覧タイルの文字色 / 背景色。'#RRGGBB'、空文字なら既定(テーマ色)。
  /// 本家Manidocは知らないフィールドなので、空のときはJSONに出力しない。
  String cardForeColor;
  String cardBackColor;
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
    this.cardForeColor = '',
    this.cardBackColor = '',
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
        cardForeColor: json['cardForeColor'] as String? ?? '',
        cardBackColor: json['cardBackColor'] as String? ?? '',
        rootNodes: (json['rootNodes'] as List<dynamic>? ?? [])
            .map((e) => ManidocNode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'lastModifiedAt': lastModifiedAt.toIso8601String(),
      'description': description,
      'lastSelectedNodeId': lastSelectedNodeId,
      'sortOrder': sortOrder,
      'themeCssFileName': themeCssFileName,
      'tag': tag,
    };
    // 未設定なら出力しない(本家Manidocが読むJSONを不要に汚さない)
    if (cardForeColor.isNotEmpty) json['cardForeColor'] = cardForeColor;
    if (cardBackColor.isNotEmpty) json['cardBackColor'] = cardBackColor;
    json['rootNodes'] = rootNodes.map((e) => e.toJson()).toList();
    return json;
  }
}
