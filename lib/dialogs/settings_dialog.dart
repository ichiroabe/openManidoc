import 'dart:io';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n/strings.dart';

/// ⚙ 設定ダイアログ: 言語・AIプロバイダ（ChatGPT/Claude対応）・並び替え・出力オプション
Future<void> showSettingsDialog(BuildContext context, AppState app) async {
  final s = app.settings;
  final geminiKeyController = TextEditingController(text: s.geminiApiKey);
  final geminiModelController = TextEditingController(text: s.geminiModel);
  final openaiKeyController = TextEditingController(text: s.openaiApiKey);
  final openaiModelController = TextEditingController(text: s.openaiModel);
  final claudeKeyController = TextEditingController(text: s.claudeApiKey);
  final claudeModelController = TextEditingController(text: s.claudeModel);
  final endpointController = TextEditingController(text: s.localLlmEndpoint);
  final localModelController = TextEditingController(text: s.localLlmModel);

  const geminiModels = [
    'gemini-2.5-flash',
    'gemini-2.5-pro',
    'gemini-1.5-flash',
    'gemini-1.5-pro',
    'custom'
  ];
  const openaiModels = [
    'gpt-4o',
    'gpt-4o-mini',
    'gpt-4-turbo',
    'custom'
  ];
  const claudeModels = [
    'claude-sonnet-5',
    'claude-opus-4-8',
    'claude-haiku-4-5-20251001',
    'custom'
  ];

  var language = s.language;
  var provider = s.aiProvider;
  var sortAxis = s.projectSortAxis;
  var numbering = s.exportHeadingNumbering;
  var tts = s.enableExportTts;
  var ttsSpeed = s.exportTtsSpeed;
  var optimize = s.enableExportOptimization;
  var jpegQuality = s.exportJpegQuality.toDouble();
  var maxDimension = s.exportMaxDimension;

  var selectedGeminiModel =
      geminiModels.contains(s.geminiModel) ? s.geminiModel : 'custom';
  var selectedOpenaiModel =
      openaiModels.contains(s.openaiModel) ? s.openaiModel : 'custom';
  var selectedClaudeModel =
      claudeModels.contains(s.claudeModel) ? s.claudeModel : 'custom';

  void launchBrowser(String url) {
    if (Platform.isWindows) {
      Process.run('explorer.exe', [url]);
    }
  }

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(L.t('settings_title')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(L.t('language'),
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ja', label: Text('日本語')),
                    ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {language},
                  onSelectionChanged: (v) =>
                      setState(() => language = v.first),
                ),
                const Divider(height: 32),
                Text(L.t('ai_provider'),
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: provider,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(
                        value: 'None', child: Text(L.t('ai_none'))),
                    const DropdownMenuItem(
                        value: 'Gemini', child: Text('Gemini (Google)')),
                    const DropdownMenuItem(
                        value: 'ChatGPT', child: Text('ChatGPT (OpenAI)')),
                    const DropdownMenuItem(
                        value: 'Claude', child: Text('Claude (Anthropic)')),
                    DropdownMenuItem(
                        value: 'LocalLLM',
                        child: Text(L.isJa
                            ? 'ローカルLLM (Ollama/LM Studio等)'
                            : 'Local LLM (Ollama/LM Studio)')),
                  ],
                  onChanged: (v) => setState(() => provider = v!),
                ),
                const SizedBox(height: 16),

                // APIプロバイダに応じた設定項目の出し分け
                if (provider == 'Gemini') ...[
                  TextField(
                    controller: geminiKeyController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: L.t('gemini_api_key'),
                      helperText: L.t('gemini_api_key_enc_note'),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.open_in_new),
                        tooltip: L.isJa ? 'キーを取得する' : 'Get API Key',
                        onPressed: () =>
                            launchBrowser('https://aistudio.google.com/'),
                      ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(L.isJa ? 'モデル選択: ' : 'Model: '),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<String>(
                          value: selectedGeminiModel,
                          isExpanded: true,
                          items: geminiModels
                              .map((m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(m == 'custom'
                                        ? (L.isJa ? 'カスタム (手入力)' : 'Custom')
                                        : m),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() {
                            selectedGeminiModel = v!;
                            if (v != 'custom') {
                              geminiModelController.text = v;
                            }
                          }),
                        ),
                      ),
                    ],
                  ),
                  if (selectedGeminiModel == 'custom') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: geminiModelController,
                      decoration: InputDecoration(
                        labelText: L.t('gemini_model'),
                        hintText: 'gemini-2.5-flash',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ] else if (provider == 'ChatGPT') ...[
                  TextField(
                    controller: openaiKeyController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: L.isJa ? 'OpenAI APIキー' : 'OpenAI API Key',
                      helperText: L.t('gemini_api_key_enc_note'),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.open_in_new),
                        tooltip: L.isJa ? 'キーを取得する' : 'Get API Key',
                        onPressed: () => launchBrowser(
                            'https://platform.openai.com/api-keys'),
                      ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(L.isJa ? 'モデル選択: ' : 'Model: '),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<String>(
                          value: selectedOpenaiModel,
                          isExpanded: true,
                          items: openaiModels
                              .map((m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(m == 'custom'
                                        ? (L.isJa ? 'カスタム (手入力)' : 'Custom')
                                        : m),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() {
                            selectedOpenaiModel = v!;
                            if (v != 'custom') {
                              openaiModelController.text = v;
                            }
                          }),
                        ),
                      ),
                    ],
                  ),
                  if (selectedOpenaiModel == 'custom') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: openaiModelController,
                      decoration: InputDecoration(
                        labelText:
                            L.isJa ? 'OpenAI モデル名' : 'OpenAI Model Name',
                        hintText: 'gpt-4o',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ] else if (provider == 'Claude') ...[
                  TextField(
                    controller: claudeKeyController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: L.isJa ? 'Claude APIキー' : 'Claude API Key',
                      helperText: L.t('gemini_api_key_enc_note'),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.open_in_new),
                        tooltip: L.isJa ? 'キーを取得する' : 'Get API Key',
                        onPressed: () => launchBrowser(
                            'https://console.anthropic.com/settings/keys'),
                      ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(L.isJa ? 'モデル選択: ' : 'Model: '),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<String>(
                          value: selectedClaudeModel,
                          isExpanded: true,
                          items: claudeModels
                              .map((m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(m == 'custom'
                                        ? (L.isJa ? 'カスタム (手入力)' : 'Custom')
                                        : m),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() {
                            selectedClaudeModel = v!;
                            if (v != 'custom') {
                              claudeModelController.text = v;
                            }
                          }),
                        ),
                      ),
                    ],
                  ),
                  if (selectedClaudeModel == 'custom') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: claudeModelController,
                      decoration: InputDecoration(
                        labelText: L.isJa ? 'Claude モデル名' : 'Claude Model Name',
                        hintText: 'claude-3-5-sonnet-20241022',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ] else if (provider == 'LocalLLM') ...[
                  TextField(
                    controller: endpointController,
                    decoration: InputDecoration(
                      labelText: L.t('local_llm_endpoint'),
                      hintText: 'http://localhost:1234/v1',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: localModelController,
                    decoration: InputDecoration(
                      labelText: L.t('local_llm_model'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      L.isJa
                          ? 'AI機能はオフに設定されています。'
                          : 'AI features are turned off.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                ],

                const Divider(height: 32),
                Text(L.t('project_sort'),
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButton<String>(
                  value: sortAxis,
                  items: [
                    DropdownMenuItem(
                        value: 'LastModifiedAt',
                        child: Text(L.t('sort_modified'))),
                    DropdownMenuItem(
                        value: 'CreatedAt', child: Text(L.t('sort_created'))),
                    DropdownMenuItem(
                        value: 'Name', child: Text(L.t('sort_name'))),
                    DropdownMenuItem(
                        value: 'Manual', child: Text(L.t('sort_manual'))),
                  ],
                  onChanged: (v) => setState(() => sortAxis = v!),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(L.t('heading_numbering')),
                  value: numbering,
                  onChanged: (v) => setState(() => numbering = v ?? true),
                ),
                const Divider(height: 24),
                Text(L.t('tts_section'),
                    style: Theme.of(context).textTheme.titleSmall),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(L.t('tts_enable')),
                  value: tts,
                  onChanged: (v) => setState(() => tts = v ?? false),
                ),
                Row(
                  children: [
                    Text(L.t('speed')),
                    Expanded(
                      child: Slider(
                        value: ttsSpeed,
                        min: 0.5,
                        max: 2.0,
                        divisions: 15,
                        label: 'x${ttsSpeed.toStringAsFixed(1)}',
                        onChanged:
                            tts ? (v) => setState(() => ttsSpeed = v) : null,
                      ),
                    ),
                    Text('x${ttsSpeed.toStringAsFixed(1)}'),
                  ],
                ),
                const Divider(height: 24),
                Text(L.t('image_quality'),
                    style: Theme.of(context).textTheme.titleSmall),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(L.t('optimize_enable')),
                  value: optimize,
                  onChanged: (v) => setState(() => optimize = v ?? false),
                ),
                Row(
                  children: [
                    Text(L.t('jpeg_quality')),
                    Expanded(
                      child: Slider(
                        value: jpegQuality,
                        min: 40,
                        max: 100,
                        divisions: 12,
                        label: '${jpegQuality.round()}',
                        onChanged: optimize
                            ? (v) => setState(() => jpegQuality = v)
                            : null,
                      ),
                    ),
                    Text('${jpegQuality.round()}'),
                  ],
                ),
                Row(
                  children: [
                    Text(L.t('max_dimension')),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: maxDimension,
                      items: const [
                        DropdownMenuItem(value: 1280, child: Text('1280px')),
                        DropdownMenuItem(value: 1920, child: Text('1920px')),
                        DropdownMenuItem(value: 2560, child: Text('2560px')),
                      ],
                      onChanged: optimize
                          ? (v) => setState(() => maxDimension = v!)
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(L.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(L.t('save'))),
        ],
      ),
    ),
  );

  if (saved == true) {
    s
      ..language = language
      ..aiProvider = provider
      ..geminiApiKey = geminiKeyController.text.trim()
      ..geminiModel = geminiModelController.text.trim().isEmpty
          ? 'gemini-2.5-flash'
          : geminiModelController.text.trim()
      ..openaiApiKey = openaiKeyController.text.trim()
      ..openaiModel = openaiModelController.text.trim().isEmpty
          ? 'gpt-4o'
          : openaiModelController.text.trim()
      ..claudeApiKey = claudeKeyController.text.trim()
      ..claudeModel = claudeModelController.text.trim().isEmpty
          ? 'claude-3-5-sonnet-20241022'
          : claudeModelController.text.trim()
      ..localLlmEndpoint = endpointController.text.trim()
      ..localLlmModel = localModelController.text.trim()
      ..projectSortAxis = sortAxis
      ..exportHeadingNumbering = numbering
      ..enableExportTts = tts
      ..exportTtsSpeed = double.parse(ttsSpeed.toStringAsFixed(1))
      ..enableExportOptimization = optimize
      ..exportJpegQuality = jpegQuality.round()
      ..exportMaxDimension = maxDimension;
    await app.saveSettings();
  }
}
