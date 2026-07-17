import 'dart:convert';
import 'dart:io';

import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';
import '../models/tag_definition.dart';

/// ワークスペース = プロジェクトJSONが並ぶフォルダ。
/// レイアウト（旧Manidoc互換）:
///   {workspace}/{projectId}.json      … プロジェクトデータ
///   {workspace}/{projectId}/images/   … 画像アセット
class WorkspaceService {
  final String workspacePath;

  WorkspaceService(this.workspacePath);

  static const _encoder = JsonEncoder.withIndent('  ');

  Directory get _dir => Directory(workspacePath);

  String projectFilePath(String projectId) =>
      '$workspacePath${Platform.pathSeparator}$projectId.json';

  String imagesDirPath(String projectId) =>
      '$workspacePath${Platform.pathSeparator}$projectId${Platform.pathSeparator}images';

  /// ワークスペース設定(タグ定義など)。旧Manidoc互換。
  String get _settingsPath =>
      '$workspacePath${Platform.pathSeparator}workspace.settings.json';

  /// workspace.settings.json の tags[] を読む
  Future<List<TagDefinition>> loadTags() async {
    final file = File(_settingsPath);
    if (!await file.exists()) return [];
    try {
      final json = jsonDecode(await file.readAsString());
      final tags = json['tags'] as List<dynamic>? ?? [];
      return tags
          .map((e) => TagDefinition.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// tags[] を保存(他のキーは保持する)
  Future<void> saveTags(List<TagDefinition> tags) async {
    final file = File(_settingsPath);
    Map<String, dynamic> json = {};
    if (await file.exists()) {
      try {
        final parsed = jsonDecode(await file.readAsString());
        if (parsed is Map<String, dynamic>) json = parsed;
      } catch (_) {}
    }
    json['tags'] = tags.map((t) => t.toJson()).toList();
    await file.writeAsString(_encoder.convert(json));
  }

  /// テーマCSSは {workspace}/themes/*.css に置く
  String get themesDirPath =>
      '$workspacePath${Platform.pathSeparator}themes';

  /// themes フォルダ内の *.css ファイル名一覧
  Future<List<String>> listThemeCssFiles() async {
    final dir = Directory(themesDirPath);
    if (!await dir.exists()) return [];
    final files = <String>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.css')) {
        files.add(entity.uri.pathSegments.last);
      }
    }
    files.sort();
    return files;
  }

  /// テーマCSSファイルの中身を読む(未指定・不在ならnull)
  Future<String?> readThemeCss(String fileName) async {
    if (fileName.isEmpty) return null;
    final file = File('$themesDirPath${Platform.pathSeparator}$fileName');
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  /// テーマCSSを保存し、ファイル名を返す(同名は上書き=編集)
  Future<String> saveThemeCss(String name, String css) async {
    final dir = Directory(themesDirPath);
    await dir.create(recursive: true);
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final fileName = safe.toLowerCase().endsWith('.css') ? safe : '$safe.css';
    await File('${dir.path}${Platform.pathSeparator}$fileName')
        .writeAsString(css);
    return fileName;
  }

  /// テーマCSSファイルを削除する(存在しなければ何もしない)
  Future<void> deleteThemeCss(String fileName) async {
    if (fileName.isEmpty) return;
    final file = File('$themesDirPath${Platform.pathSeparator}$fileName');
    if (await file.exists()) await file.delete();
  }

  /// ワークスペース内の全プロジェクトを読み込む（壊れたJSONはスキップ）
  Future<List<ManidocProject>> loadProjects() async {
    if (!await _dir.exists()) return [];
    final projects = <ManidocProject>[];
    await for (final entity in _dir.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      try {
        final json = jsonDecode(await entity.readAsString());
        if (json is Map<String, dynamic> && json.containsKey('rootNodes')) {
          projects.add(ManidocProject.fromJson(json));
        }
      } catch (_) {
        // プロジェクト以外のJSONや破損ファイルは無視
      }
    }
    projects.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return projects;
  }

  Future<void> saveProject(ManidocProject project) async {
    project.lastModifiedAt = DateTime.now();
    final file = File(projectFilePath(project.id));
    await file.parent.create(recursive: true);
    await file.writeAsString(_encoder.convert(project.toJson()));
  }

  Future<void> deleteProject(ManidocProject project) async {
    final file = File(projectFilePath(project.id));
    if (await file.exists()) await file.delete();
    final assetDir =
        Directory('$workspacePath${Platform.pathSeparator}${project.id}');
    if (await assetDir.exists()) await assetDir.delete(recursive: true);
  }

  /// 画像ファイルをプロジェクトのimagesフォルダへコピーし、相対パスを返す
  Future<String> importImage(String projectId, String sourcePath) async {
    final imagesDir = Directory(imagesDirPath(projectId));
    await imagesDir.create(recursive: true);
    final ext = sourcePath.contains('.')
        ? sourcePath.substring(sourcePath.lastIndexOf('.'))
        : '.png';
    final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}$ext';
    await File(sourcePath)
        .copy('${imagesDir.path}${Platform.pathSeparator}$fileName');
    return 'images/$fileName';
  }

  /// 画像バイト列(AI生成等)をimagesフォルダへ保存し、相対パスを返す
  Future<String> importImageBytes(String projectId, List<int> bytes,
      {String ext = '.png'}) async {
    final imagesDir = Directory(imagesDirPath(projectId));
    await imagesDir.create(recursive: true);
    final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}$ext';
    await File('${imagesDir.path}${Platform.pathSeparator}$fileName')
        .writeAsBytes(bytes);
    return 'images/$fileName';
  }

  /// スマート画像管理: どのノードからも参照されていない画像を削除し、削除数を返す
  Future<int> cleanupUnusedImages(ManidocProject project) async {
    final imagesDir = Directory(imagesDirPath(project.id));
    if (!await imagesDir.exists()) return 0;
    final referenced = <String>{};
    void walk(List<ManidocNode> nodes) {
      for (final node in nodes) {
        if (node.imagePath.isNotEmpty) {
          referenced.add(node.imagePath.split('/').last);
        }
        for (final text in [node.article, node.comment]) {
          for (final m
              in RegExp(r'images/([^)\s"]+)').allMatches(text)) {
            referenced.add(m.group(1)!);
          }
        }
        walk(node.children);
      }
    }

    walk(project.rootNodes);
    var deleted = 0;
    await for (final entity in imagesDir.list()) {
      if (entity is File &&
          !referenced.contains(entity.uri.pathSegments.last)) {
        await entity.delete();
        deleted++;
      }
    }
    return deleted;
  }

  /// 1プロジェクトをディスクから読み直す
  Future<ManidocProject?> loadProjectById(String projectId) async {
    final file = File(projectFilePath(projectId));
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      return ManidocProject.fromJson(json as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// ノードの imagePath（相対）を絶対パスへ解決
  String resolveImagePath(String projectId, String relativePath) {
    final normalized = relativePath.replaceAll('/', Platform.pathSeparator);
    return '$workspacePath${Platform.pathSeparator}$projectId${Platform.pathSeparator}$normalized';
  }
}
