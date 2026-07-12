import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n/strings.dart';

/// ✨ AIアシスタント。本家AIAssistantWindow準拠:
/// 指示入力+実行 → 左に元テキスト(読み取り専用)、右にAI結果(編集可)。
/// 「適用」で結果文字列を返す(キャンセルはnull)。
Future<String?> showAiAssistantDialog(
    BuildContext context, AppState app, String originalText) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _AiAssistantDialog(app: app, originalText: originalText),
  );
}

class _AiAssistantDialog extends StatefulWidget {
  final AppState app;
  final String originalText;

  const _AiAssistantDialog({required this.app, required this.originalText});

  @override
  State<_AiAssistantDialog> createState() => _AiAssistantDialogState();
}

class _AiAssistantDialogState extends State<_AiAssistantDialog> {
  final _promptController = TextEditingController();
  final _resultController = TextEditingController();
  late final _originalController =
      TextEditingController(text: widget.originalText);
  bool _running = false;
  String? _error;

  @override
  void dispose() {
    _promptController.dispose();
    _resultController.dispose();
    _originalController.dispose();
    super.dispose();
  }

  Future<void> _execute() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _running) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final hasText = widget.originalText.isNotEmpty;
      final userPrompt = L.isJa
          ? '${hasText ? '以下のテキストに対して指示を実行してください。\n\n--- テキスト ---\n${widget.originalText}\n--- ここまで ---\n\n' : ''}指示: $prompt'
          : '${hasText ? 'Apply the instruction to the following text.\n\n--- TEXT ---\n${widget.originalText}\n--- END ---\n\n' : ''}Instruction: $prompt';
      final result = await widget.app.ai.generateText(
        userPrompt,
        systemInstruction: L.isJa
            ? 'あなたは操作マニュアル作成を支援するアシスタントです。結果はMarkdown形式の本文のみを返し、前置きや説明は不要です。'
            : 'You assist with authoring manuals. Return only the Markdown body of the result, with no preamble or explanation.',
      );
      setState(() => _resultController.text = result.trim());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.app.settings.effectiveAIProvider;
    return Dialog(
      child: Container(
        width: 900,
        height: 620,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(L.t('ai_assistant'),
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 16),
                Chip(
                  label: Text(provider == 'None' ? L.t('ai_unset') : provider),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _promptController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: L.t('aia_prompt_hint'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _execute(),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _running ? null : _execute,
                    child: _running
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(L.t('run')),
                  ),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(L.t('original_text')),
                        const SizedBox(height: 4),
                        Expanded(
                          child: TextField(
                            controller: _originalController,
                            readOnly: true,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 13),
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              fillColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              filled: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(L.t('ai_result_editable')),
                        const SizedBox(height: 4),
                        Expanded(
                          child: TextField(
                            controller: _resultController,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 13),
                            decoration: const InputDecoration(
                                border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(L.t('cancel'))),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _resultController.text.isEmpty && _running
                      ? null
                      : () => Navigator.pop(context, _resultController.text),
                  child: Text(L.t('apply_this')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
