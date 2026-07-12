import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n/strings.dart';

/// ⚙ 設定ダイアログ: 言語・AIプロバイダ・APIキー・並び替え・出力オプション
Future<void> showSettingsDialog(BuildContext context, AppState app) async {
  final s = app.settings;
  final geminiKeyController = TextEditingController(text: s.geminiApiKey);
  final geminiModelController = TextEditingController(text: s.geminiModel);
  final endpointController = TextEditingController(text: s.localLlmEndpoint);
  final localModelController = TextEditingController(text: s.localLlmModel);
  var language = s.language;
  var provider = s.aiProvider;
  var sortAxis = s.projectSortAxis;
  var numbering = s.exportHeadingNumbering;
  var tts = s.enableExportTts;
  var ttsSpeed = s.exportTtsSpeed;
  var optimize = s.enableExportOptimization;
  var jpegQuality = s.exportJpegQuality.toDouble();
  var maxDimension = s.exportMaxDimension;

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
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'None', label: Text(L.t('ai_none'))),
                    const ButtonSegment(value: 'Gemini', label: Text('Gemini')),
                    ButtonSegment(
                        value: 'LocalLLM',
                        label: Text(L.isJa ? 'ローカルLLM' : 'Local LLM')),
                  ],
                  selected: {provider},
                  onSelectionChanged: (v) =>
                      setState(() => provider = v.first),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: geminiKeyController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: L.t('gemini_api_key'),
                    helperText: L.t('gemini_api_key_enc_note'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
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
                const SizedBox(height: 12),
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
                const Divider(height: 32),
                Text(L.t('project_sort'),
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButton<String>(
                  value: sortAxis,
                  items: [
                    DropdownMenuItem(
                        value: 'LastModifiedAt', child: Text(L.t('sort_modified'))),
                    DropdownMenuItem(
                        value: 'CreatedAt', child: Text(L.t('sort_created'))),
                    DropdownMenuItem(value: 'Name', child: Text(L.t('sort_name'))),
                    DropdownMenuItem(value: 'Manual', child: Text(L.t('sort_manual'))),
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
                        onChanged: tts
                            ? (v) => setState(() => ttsSpeed = v)
                            : null,
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
