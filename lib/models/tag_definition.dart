/// ワークスペースのタグ定義(名前 + 任意のサムネイル画像パス)。
/// 旧Manidocの workspace.settings.json の tags[] と互換。
class TagDefinition {
  String name;
  String imagePath; // 絶対パス。空可

  TagDefinition({required this.name, this.imagePath = ''});

  factory TagDefinition.fromJson(Map<String, dynamic> json) => TagDefinition(
        name: json['name'] as String? ?? '',
        imagePath: json['imagePath'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'imagePath': imagePath,
      };
}
