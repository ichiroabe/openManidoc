import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'mcp_service.dart';
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
  /// [onToolCall] はローカルMCPのツール実行時に呼ばれる進捗通知(LocalLLMのみ)。
  Future<String> chat(List<(String, String)> history,
      {String? systemInstruction,
      bool useGrounding = false,
      void Function(String toolName)? onToolCall}) async {
    switch (settings.effectiveAIProvider) {
      case 'Gemini':
        return _geminiChat(history, systemInstruction, useGrounding);
      case 'ChatGPT':
        return _chatgptChat(history, systemInstruction);
      case 'Claude':
        return _claudeChat(history, systemInstruction);
      case 'LocalLLM':
        // ローカルLLMはWeb検索非対応。MCPツールはローカルLLM専用
        // (ローカルデータをクラウドへ送らないための設計方針)。
        return _localLlmChat(history, systemInstruction, onToolCall);
      default:
        throw AiException('AIプロバイダが未設定です。「⚙ 設定」からAPIキー'
            'またはローカルLLMのエンドポイントを設定してください。');
    }
  }

  /// ローカルMCPが有効か(プロバイダがLocalLLMかつ設定ON)
  bool get mcpEnabled =>
      settings.effectiveAIProvider == 'LocalLLM' && settings.useLocalMcp;

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
      'model':
          settings.claudeModel.isEmpty ? 'claude-sonnet-5' : settings.claudeModel,
      'max_tokens': 4000,
      'system': ?systemInstruction,
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

  // ローカルLLM: 初回はモデルロードで数分待たされることがあるため長めに取る
  static const _localTimeout = Duration(minutes: 10);
  static const _mcpMaxLoops = 8; // ツール呼び出しの最大ラウンド数
  static const _mcpResultCap = 6000; // ツール結果をLLMへ渡す際の上限文字数

  static const _listModelsTimeout = Duration(seconds: 10);

  /// ローカルLLMサーバーが持っているモデル名の一覧を取得する。
  /// OpenAI互換の `{endpoint}/models` を先に試し、返らなければ
  /// Ollamaのタグ一覧 `{host}/api/tags` にフォールバックする。
  static Future<List<String>> listLocalModels(String endpoint) async {
    final base = endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      throw AiException('エンドポイントURLを入力してください。');
    }
    final names = <String>[];
    Object? lastError;

    // 1) OpenAI互換 (LM Studio / Ollamaの/v1) : data[].id
    try {
      final response =
          await http.get(Uri.parse('$base/models')).timeout(_listModelsTimeout);
      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        final data = json is Map<String, dynamic> ? json['data'] : null;
        if (data is List) {
          for (final item in data) {
            final id = item is Map<String, dynamic> ? item['id'] : null;
            if (id is String && id.isNotEmpty) names.add(id);
          }
        }
      } else {
        lastError = 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      lastError = e;
    }

    // 2) Ollamaのタグ一覧 : models[].name (エンドポイント末尾の/v1は落とす)
    if (names.isEmpty) {
      final host = base.replaceAll(RegExp(r'/v\d+$'), '');
      try {
        final response = await http
            .get(Uri.parse('$host/api/tags'))
            .timeout(_listModelsTimeout);
        if (response.statusCode == 200) {
          final json = jsonDecode(utf8.decode(response.bodyBytes));
          final models = json is Map<String, dynamic> ? json['models'] : null;
          if (models is List) {
            for (final item in models) {
              final name = item is Map<String, dynamic> ? item['name'] : null;
              if (name is String && name.isNotEmpty) names.add(name);
            }
          }
        } else {
          lastError = 'HTTP ${response.statusCode}';
        }
      } catch (e) {
        lastError = e;
      }
    }

    if (names.isEmpty) {
      throw AiException('モデル一覧を取得できませんでした。'
          'LM Studio / Ollama が起動しているか、エンドポイントURL($base)が'
          '正しいか確認してください。${lastError == null ? '' : '\n$lastError'}');
    }
    names.sort();
    return names;
  }

  /// OpenAI互換 /chat/completions への1リクエスト(生のレスポンスJSONを返す)
  Future<Map<String, dynamic>> _localLlmRequest(
      List<Map<String, dynamic>> messages,
      {List<Map<String, dynamic>>? tools}) async {
    final url = Uri.parse(
        '${settings.localLlmEndpoint.replaceAll(RegExp(r'/+$'), '')}/chat/completions');
    final body = <String, dynamic>{
      // Ollama等はmodel必須。空ならLM Studioがロード中モデルを自動使用。
      if (settings.localLlmModel.isNotEmpty) 'model': settings.localLlmModel,
      'messages': messages,
      if (tools != null && tools.isNotEmpty) 'tools': tools,
      'stream': false,
    };
    final http.Response response;
    try {
      response = await http
          .post(url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(_localTimeout);
    } catch (e) {
      throw AiException('ローカルLLMに接続できませんでした。'
          'LM Studio / Ollama が起動しているか、エンドポイントURL'
          '(${settings.localLlmEndpoint})が正しいか確認してください。\n$e');
    }
    if (response.statusCode != 200) {
      final bodyText = utf8.decode(response.bodyBytes);
      // tools非対応モデル: エラーで落とさず設定変更を案内する
      if (tools != null && bodyText.contains('does not support tools')) {
        throw AiException(
            'このモデル(${settings.localLlmModel})はツール呼び出し(tools)に'
            '対応していないようです。「⚙ 設定」でローカルMCPをOFFにするか、'
            '対応モデル(gemma4 / qwen3 / llama3.1 等)に切り替えてください。');
      }
      throw AiException('ローカルLLMエラー(${response.statusCode})\n$bodyText');
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<String> _localLlmChat(List<(String, String)> history,
      String? systemInstruction,
      [void Function(String toolName)? onToolCall]) async {
    // ローカルMCP有効時はツールループ経路へ
    if (settings.useLocalMcp) {
      final tools = await McpRegistry.instance.ensureStarted();
      if (tools.isNotEmpty) {
        return _localLlmToolLoop(
            history, systemInstruction, tools, onToolCall);
      }
    }
    final json = await _localLlmRequest([
      if (systemInstruction != null)
        {'role': 'system', 'content': systemInstruction},
      for (final (role, content) in history)
        {'role': role, 'content': content},
    ]);
    final text = json['choices']?[0]?['message']?['content'] as String?;
    if (text == null || text.isEmpty) {
      throw AiException('ローカルLLMからレスポンスを取得できませんでした。');
    }
    return text;
  }

  static String _capResult(String s) => s.length <= _mcpResultCap
      ? s
      : '${s.substring(0, _mcpResultCap)}\n…(${s.length}文字中$_mcpResultCap文字で打ち切り)';

  /// MCPツール付きのエージェントループ(ネイティブtool calling)。
  /// tool_callsが返る限りMCPを実行して結果を戻し、最終テキストを返す。
  Future<String> _localLlmToolLoop(
      List<(String, String)> history,
      String? systemInstruction,
      List<Map<String, dynamic>> mcpTools,
      void Function(String toolName)? onToolCall) async {
    final openAiTools = mcpTools
        .map((t) => {
              'type': 'function',
              'function': {
                'name': t['name'],
                'description': t['description'] ?? '',
                'parameters':
                    t['inputSchema'] ?? {'type': 'object', 'properties': {}},
              }
            })
        .toList();

    final mcpInstruction = 'ツールが利用できる。ツール名は「サーバー名__ツール名」形式。'
        '必要に応じてツールを呼び出してタスクを完了すること。'
        '途中でユーザーに確認を求めず、最後まで完了してから回答すること。';
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': systemInstruction == null
            ? mcpInstruction
            : '$systemInstruction\n\n$mcpInstruction',
      },
      for (final (role, content) in history)
        {'role': role, 'content': content},
    ];

    final usedTools = <String>[];
    for (var i = 0; i < _mcpMaxLoops; i++) {
      final res =
          await _localLlmRequest(messages, tools: openAiTools);
      final msg = res['choices']?[0]?['message'] as Map<String, dynamic>?;
      if (msg == null) {
        throw AiException('ローカルLLMからレスポンスを取得できませんでした。');
      }
      final toolCalls =
          (msg['tool_calls'] as List?)?.cast<Map<String, dynamic>>();

      if (toolCalls == null || toolCalls.isEmpty) {
        final text = msg['content'] as String? ?? '';
        if (text.isEmpty) {
          throw AiException('ローカルLLMからレスポンスを取得できませんでした。');
        }
        if (usedTools.isEmpty) return text;
        // 透明性のため使用ツールを末尾に記す
        return '$text\n\n---\n🔧 MCP: ${usedTools.toSet().join(', ')}';
      }

      messages.add(msg); // assistantのtool_callsメッセージをそのまま履歴へ
      for (final tc in toolCalls) {
        final fn = tc['function'] as Map<String, dynamic>? ?? {};
        final name = fn['name'] as String? ?? '';
        final argsRaw = fn['arguments'];
        Map<String, dynamic> args;
        try {
          args = argsRaw is String
              ? (argsRaw.trim().isEmpty
                  ? <String, dynamic>{}
                  : jsonDecode(argsRaw) as Map<String, dynamic>)
              : Map<String, dynamic>.from(argsRaw as Map? ?? {});
        } catch (_) {
          args = {};
        }
        usedTools.add(name);
        onToolCall?.call(name);
        final result = await McpRegistry.instance.callTool(name, args);
        messages.add({
          'role': 'tool',
          'tool_call_id': tc['id'] ?? name,
          'content': _capResult(result),
        });
      }
    }
    // ループ上限: ツール無しで最終回答だけさせる
    messages.add({
      'role': 'user',
      'content': 'ツール呼び出しの上限に達しました。ここまでの結果で回答をまとめてください。',
    });
    final res = await _localLlmRequest(messages);
    final text = res['choices']?[0]?['message']?['content'] as String? ?? '';
    return '$text\n\n---\n🔧 MCP: ${usedTools.toSet().join(', ')}';
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
