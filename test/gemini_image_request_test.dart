import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/services/ai_service.dart';

// ListModels のURL組み立てとエラーメッセージ抽出のテスト。
// (画像リクエスト系の実装は main では別方式のため、ここでは扱わない)
void main() {
  test('ListModelsのURLはキーとページトークンをエスケープする', () {
    final first = AiService.geminiModelsUri('AIza+key/with=chars');
    expect(first.host, 'generativelanguage.googleapis.com');
    expect(first.path, '/v1beta/models');
    // 生の連結だと + が空白と解釈されうる。queryParameters なら復元できる。
    expect(first.queryParameters['key'], 'AIza+key/with=chars');
    expect(first.queryParameters['pageSize'], '100');
    expect(first.queryParameters.containsKey('pageToken'), false);

    final next = AiService.geminiModelsUri('k', 'Cg8KDW1vZGVscy9nZW1pbmk=');
    expect(next.queryParameters['pageToken'], 'Cg8KDW1vZGVscy9nZW1pbmk=');
  });

  test('エラー本文から error.message を取り出す', () {
    const body = '{"error":{"code":400,"message":"Model does not support the '
        'requested response modalities","status":"INVALID_ARGUMENT"}}';
    expect(AiService.geminiErrorMessage(body),
        'Model does not support the requested response modalities');
    // JSONでない場合は本文をそのまま(長すぎるものは切り詰める)
    expect(AiService.geminiErrorMessage('<html>502</html>'), '<html>502</html>');
    expect(AiService.geminiErrorMessage('x' * 600).length, 501);
  });
}
