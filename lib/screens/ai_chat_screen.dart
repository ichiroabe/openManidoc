import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../app_state.dart';
import '../l10n/strings.dart';
import '../models/manidoc_project.dart';
import '../services/markdown_io.dart';
import 'editor_screen.dart';

/// AIエージェント(チャット)画面。本家StartViewのAIタブ相当:
/// - Web検索(Geminiのgrounding)トグル
/// - MDモード(マニュアル用Markdown形式での出力を促す)
/// - AIの回答をいつでも新規プロジェクトに取り込める
class AiChatScreen extends StatefulWidget {
  final AppState appState;

  const AiChatScreen({super.key, required this.appState});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<(String, String)> _history = []; // (role, content)
  bool _running = false;
  bool _webSearch = false;
  bool _mdMode = false;
  String? _lastAssistant; // 直近のAI回答(取り込み対象)
  String? _toolStatus; // MCPツール実行中の進捗表示

  AppState get app => widget.appState;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// マニュアル作成支援 + Markdown出力フォーマットのシステムプロンプト(本家準拠)
  String get _systemPrompt => L.isJa
      ? '【Web検索】\nWeb検索が有効な場合は最新情報を参照して回答してよい。'
          'ニュースや天気などマニュアル以外の質問にも答えてよい。\n\n'
          '【マニュアル出力フォーマット】ユーザーが「出力して」「作成して」「Markdownにして」等と'
          '言ったら、会話で整理した内容を次のMarkdownのみで返す(前後の説明・区切り線・```不要):\n'
          '# プロジェクト名(H1は1つだけ)\n概要\n\n## セクション名(必ずH2で区切る)\n本文\n\n'
          '### サブセクション\n本文\n\n> 補足コメント(引用はコメント欄として取り込まれる)\n\n'
          '見出しはH1→H2→H3の順。画像は含めない。'
      : '[Web Search]\nWhen web search is enabled, you may use up-to-date info to answer. '
          'You may also answer non-manual questions such as news or weather.\n\n'
          '[Manual output format] When the user says "export", "create", "make it Markdown" etc., '
          'return ONLY the following Markdown (no surrounding text, dividers, or ```):\n'
          '# Project name (only one H1)\nOverview\n\n## Section (always split with H2)\nBody\n\n'
          '### Subsection\nBody\n\n> Note (blockquotes are imported as comment boxes)\n\n'
          'Use headings H1 -> H2 -> H3. Do not include images.';

