import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// マニュアルの1項目（章・節・項）。旧Manidocのnode形式と互換。
class ManidocNode {
  String id;
  String title;
  String comment;
  String article;
  String imagePath;
  String aiPrompt;
  List<ManidocNode> children;

  /// UIのみで使用（保存しない）
  bool isExpanded;

  ManidocNode({
    String? id,
    this.title = '新しい項目',
    this.comment = '',
    this.article = '',
    this.imagePath = '',
    this.aiPrompt = '',
    List<ManidocNode>? children,
    this.isExpanded = true,
  })  : id = id ?? _uuid.v4(),
        children = children ?? [];

  factory ManidocNode.fromJson(Map<String, dynamic> json) => ManidocNode(
        id: json['id'] as String? ?? _uuid.v4(),
        title: json['title'] as String? ?? '',
        comment: json['comment'] as String? ?? '',
        article: json['article'] as String? ?? '',
        imagePath: json['imagePath'] as String? ?? '',
        aiPrompt: json['aiPrompt'] as String? ?? '',
        children: (json['children'] as List<dynamic>? ?? [])
            .map((e) => ManidocNode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'comment': comment,
        'article': article,
        'imagePath': imagePath,
        'aiPrompt': aiPrompt,
        'children': children.map((e) => e.toJson()).toList(),
      };
}
