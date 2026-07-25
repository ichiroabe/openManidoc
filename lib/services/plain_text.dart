/// Markdown本文を読み上げ用のプレーンテキストに落とす簡易変換。
/// 完全なパースはせず、記号を除去して自然に読めればよい方針。
String markdownToPlain(String md) {
  var s = md;
  // コードフェンス除去
  s = s.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  // 画像 ![alt](url) → alt
  s = s.replaceAllMapped(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (m) => m[1] ?? '');
  // リンク [text](url) → text
  s = s.replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1] ?? '');
  // 見出し/引用/リスト記号(行頭)
  s = s.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s{0,3}[-*+]\s+', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s{0,3}\d+\.\s+', multiLine: true), '');
  // 強調/インラインコード記号
  s = s.replaceAll(RegExp(r'[*_`~]'), '');
  // テーブルの区切り
  s = s.replaceAll(RegExp(r'^\s*\|?[-:\s|]+\|?\s*$', multiLine: true), ' ');
  s = s.replaceAll('|', ' ');
  // 連続空白/空行を圧縮
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
  s = s.replaceAll(RegExp(r'\n{2,}'), '\n');
  return s.trim();
}
