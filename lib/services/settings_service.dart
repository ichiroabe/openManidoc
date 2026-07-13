import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'crypto_service.dart';

/// アプリ全体設定。ChatGPT/ClaudeのAPIキーおよびモデル設定をサポート。
class AppSettings {
  String language; // "ja", "en"
  String aiProvider; // "Gemini", "ChatGPT", "Claude", "LocalLLM", "None"
  String geminiApiKey; // メモリ上は平文。保存時のみ暗号化される
  String geminiModel;
  String openaiApiKey; // 暗号化されて保存される
  String openaiModel;
  String claudeApiKey; // 暗号化されて保存される
  String claudeModel;
  String localLlmEndpoint;
  String localLlmModel; // 空ならmodelフィールドを送らない(LM Studio)
  String projectSortAxis; // "Manual", "LastModifiedAt", "CreatedAt", "Name"
  bool exportHeadingNumbering;
  bool enableExportTts;
  double exportTtsSpeed;
  bool enableExportOptimization;
  int exportJpegQuality;
  int exportMaxDimension;
  double articleFontSize;

  AppSettings({
    this.language = 'ja',
    this.aiProvider = 'None',
    this.geminiApiKey = '',
    this.geminiModel = 'gemini-2.5-flash',
    this.openaiApiKey = '',
    this.openaiModel = 'gpt-4o',
    this.claudeApiKey = '',
    this.claudeModel = 'claude-sonnet-5',
    this.localLlmEndpoint = 'http://localhost:1234/v1',
    this.localLlmModel = '',
    this.projectSortAxis = 'LastModifiedAt',
    this.exportHeadingNumbering = true,
    this.enableExportTts = false,
    this.exportTtsSpeed = 1.0,
    this.enableExportOptimization = false,
    this.exportJpegQuality = 80,
    this.exportMaxDimension = 1920,
    this.articleFontSize = 14.0,
  });

  bool get hasGeminiKey => geminiApiKey.isNotEmpty;
  bool get hasOpenaiKey => openaiApiKey.isNotEmpty;
  bool get hasClaudeKey => claudeApiKey.isNotEmpty;
  bool get hasLocalLlm => localLlmEndpoint.isNotEmpty;

  /// 実際に使えるプロバイダ("None"=AI無効)
  String get effectiveAIProvider {
    if (aiProvider == 'None') return 'None';
    if (aiProvider == 'LocalLLM' && hasLocalLlm) return 'LocalLLM';
    if (aiProvider == 'Gemini' && hasGeminiKey) return 'Gemini';
    if (aiProvider == 'ChatGPT' && hasOpenaiKey) return 'ChatGPT';
    if (aiProvider == 'Claude' && hasClaudeKey) return 'Claude';
    
    // フォールバック
    if (hasGeminiKey) return 'Gemini';
    if (hasOpenaiKey) return 'ChatGPT';
    if (hasClaudeKey) return 'Claude';
    if (hasLocalLlm) return 'LocalLLM';
    return 'None';
  }

  /// 暗号化キー(geminiApiKeyEnc)を優先。無ければ旧平文(geminiApiKey)から移行。
  static String _readGeminiKey(Map<String, dynamic> json) {
    final enc = json['geminiApiKeyEnc'] as String?;
    if (enc != null && enc.isNotEmpty) return CryptoService.decryptText(enc);
    return json['geminiApiKey'] as String? ?? '';
  }

  static String _readOpenaiKey(Map<String, dynamic> json) {
    final enc = json['openaiApiKeyEnc'] as String?;
    if (enc != null && enc.isNotEmpty) return CryptoService.decryptText(enc);
    return json['openaiApiKey'] as String? ?? '';
  }

  static String _readClaudeKey(Map<String, dynamic> json) {
    final enc = json['claudeApiKeyEnc'] as String?;
    if (enc != null && enc.isNotEmpty) return CryptoService.decryptText(enc);
    return json['claudeApiKey'] as String? ?? '';
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        language: json['language'] as String? ?? 'ja',
        aiProvider: json['aiProvider'] as String? ?? 'None',
        geminiApiKey: _readGeminiKey(json),
        geminiModel: json['geminiModel'] as String? ?? 'gemini-2.5-flash',
        openaiApiKey: _readOpenaiKey(json),
        openaiModel: json['openaiModel'] as String? ?? 'gpt-4o',
        claudeApiKey: _readClaudeKey(json),
        claudeModel: json['claudeModel'] as String? ?? 'claude-3-5-sonnet-20241022',
        localLlmEndpoint:
            json['localLlmEndpoint'] as String? ?? 'http://localhost:1234/v1',
        localLlmModel: json['localLlmModel'] as String? ?? '',
        projectSortAxis: json['projectSortAxis'] as String? ?? 'LastModifiedAt',
        exportHeadingNumbering: json['exportHeadingNumbering'] as bool? ?? true,
        enableExportTts: json['enableExportTts'] as bool? ?? false,
        exportTtsSpeed: (json['exportTtsSpeed'] as num?)?.toDouble() ?? 1.0,
        enableExportOptimization:
            json['enableExportOptimization'] as bool? ?? false,
        exportJpegQuality: (json['exportJpegQuality'] as num?)?.toInt() ?? 80,
        exportMaxDimension:
            (json['exportMaxDimension'] as num?)?.toInt() ?? 1920,
        articleFontSize:
            (json['articleFontSize'] as num?)?.toDouble() ?? 14.0,
      );

  Map<String, dynamic> toJson() => {
        'language': language,
        'aiProvider': aiProvider,
        'geminiApiKeyEnc': CryptoService.encryptText(geminiApiKey),
        'geminiModel': geminiModel,
        'openaiApiKeyEnc': CryptoService.encryptText(openaiApiKey),
        'openaiModel': openaiModel,
        'claudeApiKeyEnc': CryptoService.encryptText(claudeApiKey),
        'claudeModel': claudeModel,
        'localLlmEndpoint': localLlmEndpoint,
        'localLlmModel': localLlmModel,
        'projectSortAxis': projectSortAxis,
        'exportHeadingNumbering': exportHeadingNumbering,
        'enableExportTts': enableExportTts,
        'exportTtsSpeed': exportTtsSpeed,
        'enableExportOptimization': enableExportOptimization,
        'exportJpegQuality': exportJpegQuality,
        'exportMaxDimension': exportMaxDimension,
        'articleFontSize': articleFontSize,
      };

  static const _prefKey = 'appSettingsJson';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) return AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AppSettings();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(toJson()));
  }
}
