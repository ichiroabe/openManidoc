import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// ローカルMCP(Model Context Protocol)対応。
///
/// 設計方針(2026-07-18確定):
/// - MCPツール実行は **ローカルLLM専用**。ツール結果(記事本文などのローカルデータ)が
///   クラウドLLMへ送信されるのを防ぐため、Gemini等のクラウド経路には接続しない。
/// - 設定ファイルは Claude Desktop 互換形式の mcp_servers.json
///   (アプリ設定フォルダ = shared_preferences.json と同じ場所)。
/// - 同一サーバーをワークスペース違いで複数登録でき、ツール名は
///   「サーバー名__ツール名」で名前空間分離する(AIのワークスペース横断検索を実現)。
/// - サーバー定義の allowedTools(独自拡張)で公開ツールを絞れる。
///   雛形では読み取り系のみを許可し、書き込みは既存の取込UI(人間の承認)経由とする。

/// ツール名の名前空間区切り(OpenAI/Ollamaのツール名規則 [a-zA-Z0-9_-] に適合)
const mcpNsSep = '__';

/// 「サーバー名__ツール名」を (サーバー名, ツール名) に分解。形式不正ならnull。
(String, String)? mcpSplitToolName(String namespaced) {
  final idx = namespaced.indexOf(mcpNsSep);
  if (idx <= 0 || idx + mcpNsSep.length >= namespaced.length) return null;
  return (
    namespaced.substring(0, idx),
    namespaced.substring(idx + mcpNsSep.length)
  );
}

/// mcp_servers.json の1サーバー定義(Claude Desktop互換+allowedTools拡張)
class McpServerConfig {
  final String name;
  final String command;
  final List<String> args;
  final Map<String, String> env;

  /// LLMに公開するツール名の許可リスト。nullなら全ツール公開。
  final List<String>? allowedTools;

  McpServerConfig({
    required this.name,
    required this.command,
    this.args = const [],
    this.env = const {},
    this.allowedTools,
  });
}

/// mcp_servers.json の読み書き・検証・雛形
class McpConfig {
  static const fileName = 'mcp_servers.json';

  /// テスト用にパスを差し替え可能
  static String? configPathOverride;

  /// 初回用の雛形(読み取り専用ツールのみ許可する例)
  static const template = '''
{
  "mcpServers": {
    "manidoc": {
      "command": "dotnet",
      "args": ["C:\\\\path\\\\to\\\\ManidocMCP.dll"],
      "env": { "MANIDOC_WORKSPACE": "C:\\\\path\\\\to\\\\workspace" },
      "allowedTools": [
        "list_projects", "list_nodes", "get_article",
        "get_article_by_title", "search_fulltext"
      ]
    }
  }
}
''';

  static Future<String> configPath() async {
    if (configPathOverride != null) return configPathOverride!;
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}${Platform.pathSeparator}$fileName';
  }

  /// 設定ファイルの生テキストを読む。無ければnull。
  static Future<String?> readRaw() async {
    final file = File(await configPath());
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  static Future<void> writeRaw(String raw) async {
    final file = File(await configPath());
    await file.parent.create(recursive: true);
    await file.writeAsString(raw);
  }

  /// 構文・構造チェック。問題なければnull、あればエラーメッセージを返す。
  static String? validate(String raw) {
    try {
      parse(raw);
      return null;
    } catch (e) {
      return e.toString().replaceFirst('FormatException: ', '');
    }
  }

  /// 生テキストからサーバー定義一覧を得る。不正ならFormatException。
  static List<McpServerConfig> parse(String raw) {
    final dynamic root;
    try {
      root = jsonDecode(raw);
    } on FormatException catch (e) {
      throw FormatException('JSON構文エラー: ${e.message}');
    }
    if (root is! Map<String, dynamic>) {
      throw const FormatException('ルートはオブジェクトである必要があります');
    }
    final servers = root['mcpServers'];
    if (servers == null) {
      throw const FormatException('"mcpServers" キーがありません');
    }
    if (servers is! Map<String, dynamic>) {
      throw const FormatException('"mcpServers" はオブジェクトである必要があります');
    }
    final result = <McpServerConfig>[];
    for (final entry in servers.entries) {
      final name = entry.key;
      if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name)) {
        throw FormatException(
            'サーバー名 "$name" は半角英数字・ハイフン・アンダースコアのみ使用できます'
            '(ツール名の一部になるため)');
      }
      final cfg = entry.value;
      if (cfg is! Map<String, dynamic>) {
        throw FormatException('サーバー "$name" の定義はオブジェクトである必要があります');
      }
      final command = cfg['command'];
      if (command is! String || command.isEmpty) {
        throw FormatException('サーバー "$name" に "command" がありません');
      }
      final args = cfg['args'];
      if (args != null && args is! List) {
        throw FormatException('サーバー "$name" の "args" は配列である必要があります');
      }
      final env = cfg['env'];
      if (env != null && env is! Map) {
        throw FormatException('サーバー "$name" の "env" はオブジェクトである必要があります');
      }
      final allowed = cfg['allowedTools'];
      if (allowed != null && allowed is! List) {
        throw FormatException(
            'サーバー "$name" の "allowedTools" は配列である必要があります');
      }
      result.add(McpServerConfig(
        name: name,
        command: command,
        args: (args as List?)?.map((e) => e.toString()).toList() ?? const [],
        env: (env as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
            const {},
        allowedTools:
            (allowed as List?)?.map((e) => e.toString()).toList(),
      ));
    }
    return result;
  }
}

