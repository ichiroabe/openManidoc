import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'settings_service.dart';

class AiException implements Exception {
  final String message;
  AiException(this.message);
  @override
  String toString() => message;
}

/// AI連携。ChatGPT/ClaudeのAPIおよび通信処理をサポート。
class AiService {
  final AppSettings settings;

  AiService(this.settings);

  static const _timeout = Duration(seconds: 120);

  /// 単発のテキスト生成
  Future<String> generateText(String prompt, {String? systemInstruction}) =>
      chat([('user', prompt)], systemInstruction: systemInstruction);

  /// 会話履歴つき生成。roleは 'user' / 'assistant'。
  /// [useGrounding] が true かつ Gemini の場合、Google検索(grounding)で最新情報を参照する。
  Future<String> chat(List<(String, String)> history,
      {String? systemInstruction, bool useGrounding = false}) async {
    switch (settings.effectiveAIProvider) {
      case 'Gemini':
        return _geminiChat(history, systemInstruction, useGrounding);
      case 'ChatGPT':
        return _chatgptChat(history, systemInstruction);
      case 'Claude':
        return _claudeChat(history, systemInstruction);
      case 'LocalLLM':
        // ローカルLLMはWeb検索非対応
        return _localLlmChat(history, systemInstruction);
      default:
        throw AiException('AIプロバイダが未設定です。「⚙ 設定」からAPIキー'
            'またはローカルLLMのエンドポイントを設定してください。');
    }
  }

  /// Web検索(grounding)が使えるのはGeminiプロバイダのときのみ
  bool get supportsWebSearch => settings.effectiveAIProvider == 'Gemini';

  Future<String> _geminiChat(List<(String, String)> history,
      String? systemInstruction, bool useGrounding) async {
    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '${settings.geminiModel}:generateContent?key=${settings.geminiApiKey}');
    final body = <String, dynamic>{
      'contents': [
        for (final (role, content) in history)
          {
            'role': role == 'assistant' ? 'model' : 'user',
            'parts': [
              {'text': content}
            ],
          }
      ],
      if (systemInstruction != null)
        'systemInstruction': {
          'parts': [
            {'text': systemInstruction}
          ]
        },
      // Google検索によるグラウンディング(Web検索)
      if (useGrounding)
        'tools': [
          {'google_search': <String, dynamic>{}}
        ],
    };
    final response = await http
        .post(url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw AiException(_geminiError(response.statusCode, response.body));
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    final candidate = json?['candidates']?[0];
    final parts = candidate?['content']?['parts'] as List?;
    // Thinkingモデルは thought パートを含むので、非thoughtのtextのみ採用
    final text = parts
        ?.where((p) => p['thought'] != true)
        .map((p) => p['text'] as String? ?? '')
        .where((t) => t.isNotEmpty)
        .join();
    if (text == null || text.isEmpty) {
      throw AiException('Geminiからテキストレスポンスを取得できませんでした。');
    }
    // grounding時は検索ソースを末尾に付ける
    if (useGrounding) {
      final chunks =
          candidate?['groundingMetadata']?['groundingChunks'] as List?;
      if (chunks != null && chunks.isNotEmpty) {
        final buffer = StringBuffer(text)
          ..write('\n\n---\n**検索ソース:**\n');
        var idx = 1;
        for (final chunk in chunks) {
          final title = chunk['web']?['title'] as String? ?? '';
          final uri = chunk['web']?['uri'] as String? ?? '';
          if (uri.isNotEmpty) buffer.writeln('${idx++}. [$title]($uri)');
        }
        return buffer.toString();
      }
    }
    return text;
  }

  String _geminiError(int status, String body) {
    switch (status) {
      case 400:
      case 401:
      case 403:
        return 'Gemini APIリクエストに失敗しました($status)。'
            '「⚙ 設定」で正しいAPIキーが設定されているか確認してください。';
      case 429:
        return 'Gemini APIの利用上限に達しました(429)。しばらく待ってから再実行してください。';
      default:
        return 'Geminiサーバーエラーが発生しました($status)。\n$body';
    }
  }

