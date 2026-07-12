import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'crypto_service.dart';

/// アプリ全体設定。旧ManidocのAppSettingsに準拠。
class AppSettings {
  String language; // "ja", "en"
  String aiProvider; // "Gemini", "LocalLLM", "None"
  String geminiApiKey; // メモリ上は平文。保存時のみ暗号化される
  String geminiModel;
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
  bool get hasLocalLlm => localLlmEndpoint.isNotEmpty;

  /// 実際に使えるプロバイダ("None"=AI無効)
  String get effectiveAIProvider {
    if (aiProvider == 'None') return 'None';
    if (aiProvider == 'LocalLLM' && hasLocalLlm) return 'LocalLLM';
    if (aiProvider == 'Gemini' && hasGeminiKey) return 'Gemini';
    if (hasGeminiKey) return 'Gemini';
    if (hasLocalLlm) return 'LocalLLM';
    return 'None';
  }

  /// 暗号化キー(geminiApiKeyEnc)を優先。無ければ旧平文(geminiApiKey)から移行。
  static String _readGeminiKey(Map<String, dynamic> json) {
    final enc = json['geminiApiKeyEnc'] as String?;
    if (enc != null && enc.isNotEmpty) return CryptoService.decryptText(enc);
    return json['geminiApiKey'] as String? ?? '';
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        language: json['language'] as String? ?? 'ja',
        aiProvider: json['aiProvider'] as String? ?? 'None',
        geminiApiKey: _readGeminiKey(json),
        geminiModel: json['geminiModel'] as String? ?? 'gemini-2.5-flash',
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
        // 平文は保存せず、暗号化した値のみ保存する
        'geminiApiKeyEnc': CryptoService.encryptText(geminiApiKey),
        'geminiModel': geminiModel,
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
