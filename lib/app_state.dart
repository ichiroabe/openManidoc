import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/strings.dart';
import 'models/manidoc_project.dart';
import 'models/tag_definition.dart';
import 'services/ai_service.dart';
import 'services/backup_service.dart';
import 'services/settings_service.dart';
import 'services/workspace_service.dart';

/// アプリ全体の状態(ワークスペース・プロジェクト一覧・テーマ・設定)
class AppState extends ChangeNotifier {
  static const _prefWorkspace = 'workspacePath';
  static const _prefDarkMode = 'darkMode';

  WorkspaceService? workspace;
  List<ManidocProject> projects = [];
  List<TagDefinition> workspaceTags = []; // workspace.settings.json のタグ定義
  ThemeMode themeMode = ThemeMode.light;
  bool loading = false;
  AppSettings settings = AppSettings();

  AiService get ai => AiService(settings);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode =
        (prefs.getBool(_prefDarkMode) ?? false) ? ThemeMode.dark : ThemeMode.light;
    settings = await AppSettings.load();
    L.lang = settings.language;
    final path = prefs.getString(_prefWorkspace);
    if (path != null && path.isNotEmpty) {
      workspace = WorkspaceService(path);
      await refreshProjects();
    }
    notifyListeners();
  }

  Future<void> saveSettings() async {
    L.lang = settings.language;
    await settings.save();
    _sortProjects();
    notifyListeners();
  }

  /// タグ候補: workspace.settings.json の定義タグ + 実際に使われているタグ
  List<String> get allTags {
    final names = <String>{
      for (final t in workspaceTags) t.name,
      for (final p in projects)
        if (p.tag.isNotEmpty) p.tag,
    }..removeWhere((n) => n.isEmpty);
    final list = names.toList()..sort();
    return list;
  }

  /// タグ名 → 画像パス(定義がなければnull)
  String? tagImage(String tagName) {
    for (final t in workspaceTags) {
      if (t.name == tagName && t.imagePath.isNotEmpty) return t.imagePath;
    }
    return null;
  }

  Future<void> setProjectTag(ManidocProject project, String tag) async {
    project.tag = tag;
    // 未定義タグなら定義にも追加する
    if (tag.isNotEmpty && !workspaceTags.any((t) => t.name == tag)) {
      workspaceTags.add(TagDefinition(name: tag));
      await workspace!.saveTags(workspaceTags);
    }
    await workspace!.saveProject(project);
    await refreshProjects();
  }

  /// 複数プロジェクトのタグをまとめて更新する（タグ管理の「一括タグ設定」タブ用）。
  /// tag が空文字ならタグを外す。setProjectTag と違い、定義追加と再読込は1回にまとめる。
  Future<void> setProjectsTag(List<ManidocProject> targets, String tag) async {
    if (targets.isEmpty) return;
    // 未定義タグなら定義に一度だけ追加する
    if (tag.isNotEmpty && !workspaceTags.any((t) => t.name == tag)) {
      workspaceTags.add(TagDefinition(name: tag));
      await workspace!.saveTags(workspaceTags);
    }
    for (final p in targets) {
      p.tag = tag;
      await workspace!.saveProject(p);
    }
    await refreshProjects();
  }

  /// タグ管理画面からの一括保存
  Future<void> saveWorkspaceTags(List<TagDefinition> tags) async {
    workspaceTags = tags;
    await workspace!.saveTags(workspaceTags);
    notifyListeners();
  }

  Future<void> setWorkspace(String path) async {
    workspace = WorkspaceService(path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefWorkspace, path);
    await refreshProjects();
  }

  void _sortProjects() {
    switch (settings.projectSortAxis) {
      case 'Name':
        projects.sort((a, b) => a.name.compareTo(b.name));
      case 'CreatedAt':
        projects.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case 'Manual':
        projects.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      case 'Tag':
        // 本家準拠: タグ定義の登録順を一次キー(未定義/無タグは末尾)、その中は手動順
        final order = {
          for (var i = 0; i < workspaceTags.length; i++) workspaceTags[i].name: i
        };
        int idx(ManidocProject p) => order[p.tag] ?? (1 << 30);
        projects.sort((a, b) {
          final c = idx(a).compareTo(idx(b));
          return c != 0 ? c : a.sortOrder.compareTo(b.sortOrder);
        });
      default: // LastModifiedAt
        projects.sort((a, b) => b.lastModifiedAt.compareTo(a.lastModifiedAt));
    }
  }

  Future<void> refreshProjects() async {
    final ws = workspace;
    if (ws == null) return;
    loading = true;
    notifyListeners();
    projects = await ws.loadProjects();
    workspaceTags = await ws.loadTags();
    _sortProjects();
    loading = false;
    notifyListeners();
  }

  Future<ManidocProject> createProject(String name) async {
    final ws = workspace!;
    final project = ManidocProject(name: name)..sortOrder = projects.length;
    await ws.saveProject(project);
    await refreshProjects();
    return projects.firstWhere((p) => p.id == project.id);
  }

  /// 生成済みプロジェクト(インポート等)を保存して一覧を更新
  /// プロジェクト名の変更。IDはUUIDのままなのでデータファイル名・画像フォルダ・
  /// ノードリンク・MCP参照には影響しない(HTML出力のファイル名だけ次回出力から新名)。
  Future<void> renameProject(ManidocProject project, String newName) async {
    final name = newName.trim();
    if (name.isEmpty || name == project.name) return;
    project.name = name;
    await workspace!.saveProject(project);
    await refreshProjects();
  }

  Future<ManidocProject> addProject(ManidocProject project) async {
    project.sortOrder = projects.length;
    await workspace!.saveProject(project);
    await refreshProjects();
    return projects.firstWhere((p) => p.id == project.id);
  }

  /// 手動並び替え(▲▼)。projectSortAxisをManualへ切り替えて入れ替える。
  Future<void> moveProject(ManidocProject project, int delta) async {
    if (settings.projectSortAxis != 'Manual') {
      settings.projectSortAxis = 'Manual';
      for (var i = 0; i < projects.length; i++) {
        projects[i].sortOrder = i;
      }
      await settings.save();
    }
    final index = projects.indexWhere((p) => p.id == project.id);
    final newIndex = index + delta;
    if (index < 0 || newIndex < 0 || newIndex >= projects.length) return;
    final other = projects[newIndex];
    final tmp = project.sortOrder;
    project.sortOrder = other.sortOrder;
    other.sortOrder = tmp;
    await workspace!.saveProject(project);
    await workspace!.saveProject(other);
    await refreshProjects();
  }

  Future<void> deleteProject(ManidocProject project) async {
    await workspace!.deleteProject(project);
    await workspace!.removeCardColors([project.id]);
    await refreshProjects();
  }

  /// 一括削除。削除は取り消せずゴミ箱にも入らないので、1件ずつZIPバックアップを
  /// 取ってから消す。バックアップに失敗したプロジェクトは消さずに失敗として返す。
  /// 途中で失敗しても残りの処理は続ける(Driveのロック等で全体が止まらないように)。
  Future<({List<String> deleted, Map<String, String> failed, String? backupDir})>
      deleteProjects(List<ManidocProject> targets) async {
    final ws = workspace!;
    final backup = BackupService(ws);
    final deleted = <String>[];
    final deletedIds = <String>[];
    final failed = <String, String>{};
    String? backupDir;
    for (final project in targets) {
      try {
        final zipPath = await backup.backupProject(project);
        backupDir = File(zipPath).parent.path;
        await ws.deleteProject(project);
        deleted.add(project.name);
        deletedIds.add(project.id);
      } catch (e) {
        failed[project.name] = '$e';
      }
    }
    if (deletedIds.isNotEmpty) await ws.removeCardColors(deletedIds);
    await refreshProjects();
    return (deleted: deleted, failed: failed, backupDir: backupDir);
  }

  /// タイル色をまとめて設定する。null を渡した側は変更しない(一括設定の
  /// 「背景色だけ適用」に対応)。空文字を渡すと既定色へ戻す。
  /// 色は本文ではないので lastModifiedAt は動かさない。
  Future<void> setProjectsCardColor(List<ManidocProject> targets,
      {String? fore, String? back}) async {
    if (targets.isEmpty || (fore == null && back == null)) return;
    final ws = workspace!;
    for (final project in targets) {
      if (fore != null) project.cardForeColor = fore;
      if (back != null) project.cardBackColor = back;
      await ws.saveProject(project, touch: false);
    }
    await ws.updateCardColors(targets);
    await refreshProjects();
  }

  Future<void> toggleTheme() async {
    themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefDarkMode, themeMode == ThemeMode.dark);
    notifyListeners();
  }
}
