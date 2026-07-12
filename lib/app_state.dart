import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/strings.dart';
import 'models/manidoc_project.dart';
import 'services/ai_service.dart';
import 'services/settings_service.dart';
import 'services/workspace_service.dart';

/// アプリ全体の状態(ワークスペース・プロジェクト一覧・テーマ・設定)
class AppState extends ChangeNotifier {
  static const _prefWorkspace = 'workspacePath';
  static const _prefDarkMode = 'darkMode';

  WorkspaceService? workspace;
  List<ManidocProject> projects = [];
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

  /// ワークスペース内の全プロジェクトから使われているタグの一覧
  List<String> get allTags {
    final tags = projects
        .map((p) => p.tag)
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return tags;
  }

  Future<void> setProjectTag(ManidocProject project, String tag) async {
    project.tag = tag;
    await workspace!.saveProject(project);
    await refreshProjects();
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
    await refreshProjects();
  }

  Future<void> toggleTheme() async {
    themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefDarkMode, themeMode == ThemeMode.dark);
    notifyListeners();
  }
}