  Future<String> _chatgptChat(
      List<(String, String)> history, String? systemInstruction) async {
    final url = Uri.parse('https://api.openai.com/v1/chat/completions');
    final body = <String, dynamic>{
      'model': settings.openaiModel.isEmpty ? 'gpt-4o' : settings.openaiModel,
      'messages': [
        if (systemInstruction != null)
          {'role': 'system', 'content': systemInstruction},
        for (final (role, content) in history)
          {'role': role, 'content': content},
      ],
    };
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${settings.openaiApiKey}',
      },
      body: jsonEncode(body),
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw AiException('ChatGPT APIエラー(${response.statusCode}):\n${utf8.decode(response.bodyBytes)}');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    final text = json?['choices']?[0]?['message']?['content'] as String?;
    if (text == null || text.isEmpty) {
      throw AiException('ChatGPTからレスポンスを取得できませんでした。');
    }
    return text;
  }

  Future<String> _claudeChat(
      List<(String, String)> history, String? systemInstruction) async {
    final url = Uri.parse('https://api.anthropic.com/v1/messages');
    final body = <String, dynamic>{
      'model': settings.claudeModel.isEmpty ? 'claude-3-5-sonnet-20241022' : settings.claudeModel,
      'max_tokens': 4000,
      if (systemInstruction != null) 'system': systemInstruction,
      'messages': [
        for (final (role, content) in history)
          {
            'role': role == 'assistant' ? 'assistant' : 'user',
            'content': content,
          },
      ],
    };
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': settings.claudeApiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode(body),
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw AiException('Claude APIエラー(${response.statusCode}):\n${utf8.decode(response.bodyBytes)}');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    final text = json?['content']?[0]?['text'] as String?;
    if (text == null || text.isEmpty) {
      throw AiException('Claudeからレスポンスを取得できませんでした。');
    }
    return text;
  }

  Future<String> _localLlmChat(
      List<(String, String)> history, String? systemInstruction) async {
    final url = Uri.parse(
        '${settings.localLlmEndpoint.replaceAll(RegExp(r'/+$'), '')}/chat/completions');
    final body = <String, dynamic>{
      // Ollama等はmodel必須。空ならLM Studioがロード中モデルを自動使用。
      if (settings.localLlmModel.isNotEmpty) 'model': settings.localLlmModel,
      'messages': [
        if (systemInstruction != null)
          {'role': 'system', 'content': systemInstruction},
        for (final (role, content) in history)
          {'role': role, 'content': content},
      ],
    };
    final http.Response response;
    try {
      response = await http
          .post(url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(_timeout);
    } catch (e) {
      throw AiException('ローカルLLMに接続できませんでした。'
          'LM Studio / Ollama が起動しているか、エンドポイントURL'
          '(${settings.localLlmEndpoint})が正しいか確認してください。\n$e');
    }
    if (response.statusCode != 200) {
      throw AiException(
          'ローカルLLMエラー(${response.statusCode})\n${utf8.decode(response.bodyBytes)}');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    final text = json?['choices']?[0]?['message']?['content'] as String?;
    if (text == null || text.isEmpty) {
      throw AiException('ローカルLLMからレスポンスを取得できませんでした。');
    }
    return text;
  }

  /// Geminiによる画像生成。PNGバイト列を返す。
  Future<Uint8List> generateImage(String prompt) async {
    if (!settings.hasGeminiKey) {
      throw AiException('画像生成にはGemini APIキーが必要です。「⚙ 設定」から設定してください。');
    }
    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-2.5-flash-image:generateContent?key=${settings.geminiApiKey}');
    final body = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
    };
    final response = await http
        .post(url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw AiException(_geminiError(response.statusCode, response.body));
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    final parts = json?['candidates']?[0]?['content']?['parts'] as List?;
    for (final part in parts ?? []) {
      final data = part['inlineData']?['data'] as String?;
      if (data != null) return base64Decode(data);
    }
    throw AiException('Geminiから画像データを取得できませんでした。');
  }
}
