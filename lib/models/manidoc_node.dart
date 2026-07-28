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

  /// 没入モード読み上げの話者(VOICEVOXスタイルID)。題名/記事/コメント個別。
  /// null = 未設定 → 設定ウィンドウの話者にフォロー。
  int? titleSpeaker;
  int? articleSpeaker;
  int? commentSpeaker;

  /// UIのみで使用（保存しない）
  bool isExpanded;

  ManidocNode({
    String? id,
    this.title = '新しい項目',
    this.comment = '',
    this.article = '',
    this.imagePath = '',
    this.aiPrompt = '',
    this.titleSpeaker,
    this.articleSpeaker,
    this.commentSpeaker,
    List<ManidocNode>? children,
    this.isExpanded = true,
  })  : id = id ?? _uuid.v4(),
        children = children ?? [];

  static int? _speaker(Object? v) => v is num ? v.toInt() : null;

  factory ManidocNode.fromJson(Map<String, dynamic> json) => ManidocNode(
        id: json['id'] as String? ?? _uuid.v4(),
        title: json['title'] as String? ?? '',
        comment: json['comment'] as String? ?? '',
        article: json['article'] as String? ?? '',
        imagePath: json['imagePath'] as String? ?? '',
        aiPrompt: json['aiPrompt'] as String? ?? '',
        titleSpeaker: _speaker(json['titleSpeaker']),
        articleSpeaker: _speaker(json['articleSpeaker']),
        commentSpeaker: _speaker(json['commentSpeaker']),
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
        // 未設定(null)のキーは出力しない → 既存プロジェクトと後方互換
        if (titleSpeaker != null) 'titleSpeaker': titleSpeaker,
        if (articleSpeaker != null) 'articleSpeaker': articleSpeaker,
        if (commentSpeaker != null) 'commentSpeaker': commentSpeaker,
        'children': children.map((e) => e.toJson()).toList(),
      };
}