  /// MDモード時に各メッセージへ付ける追加指示(本家準拠)
  String get _mdInstruction => L.isJa
      ? '\n\n---\n上記を、次のMarkdown形式のみで出力してください(前後の説明や```は不要):\n'
          '# タイトル(1つだけ)\n概要\n\n## セクション名\n本文\n\n### サブセクション\n本文'
      : '\n\n---\nOutput the above as Markdown only (no extra text or ```):\n'
          '# Title (only one)\nOverview\n\n## Section\nBody\n\n### Subsection\nBody';

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _running) return;
    // 表示はユーザーの原文、APIにはMDモード指示を付ける
    final apiText = _mdMode ? '$text$_mdInstruction' : text;
    setState(() {
      _history.add(('user', apiText));
      _inputController.clear();
      _running = true;
    });
    _scrollToEnd();
    try {
      final reply = await app.ai.chat(
        _history,
        systemInstruction: _systemPrompt,
        useGrounding: _webSearch && app.ai.supportsWebSearch,
        onToolCall: (name) {
          if (mounted) setState(() => _toolStatus = name);
        },
      );
      setState(() {
        _history.add(('assistant', reply.trim()));
        _lastAssistant = reply.trim();
      });
    } catch (e) {
      setState(() => _history.add(('assistant', '⚠ $e')));
    } finally {
      setState(() {
        _running = false;
        _toolStatus = null;
      });
      _scrollToEnd();
    }
  }

  /// 検索ソース等の末尾を除き、コードブロックや本体を取り出す
  String _extractMarkdown(String text) {
    for (final marker in ['\n\n---\n**検索ソース:**', '\n\n---\n**Sources:**']) {
      final i = text.indexOf(marker);
      if (i >= 0) text = text.substring(0, i);
    }
    final code = RegExp(r'^```(?:markdown|md)?\r?\n([\s\S]*?)\r?\n```',
            multiLine: true)
        .firstMatch(text);
    if (code != null) return code.group(1)!.trim();
    return text.trim();
  }

  /// プロジェクト名を推定(H1→H2→先頭行)
  String _deriveName(String content) {
    final h1 = RegExp(r'^# (.+)$', multiLine: true).firstMatch(content);
    if (h1 != null) return h1.group(1)!.trim();
    final h2 = RegExp(r'^## (.+)$', multiLine: true).firstMatch(content);
    if (h2 != null) return h2.group(1)!.trim();
    final firstLine = content
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'^[#>\-*\s]+'), '').trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return L.isJa ? 'AIメモ' : 'AI note';
    return firstLine.length > 40 ? firstLine.substring(0, 40) : firstLine;
  }

  /// 直近のAI回答を新規プロジェクトとして取り込む
  Future<void> _importLatest() async {
    final raw = _lastAssistant;
    if (raw == null) return;
    if (app.workspace == null) {
      _snack(L.t('select_workspace_first'));
      return;
    }
    final content = _extractMarkdown(raw);
    // H1はプロジェクト名として使い本文から除く(H2がルートノードになる=本家準拠)
    final h1 = RegExp(r'^# (.+)$', multiLine: true).firstMatch(content);
    final name = h1 != null ? h1.group(1)!.trim() : _deriveName(content);
    final body = h1 != null
        ? content.replaceRange(h1.start, h1.end, '').trimLeft()
        : content;
    final project = MarkdownIo.importAsProject(name, body);
    // AI由来であることをタグで明示(検索での除外・一覧の識別に使える)
    if (project.tag.isEmpty) project.tag = L.t('ai_generated_tag');
    final saved = await app.addProject(project);
    if (!mounted) return;
    _snack(L.t('imported', [saved.name]));
    _openProject(saved);
  }

  void _openProject(ManidocProject project) {
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) => EditorScreen(appState: app, project: project)))
        .then((_) => app.refreshProjects());
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final config =
        isDark ? MarkdownConfig.darkConfig : MarkdownConfig.defaultConfig;
    final provider = app.settings.effectiveAIProvider;
    final canWebSearch = app.ai.supportsWebSearch;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(L.t('ai_agent_title')),
            const SizedBox(width: 12),
            Chip(
              label: Text(provider == 'None' ? L.t('ai_unset') : provider),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        actions: [
          // MDモード: マニュアル用Markdownでの出力を促す
          Tooltip(
            message: L.t('md_mode_tip'),
            child: Row(
              children: [
                Text(L.t('md_mode'), style: const TextStyle(fontSize: 13)),
                Switch(
                  value: _mdMode,
                  onChanged: (v) => setState(() => _mdMode = v),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Web検索トグル(Geminiのみ有効)
          Tooltip(
            message: canWebSearch
                ? L.t('web_search_tip')
                : L.t('web_search_gemini_only'),
            child: Row(
              children: [
                Icon(Icons.travel_explore,
                    size: 18,
                    color: _webSearch && canWebSearch
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline),
                const SizedBox(width: 4),
                Text(L.t('web_search'), style: const TextStyle(fontSize: 13)),
                Switch(
                  value: _webSearch && canWebSearch,
                  onChanged: canWebSearch
                      ? (v) => setState(() => _webSearch = v)
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _history.isEmpty
                ? Center(child: Text(L.t('ai_chat_empty')))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final (role, content) = _history[index];
                      final isUser = role == 'user';
                      // 表示用: MDモードで付けた指示は隠す
                      final shown = isUser
                          ? content.split('\n\n---\n').first
                          : content;
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.72),
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isUser
                                ? Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: isUser
                              ? Text(shown)
                              : MarkdownBlock(data: shown, config: config),
                        ),
                      );
                    },
                  ),
          ),
          if (_running) const LinearProgressIndicator(),
          // MCPツール実行中はツール名を表示(何をしているか見えるように)
          if (_running && _toolStatus != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '🔧 ${L.t('ai_tool_running', [_toolStatus!])}',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline),
              ),
            ),
          // AI回答があればいつでも「プロジェクトに取り込む」バナーを表示
          if (_lastAssistant != null && !_running)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.secondaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(L.t('ai_import_hint'))),
                  FilledButton.icon(
                    onPressed: _importLatest,
                    icon: const Icon(Icons.add),
                    label: Text(L.t('ai_create_project')),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    decoration: InputDecoration(
                      hintText: L.t('ai_message_hint'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _running ? null : _send,
                  icon: const Icon(Icons.send),
                  label: Text(L.t('send')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