/// 1つのMCPサーバー(stdioサブプロセス)とのJSON-RPC通信
class McpClient {
  final McpServerConfig config;
  McpClient(this.config);

  late Process _proc;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int _nextId = 1;
  final _stderrBuf = StringBuffer();

  Future<void> start() async {
    _proc = await Process.start(config.command, config.args,
        environment: config.env, runInShell: false);
    _proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine);
    _proc.stderr.transform(utf8.decoder).listen((s) {
      // 溜めすぎ防止(エラー診断用に末尾だけあれば十分)
      if (_stderrBuf.length < 8000) _stderrBuf.write(s);
    });
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return; // MCP以外のログ行は無視
    }
    final id = msg['id'];
    if (id is int && _pending.containsKey(id)) {
      _pending.remove(id)!.complete(msg);
    }
  }

  Future<Map<String, dynamic>> _request(String method,
      [Map<String, dynamic>? params]) async {
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _send({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': ?params
    });
    final msg = await completer.future.timeout(const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException(
            'MCPサーバー ${config.name} が応答しません($method)。'
            '\nstderr: ${_stderrBuf.toString().trim()}'));
    if (msg.containsKey('error')) {
      throw Exception(
          'MCPエラー(${config.name}/$method): ${jsonEncode(msg['error'])}');
    }
    return (msg['result'] as Map<String, dynamic>?) ?? {};
  }

  void _notify(String method) => _send({'jsonrpc': '2.0', 'method': method});

  void _send(Map<String, dynamic> msg) => _proc.stdin.writeln(jsonEncode(msg));

  /// initialize→tools/list。ツール定義(name/description/inputSchema)を返す。
  Future<List<Map<String, dynamic>>> initializeAndListTools() async {
    await _request('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': {},
      'clientInfo': {'name': 'openManidoc', 'version': '1.0'},
    });
    _notify('notifications/initialized');
    final res = await _request('tools/list');
    return (res['tools'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  /// tools/call を実行し、content内のtextを連結して返す
  Future<String> callTool(String name, Map<String, dynamic> args) async {
    final res =
        await _request('tools/call', {'name': name, 'arguments': args});
    final content = (res['content'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'] as String? ?? '')
        .join('\n');
    if (res['isError'] == true) return '[ツールエラー] $content';
    return content;
  }

  void dispose() {
    try {
      _proc.kill();
    } catch (_) {}
  }
}

/// 複数MCPサーバーの束ね役(アプリ全体で1つ)。
/// 設定変更後は stopAll() を呼べば、次回利用時に新しい設定で再起動される。
class McpRegistry {
  McpRegistry._();
  static final McpRegistry instance = McpRegistry._();

  final _clients = <String, McpClient>{};
  List<Map<String, dynamic>> _tools = [];
  bool _started = false;

  /// 起動に失敗したサーバーの警告(チャット画面等で表示できる)
  final startupWarnings = <String>[];

  /// 名前空間付きツール一覧(未起動なら設定を読んで全サーバーを起動する)。
  /// 設定ファイルが無い/空の場合は空リストを返す(エラーにしない)。
  Future<List<Map<String, dynamic>>> ensureStarted() async {
    if (_started) return _tools;
    startupWarnings.clear();
    final tools = <Map<String, dynamic>>[];
    final raw = await McpConfig.readRaw();
    if (raw != null && raw.trim().isNotEmpty) {
      final List<McpServerConfig> configs;
      try {
        configs = McpConfig.parse(raw);
      } catch (e) {
        startupWarnings.add('mcp_servers.json が不正です: $e');
        _tools = [];
        _started = true;
        return _tools;
      }
      for (final cfg in configs) {
        try {
          final client = McpClient(cfg);
          await client.start();
          final serverTools = await client.initializeAndListTools();
          _clients[cfg.name] = client;
          final exposed = cfg.allowedTools == null
              ? serverTools
              : serverTools
                  .where((t) => cfg.allowedTools!.contains(t['name']))
                  .toList();
          for (final t in exposed) {
            tools.add({
              ...t,
              'name': '${cfg.name}$mcpNsSep${t['name']}',
              'description':
                  '[${cfg.name}] ${t['description'] ?? ''}',
            });
          }
        } catch (e) {
          startupWarnings.add('MCPサーバー "${cfg.name}" の起動に失敗: $e');
        }
      }
    }
    _tools = tools;
    _started = true;
    return _tools;
  }

  /// 名前空間付きツール名を解決して実行
  Future<String> callTool(
      String namespacedName, Map<String, dynamic> args) async {
    final split = mcpSplitToolName(namespacedName);
    if (split == null) {
      return '[エラー] 不正なツール名です: $namespacedName';
    }
    final (server, tool) = split;
    final client = _clients[server];
    if (client == null) return '[エラー] 未知のMCPサーバーです: $server';
    // 許可リスト外のツールを(LLMが名前を推測して)呼ぼうとした場合は拒否
    final allowed = client.config.allowedTools;
    if (allowed != null && !allowed.contains(tool)) {
      return '[拒否] ツール "$tool" は許可されていません(allowedTools参照)';
    }
    try {
      return await client.callTool(tool, args);
    } catch (e) {
      return '[ツール実行エラー] $e';
    }
  }

  /// 全サーバー停止。次回 ensureStarted() で設定を読み直して再起動する。
  void stopAll() {
    for (final c in _clients.values) {
      c.dispose();
    }
    _clients.clear();
    _tools = [];
    _started = false;
  }
}
