import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// VOICEVOX ENGINE(別途起動)への薄いクライアント。
/// 既定エンドポイントは http://127.0.0.1:50021。
/// フロー: POST /audio_query → POST /synthesis → WAVバイト列。
class VoicevoxService {
  final String endpoint;
  VoicevoxService(this.endpoint);

  Uri _u(String path, [Map<String, String>? query]) {
    final base = Uri.parse(endpoint);
    return base.replace(
      path: path,
      queryParameters: {...base.queryParameters, ...?query},
    );
  }

  /// エンジンが起動しているか(/version が返るか)。
  Future<bool> isAvailable() async {
    try {
      final res = await http
          .get(_u('/version'))
          .timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 話者一覧(表示名 → 代表スタイルID)。失敗時は空。
  Future<List<({String name, int id})>> speakers() async {
    try {
      final res = await http
          .get(_u('/speakers'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return [];
      final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
      final out = <({String name, int id})>[];
      for (final s in list) {
        final m = s as Map<String, dynamic>;
        final styles = (m['styles'] as List<dynamic>? ?? []);
        for (final st in styles) {
          final sm = st as Map<String, dynamic>;
          out.add((
            name: '${m['name']} / ${sm['name']}',
            id: (sm['id'] as num).toInt(),
          ));
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// テキストを合成してWAVバイト列を返す。失敗時は例外。
  Future<Uint8List> synthesize(String text, int speaker,
      {double speed = 1.0}) async {
    // 1) audio_query
    final queryRes = await http
        .post(_u('/audio_query',
            {'text': text, 'speaker': '$speaker'}))
        .timeout(const Duration(seconds: 20));
    if (queryRes.statusCode != 200) {
      throw Exception('audio_query failed: ${queryRes.statusCode}');
    }
    final query = jsonDecode(utf8.decode(queryRes.bodyBytes))
        as Map<String, dynamic>;
    query['speedScale'] = speed;

    // 2) synthesis
    final synthRes = await http
        .post(
          _u('/synthesis', {'speaker': '$speaker'}),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(query),
        )
        .timeout(const Duration(seconds: 60));
    if (synthRes.statusCode != 200) {
      throw Exception('synthesis failed: ${synthRes.statusCode}');
    }
    return synthRes.bodyBytes;
  }
}
