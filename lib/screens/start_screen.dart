import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../dialogs/card_color_dialog.dart';
import '../dialogs/settings_dialog.dart';
import '../dialogs/tag_dialog.dart';
import '../dialogs/tag_manager_dialog.dart';
import '../l10n/strings.dart';
import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';
import '../services/backup_service.dart';
import '../services/color_utils.dart';
import '../services/exports_manager.dart';
import '../services/html_exporter.dart';
import '../services/html_import.dart';
import '../services/markdown_io.dart';
import '../services/portal_exporter.dart';
import '../widgets/immersive_project_view.dart';
import 'ai_chat_screen.dart';
import 'editor_screen.dart';

/// 一括操作のショートカット用Intent
class _SelectAllProjectsIntent extends Intent {
  const _SelectAllProjectsIntent();
}

class _ClearProjectSelectionIntent extends Intent {
  const _ClearProjectSelectionIntent();
}

/// 条件付きで有効になるAction。無効の間はキーを消費しないので、
/// テキスト入力中のCtrl+A(文字の全選択)はそのまま生きる。
class _ConditionalCallbackAction<T extends Intent> extends CallbackAction<T> {
  _ConditionalCallbackAction({required super.onInvoke, required this.enabled});

  final bool Function() enabled;

  @override
  bool get isActionEnabled => enabled();
}

/// 検索ヒット(全プロジェクト横断)
class _GlobalHit {
  final ManidocProject project;
  final ManidocNode node;
  final String area; // 'title' | 'article' | 'comment'
  final String snippet;
  final int matchStart; // snippet 内でのヒット開始位置
  final int matchEnd; // snippet 内でのヒット終了位置
  _GlobalHit(this.project, this.node, this.area, this.snippet,
      this.matchStart, this.matchEnd);
}

/// スタート画面。本家StartView準拠: アクションタイル+プロジェクトカードグリッド。
class StartScreen extends StatefulWidget {
  final AppState appState;

  const StartScreen({super.key, required this.appState});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  AppState get app => widget.appState;

  final _globalSearchController = TextEditingController();
  List<_GlobalHit> _globalHits = [];

  /// ショートカットを受けるフォーカスノード。余白クリックでここへ戻すことで
  /// 検索欄からフォーカスを外しつつ、キーイベントがこの画面に届く状態を保つ。
  final _shortcutFocus = FocusNode(debugLabel: 'startScreenShortcuts');

  /// 一括操作(削除/色設定)のための選択モード。ONの間はカードのタップが選択になる。
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _globalSearchController.dispose();
    _shortcutFocus.dispose();
    super.dispose();
  }

  void _snack(String message, {String? folderPath}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      action: folderPath == null
          ? null
          : SnackBarAction(
              label: L.t('open_folder'), onPressed: () => _openFolder(folderPath)),
    ));
  }

  void _openFolder(String path) {
    if (Platform.isWindows) {
      Process.run('explorer', [path]);
    } else if (Platform.isMacOS) {
      Process.run('open', [path]);
    } else {
      Process.run('xdg-open', [path]);
    }
  }

  Future<void> _pickWorkspace() async {
    final path = await getDirectoryPath(confirmButtonText: L.t('use_this_folder'));
    if (path != null) await app.setWorkspace(path);
  }

  Future<bool> _requireWorkspace() async {
    if (app.workspace != null) return true;
    await _pickWorkspace();
    return app.workspace != null;
  }

  // ---------- 全プロジェクト横断の全文検索 ----------

  void _runGlobalSearch(String query) {
    final hits = <_GlobalHit>[];
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      for (final project in app.projects) {
        void walk(List<ManidocNode> nodes) {
          for (final node in nodes) {
            for (final entry in [
              ('title', node.title),
              ('article', node.article),
              ('comment', node.comment),
            ]) {
              final idx = entry.$2.toLowerCase().indexOf(q);
              if (idx >= 0) {
                final start = (idx - 15).clamp(0, entry.$2.length);
                final end = (idx + 30).clamp(0, entry.$2.length);
                final prefix = start > 0 ? '…' : '';
                final body =
                    entry.$2.substring(start, end).replaceAll('\n', ' ');
                final suffix = end < entry.$2.length ? '…' : '';
                final snippet = '$prefix$body$suffix';
                final matchStart = prefix.length + (idx - start);
                final matchEnd = matchStart + q.length;
                hits.add(_GlobalHit(
                    project, node, entry.$1, snippet, matchStart, matchEnd));
              }
            }
          }
          for (final node in nodes) {
            walk(node.children);
          }
        }

        walk(project.rootNodes);
      }
    }
    setState(() => _globalHits = hits);
  }

  Future<void> _newProject() async {
    if (!await _requireWorkspace()) return;
    if (!mounted) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.t('new_project')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
              labelText: L.t('project_name'),
              border: const OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(L.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(L.t('create_and_open'))),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final project = await app.createProject(name.trim());
    if (mounted) _openProject(project);
  }

  Future<void> _importMd() async {
    if (!await _requireWorkspace()) return;
    const typeGroup = XTypeGroup(label: 'Markdown', extensions: ['md', 'markdown', 'txt']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final content = await File(file.path).readAsString();
    final baseName = file.name.replaceAll(RegExp(r'\.(md|markdown|txt)$'), '');
    final project = MarkdownIo.importAsProject(baseName, content);
    final saved = await app.addProject(project);
    _snack(L.t('imported', [saved.name]));
    if (mounted) _openProject(saved);
  }

  Future<void> _importHtml() async {
    if (!await _requireWorkspace()) return;
    const typeGroup = XTypeGroup(label: 'HTML', extensions: ['html', 'htm']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    try {
      final project =
          await HtmlImport.importHtmlFile(app.workspace!, file.path);
      final saved = await app.addProject(project);
      _snack(L.t('imported', [saved.name]));
      if (mounted) _openProject(saved);
    } catch (e) {
      _snack(L.t('import_failed', [e]));
    }
  }

  Future<void> _importWeb() async {
    if (!await _requireWorkspace()) return;
    if (!mounted) return;
    final controller = TextEditingController(text: 'https://');
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.t('import_from_web')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
              labelText: L.t('url'), border: const OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(L.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(L.t('import'))),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    _snack(L.t('importing'));
    try {
      final project = await HtmlImport.importUrl(app.workspace!, url);
      final saved = await app.addProject(project);
      _snack(L.t('imported', [saved.name]));
      if (mounted) _openProject(saved);
    } catch (e) {
      _snack(L.t('import_failed', [e]));
    }
  }

  /// 🌐 Web一括出力: タイトルを聞いて全プロジェクトのポータルを生成
  Future<void> _exportPortal() async {
    if (app.workspace == null || app.projects.isEmpty) {
      _snack(L.t('no_export_projects'));
      return;
    }
    final controller = TextEditingController(text: L.t('manual_list'));
    final urlController = TextEditingController();
    // 既定は本家同様の自動判定(タグ付きプロジェクトが1件でもあればON)
    var groupByTag = app.projects.any((p) => p.tag.trim().isNotEmpty);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(L.t('portal_dialog_title', [app.projects.length])),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                    labelText: L.t('portal_title_label'),
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                    labelText: L.t('portal_url_label'),
                    hintText: 'https://...',
                    border: const OutlineInputBorder()),
                onSubmitted: (_) => Navigator.pop(context, true),
              ),
              CheckboxListTile(
                value: groupByTag,
                onChanged: (v) => setLocal(() => groupByTag = v ?? false),
                title: Text(L.t('portal_group_by_tag')),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(L.t('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(L.t('export'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final title = controller.text.trim();
    if (title.isEmpty) return;
    final s = app.settings;
    final dir = await PortalExporter(app.workspace!).export(
      app.projects,
      title,
      numbering: s.exportHeadingNumbering,
      tts: s.enableExportTts,
      ttsSpeed: s.exportTtsSpeed,
      articleFontSize: s.articleFontSize,
      titleUrl: urlController.text.trim(),
      useGrouping: groupByTag,
    );
    _snack(L.t('portal_done'), folderPath: dir);
  }

  Future<void> _restoreBackup() async {
    if (!await _requireWorkspace()) return;
    const typeGroup = XTypeGroup(label: 'ZIP', extensions: ['zip']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    try {
      await BackupService(app.workspace!).restoreFromZip(file.path);
      await app.refreshProjects();
      _snack(L.t('restore_done'));
    } catch (e) {
      _snack(L.t('restore_failed', [e]));
    }
  }

  void _openAiChat() {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AiChatScreen(appState: app)));
  }

  void _openProject(ManidocProject project, {String? nodeId}) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) =>
              EditorScreen(appState: app, project: project, initialNodeId: nodeId),
        ))
        .then((_) => app.refreshProjects());
  }

  Future<void> _confirmDelete(ManidocProject project) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.t('delete_project')),
        content: Text(L.t('delete_project_confirm', [project.name])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(L.t('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(L.t('do_delete')),
          ),
        ],
      ),
    );
    if (ok == true) await app.deleteProject(project);
  }

  // ---------- 選択モード(一括削除 / 一括色設定) ----------

  List<ManidocProject> get _selectedProjects =>
      app.projects.where((p) => _selectedIds.contains(p.id)).toList();

  void _toggleSelect(ManidocProject project) => setState(() {
        if (!_selectedIds.remove(project.id)) _selectedIds.add(project.id);
      });

  void _exitSelection() => setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });

  /// 一括削除。削除前に対象を1件ずつZIPバックアップしてから消す(AppState側で実施)。
  Future<void> _bulkDelete() async {
    final targets = _selectedProjects;
    if (targets.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.t('bulk_delete_title')),
        content: SizedBox(
          width: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(L.t('bulk_delete_confirm', [targets.length])),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final p in targets)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('・${p.name}',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(L.t('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(L.t('bulk_delete_do', [targets.length])),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _snack(L.t('bulk_delete_running', [targets.length]));
    final result = await app.deleteProjects(targets);
    if (!mounted) return;
    setState(() => _selectedIds.clear());
    if (result.failed.isEmpty) {
      _snack(L.t('bulk_delete_done', [result.deleted.length]),
          folderPath: result.backupDir);
    } else {
      final first = result.failed.entries.first;
      _snack(
          L.t('bulk_delete_partial', [
            result.deleted.length,
            result.failed.length,
            '${first.key}: ${first.value}'
          ]),
          folderPath: result.backupDir);
    }
  }

  /// 一括色設定。初期値は選択の先頭プロジェクトの色。
  Future<void> _bulkColor() async {
    final targets = _selectedProjects;
    if (targets.isEmpty) return;
    final first = targets.first;
    final result = await showCardColorDialog(
      context,
      app,
      initialFore: first.cardForeColor,
      initialBack: first.cardBackColor,
      bulkCount: targets.length,
    );
    if (result == null) return;
    await app.setProjectsCardColor(
      targets,
      fore: result.applyFore ? result.fore : null,
      back: result.applyBack ? result.back : null,
    );
    _snack(L.t('bulk_color_applied', [targets.length]));
  }

  Future<void> _editCardColor(ManidocProject project) async {
    final result = await showCardColorDialog(
      context,
      app,
      initialFore: project.cardForeColor,
      initialBack: project.cardBackColor,
    );
    if (result == null) return;
    await app.setProjectsCardColor([project],
        fore: result.fore, back: result.back);
  }

  Future<void> _editTag(ManidocProject project) async {
    final tag = await showTagDialog(context, app, project.tag);
    if (tag != null) await app.setProjectTag(project, tag);
  }

  Future<void> _renameProject(ManidocProject project) async {
    final controller = TextEditingController(text: project.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.t('menu_rename')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(L.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(L.t('save'))),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await app.renameProject(project, name);
    }
  }

  Future<void> _exportHtml(ManidocProject project) async {
    final ws = app.workspace!;
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    final safeName = project.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final outDir =
        '${ws.workspacePath}${Platform.pathSeparator}exports${Platform.pathSeparator}${safeName}_$stamp';
    final s = app.settings;
    final path = await HtmlExporter(ws).export(
      project,
      outDir,
      numbering: s.exportHeadingNumbering,
      tts: s.enableExportTts,
      ttsSpeed: s.exportTtsSpeed,
      optimize: s.enableExportOptimization,
      jpegQuality: s.exportJpegQuality,
      maxDimension: s.exportMaxDimension,
      articleFontSize: s.articleFontSize,
      themeCss: await ws.readThemeCss(project.themeCssFileName),
    );
    setState(() {});
    _snack(L.t('html_exported'), folderPath: path);
  }

  Future<void> _cleanupExport(ManidocProject project, bool html) async {
    final manager = ExportsManager(app.workspace!);
    try {
      final deleted = html
          ? await manager.deleteOldestHtml(project)
          : await manager.deleteOldestMd(project);
      if (!mounted) return;
      setState(() {});
      _snack(deleted ? L.t('cleaned_oldest') : L.t('nothing_to_clean'));
    } catch (e) {
      // 削除失敗(フォルダを開いたまま / Google Drive のロック等)を無言にせず通知する
      if (!mounted) return;
      setState(() {});
      _snack(L.t('cleanup_failed', [e]));
    }
  }

  Future<void> _exportMd(ManidocProject project) async {
    final outDir =
        '${app.workspace!.workspacePath}${Platform.pathSeparator}exports';
    final path = await MarkdownIo.exportToFile(project, outDir,
        numbering: app.settings.exportHeadingNumbering);
    setState(() {});
    _snack(L.t('md_exported'), folderPath: File(path).parent.path);
  }

  Future<void> _backup(ManidocProject project) async {
    final zip = await BackupService(app.workspace!).backupProject(project);
    _snack(L.t('backup_done'), folderPath: File(zip).parent.path);
  }

  int _countNodes(List<ManidocNode> nodes) => nodes.fold(
      0, (sum, node) => sum + 1 + _countNodes(node.children));

  // 一括操作のショートカット。Ctrl(macはCmd)+A ですべて選択、Shiftを足すと選択解除。
  static const _selectionShortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.keyA, control: true):
        _SelectAllProjectsIntent(),
    SingleActivator(LogicalKeyboardKey.keyA, meta: true):
        _SelectAllProjectsIntent(),
    SingleActivator(LogicalKeyboardKey.keyA, control: true, shift: true):
        _ClearProjectSelectionIntent(),
    SingleActivator(LogicalKeyboardKey.keyA, meta: true, shift: true):
        _ClearProjectSelectionIntent(),
  };

  /// ショートカットを受け付けてよい状況か。
  /// 検索欄などテキスト入力中はfalseにして、入力欄側のCtrl+A(文字の全選択)を殺さない
  /// (Actionが無効なら Shortcuts はキーを消費せず、そのまま上へ流れる)。
  bool get _canUseSelectionShortcut {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext != null &&
        (focusContext.widget is EditableText ||
            focusContext.findAncestorWidgetOfExactType<EditableText>() !=
                null)) {
      return false;
    }
    return app.workspace != null &&
        app.projects.isNotEmpty &&
        !app.settings.immersiveProjectView;
  }

  /// Ctrl+A: 選択モードがOFFなら自動でONにしてから全選択する。
  void _shortcutSelectAll() {
    if (app.workspace == null ||
        app.projects.isEmpty ||
        app.settings.immersiveProjectView) {
      return;
    }
    setState(() {
      _selectionMode = true;
      _selectedIds
        ..clear()
        ..addAll(app.projects.map((p) => p.id));
    });
  }

  void _shortcutClearSelection() {
    if (!_selectionMode || _selectedIds.isEmpty) return;
    setState(_selectedIds.clear);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Shortcuts(
        shortcuts: _selectionShortcuts,
        child: Actions(
          actions: {
            _SelectAllProjectsIntent:
                _ConditionalCallbackAction<_SelectAllProjectsIntent>(
              onInvoke: (_) {
                _shortcutSelectAll();
                return null;
              },
              enabled: () => _canUseSelectionShortcut,
            ),
            _ClearProjectSelectionIntent:
                _ConditionalCallbackAction<_ClearProjectSelectionIntent>(
              onInvoke: (_) {
                _shortcutClearSelection();
                return null;
              },
              enabled: () =>
                  _canUseSelectionShortcut && _selectionMode && _selectedIds.isNotEmpty,
            ),
          },
          child: Focus(
            focusNode: _shortcutFocus,
            autofocus: true,
            child: Scaffold(
        body: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: app.settings.immersiveProjectView && app.workspace != null
                  ? ImmersiveProjectView(
                      app: app,
                      projects: app.projects,
                      onOpen: _openProject,
                      onOpenNode: (p, nodeId) =>
                          _openProject(p, nodeId: nodeId),
                    )
                  // 余白クリックで検索欄のフォーカスを外す。
                  // (入力欄にフォーカスが残っているとCtrl+Aが入力欄側の全選択になるため)
                  : GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _shortcutFocus.requestFocus,
                      child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    _buildHero(context),
                    const SizedBox(height: 20),
                    if (app.workspace != null) _buildGlobalSearch(context),
                    if (_globalHits.isNotEmpty)
                      _buildGlobalResults(context)
                    else ...[
                      const SizedBox(height: 20),
                      _buildActionTiles(context),
                      const SizedBox(height: 32),
                      _buildManagementRow(context),
                      const SizedBox(height: 12),
                      if (_selectionMode) _buildSelectionBar(context),
                      _buildProjectGrid(context),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
                    ),
            ),
          ],
        ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
            bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          const Icon(Icons.menu_book, size: 20),
          const SizedBox(width: 8),
          const Text('openManidoc',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 24),
          Expanded(
            child: Text(
              app.workspace?.workspacePath ?? L.t('workspace_unset'),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton.icon(
            onPressed: _pickWorkspace,
            icon: const Icon(Icons.folder_open, size: 18),
            label: Text(L.t('browse_folder')),
          ),
          IconButton(
            tooltip: app.settings.immersiveProjectView
                ? L.t('grid_view')
                : L.t('immersive_view'),
            icon: Icon(app.settings.immersiveProjectView
                ? Icons.grid_view
                : Icons.threesixty),
            onPressed: () {
              setState(() => app.settings.immersiveProjectView =
                  !app.settings.immersiveProjectView);
              app.saveSettings();
            },
          ),
          IconButton(
            tooltip: L.t('settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => showSettingsDialog(context, app),
          ),
          IconButton(
            tooltip: L.t('toggle_theme'),
            icon: Icon(app.themeMode == ThemeMode.dark
                ? Icons.light_mode
                : Icons.dark_mode),
            onPressed: app.toggleTheme,
          ),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    return Text(L.t('hero_title'),
        style: Theme.of(context)
            .textTheme
            .headlineMedium
            ?.copyWith(fontWeight: FontWeight.bold));
  }

  Widget _buildGlobalSearch(BuildContext context) {
    return TextField(
      controller: _globalSearchController,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: L.t('global_search_hint'),
        isDense: true,
        border: const OutlineInputBorder(),
        suffixIcon: _globalSearchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _globalSearchController.clear();
                  _runGlobalSearch('');
                },
              ),
      ),
      onChanged: _runGlobalSearch,
    );
  }

  /// 検索スニペット内のヒット箇所を強調表示する TextSpan を組み立てる。
  TextSpan _highlightedSnippet(BuildContext context, _GlobalHit hit) {
    final baseStyle = Theme.of(context).textTheme.bodyMedium;
    final start = hit.matchStart.clamp(0, hit.snippet.length);
    final end = hit.matchEnd.clamp(start, hit.snippet.length);
    return TextSpan(
      style: baseStyle,
      children: [
        TextSpan(text: hit.snippet.substring(0, start)),
        TextSpan(
          text: hit.snippet.substring(start, end),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            backgroundColor: Color(0xFFFFEB3B), // マーカーペン風の黄色(テーマ非依存で視認性優先)
            color: Colors.black,
          ),
        ),
        TextSpan(text: hit.snippet.substring(end)),
      ],
    );
  }

  Widget _buildGlobalResults(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(L.t('search_result_count', [_globalHits.length]),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final hit in _globalHits)
          Card(
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.article_outlined),
              title: Text('${hit.project.name}  ›  ${hit.node.title}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text.rich(
                _highlightedSnippet(context, hit),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Chip(
                label: Text(hit.area, style: const TextStyle(fontSize: 10)),
                visualDensity: VisualDensity.compact,
              ),
              onTap: () => _openProject(hit.project, nodeId: hit.node.id),
            ),
          ),
      ],
    );
  }

  Widget _buildActionTiles(BuildContext context) {
    final tiles = [
      (Icons.add_circle_outline, L.t('tile_new'), L.t('tile_new_sub'), _newProject),
      (
        Icons.file_open_outlined,
        L.t('tile_import'),
        L.t('tile_import_sub'),
        () async {
          final kind = await showDialog<String>(
            context: context,
            builder: (context) => SimpleDialog(
              title: Text(L.t('import_title')),
              children: [
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, 'md'),
                    child: Text(L.t('import_md'))),
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, 'html'),
                    child: Text(L.t('import_html'))),
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, 'web'),
                    child: Text(L.t('import_web'))),
              ],
            ),
          );
          switch (kind) {
            case 'md':
              await _importMd();
            case 'html':
              await _importHtml();
            case 'web':
              await _importWeb();
          }
        }
      ),
      (Icons.smart_toy_outlined, L.t('tile_ai'), L.t('tile_ai_sub'), _openAiChat),
      (Icons.unarchive_outlined, L.t('tile_restore'), L.t('tile_restore_sub'),
          _restoreBackup),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final (icon, title, subtitle, onTap) in tiles)
          SizedBox(
            width: 220,
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon,
                          size: 28,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 8),
                      Text(title,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// タグチップ(定義に画像があればサムネイル付き)
  Widget _buildTagChip(BuildContext context, String tag) {
    final imgPath = app.tagImage(tag);
    final hasImg = imgPath != null && File(imgPath).existsSync();
    return Container(
      padding: EdgeInsets.only(
          left: hasImg ? 2 : 8, right: 8, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasImg) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(imgPath),
                  width: 16, height: 16, fit: BoxFit.cover),
            ),
            const SizedBox(width: 4),
          ],
          Text(tag, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildManagementRow(BuildContext context) {
    return Row(
      children: [
        Text(L.t('projects'),
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(width: 16),
        Text(L.t('sort_label'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: app.settings.projectSortAxis,
          isDense: true,
          underline: const SizedBox.shrink(),
          items: [
            DropdownMenuItem(value: 'LastModifiedAt', child: Text(L.t('sort_modified'))),
            DropdownMenuItem(value: 'CreatedAt', child: Text(L.t('sort_created'))),
            DropdownMenuItem(value: 'Name', child: Text(L.t('sort_name'))),
            DropdownMenuItem(value: 'Tag', child: Text(L.t('sort_tag'))),
            DropdownMenuItem(value: 'Manual', child: Text(L.t('sort_manual'))),
          ],
          onChanged: (v) {
            app.settings.projectSortAxis = v!;
            app.saveSettings();
          },
        ),
        const SizedBox(width: 8),
        // 本家GroupByTag互換: タグ見出しごとにまとめて表示するトグル
        TextButton.icon(
          onPressed: () {
            app.settings.groupByTag = !app.settings.groupByTag;
            app.saveSettings();
          },
          icon: Icon(
              app.settings.groupByTag
                  ? Icons.workspaces
                  : Icons.workspaces_outlined,
              size: 18),
          label: Text(app.settings.groupByTag
              ? L.t('ungroup')
              : L.t('group_by_tag')),
        ),
        const Spacer(),
        if (app.workspace != null) ...[
          TextButton.icon(
            onPressed: app.projects.isEmpty
                ? null
                : () => setState(() {
                      _selectionMode = !_selectionMode;
                      if (!_selectionMode) _selectedIds.clear();
                    }),
            icon: Icon(
                _selectionMode ? Icons.check_box : Icons.check_box_outlined,
                size: 18),
            label:
                Text(_selectionMode ? L.t('select_exit') : L.t('select_mode')),
          ),
          TextButton.icon(
            onPressed: () => showTagManagerDialog(context, app),
            icon: const Icon(Icons.sell_outlined, size: 18),
            label: Text(L.t('tag_manager')),
          ),
          TextButton.icon(
            onPressed: _exportPortal,
            icon: const Icon(Icons.language, size: 18),
            label: Text(L.t('portal_export', [app.projects.length])),
          ),
          TextButton.icon(
            onPressed: () => app.refreshProjects(),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(L.t('reload')),
          ),
        ],
      ],
    );
  }

  /// 選択モード中の操作バー(件数/全選択/解除/色設定/削除)
  Widget _buildSelectionBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = _selectedIds.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(L.t('selected_count', [count]),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          Tooltip(
            message: L.t('select_all_shortcut'),
            child: TextButton.icon(
              icon: const Icon(Icons.select_all, size: 18),
              label: Text(L.t('select_all')),
              onPressed: () => setState(() {
                _selectedIds
                  ..clear()
                  ..addAll(app.projects.map((p) => p.id));
              }),
            ),
          ),
          Tooltip(
            message: L.t('select_clear_shortcut'),
            child: TextButton.icon(
              icon: const Icon(Icons.deselect, size: 18),
              label: Text(L.t('select_clear')),
              onPressed: count == 0
                  ? null
                  : () => setState(() => _selectedIds.clear()),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.palette_outlined, size: 18),
            label: Text(L.t('bulk_color')),
            onPressed: count == 0 ? null : _bulkColor,
          ),
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(L.t('bulk_delete')),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            onPressed: count == 0 ? null : _bulkDelete,
          ),
          IconButton(
            tooltip: L.t('select_exit'),
            icon: const Icon(Icons.close, size: 18),
            onPressed: _exitSelection,
          ),
        ],
      ),
    );
  }

  Widget _buildProjectGrid(BuildContext context) {
    if (app.workspace == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(child: Text(L.t('select_workspace_first'))),
      );
    }
    if (app.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (app.projects.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(child: Text(L.t('no_projects'))),
      );
    }
    if (app.settings.groupByTag) return _buildGroupedGrid(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [for (final p in app.projects) _buildProjectCard(context, p)],
    );
  }

  // タグ見出しごとにセクション分けして表示(本家GroupByTag互換)。
  // セクション順=タグ定義順(未定義タグは名前順、無タグは末尾)。
  // セクション内=現在のソート順(app.projectsは_sortProjects適用済み)を保持。
  Widget _buildGroupedGrid(BuildContext context) {
    final tagOrder = {
      for (var i = 0; i < app.workspaceTags.length; i++)
        app.workspaceTags[i].name: i
    };
    final buckets = <String, List<ManidocProject>>{};
    for (final p in app.projects) {
      buckets.putIfAbsent(p.tag.trim(), () => []).add(p);
    }
    final keys = buckets.keys.toList()
      ..sort((a, b) {
        if (a == b) return 0;
        if (a.isEmpty) return 1; // 無タグは最後
        if (b.isEmpty) return -1;
        final ia = tagOrder[a] ?? (1 << 30);
        final ib = tagOrder[b] ?? (1 << 30);
        return ia != ib ? ia.compareTo(ib) : a.compareTo(b);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final key in keys) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sell_outlined,
                    size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(key.isEmpty ? L.t('tag_none') : key,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text('${buckets[key]!.length}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final p in buckets[key]!) _buildProjectCard(context, p)
            ],
          ),
          const Divider(height: 28),
        ],
      ],
    );
  }

  Widget _buildProjectCard(BuildContext context, ManidocProject project) {
    final updated =
        project.lastModifiedAt.toLocal().toString().substring(0, 16);
    final scheme = Theme.of(context).colorScheme;
    // 背景色だけ設定されても読めるよう、文字色が未設定なら背景から自動で決める
    final backColor = colorFromHex(project.cardBackColor);
    final foreColor = colorFromHex(project.cardForeColor) ??
        (backColor != null
            ? contrastForegroundFor(backColor)
            : scheme.onSurface);
    // 薄い文字は半透明ではなく背景に畳んだ実色にする(内蔵GPUのVRAM対策)
    final metaColor =
        blendOpaque(foreColor, backColor ?? scheme.surfaceContainerLow, 0.7);
    final selected = _selectedIds.contains(project.id);
    return SizedBox(
      width: 300,
      child: Card(
        color: backColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: selected
              ? BorderSide(color: scheme.primary, width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _selectionMode
              ? () => _toggleSelect(project)
              : () => _openProject(project),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_selectionMode)
                      SizedBox(
                        width: 30,
                        height: 24,
                        child: Checkbox(
                          value: selected,
                          visualDensity: VisualDensity.compact,
                          onChanged: (_) => _toggleSelect(project),
                        ),
                      ),
                    if (project.tag.isNotEmpty)
                      _buildTagChip(context, project.tag)
                    else
                      const SizedBox(height: 20),
                    const Spacer(),
                    PopupMenuButton<String>(
                      tooltip: L.t('operations'),
                      icon: Icon(Icons.more_horiz, size: 20, color: foreColor),
                      onSelected: (value) {
                        switch (value) {
                          case 'rename':
                            _renameProject(project);
                          case 'up':
                            app.moveProject(project, -1);
                          case 'down':
                            app.moveProject(project, 1);
                          case 'tag':
                            _editTag(project);
                          case 'color':
                            _editCardColor(project);
                          case 'html':
                            _exportHtml(project);
                          case 'md':
                            _exportMd(project);
                          case 'cleanHtml':
                            _cleanupExport(project, true);
                          case 'cleanMd':
                            _cleanupExport(project, false);
                          case 'openExports':
                            final dir =
                                ExportsManager(app.workspace!).exportsDir;
                            if (Directory(dir).existsSync()) {
                              _openFolder(dir);
                            } else {
                              _snack(L.t('no_exports_yet'));
                            }
                          case 'backup':
                            _backup(project);
                          case 'delete':
                            _confirmDelete(project);
                        }
                      },
                      itemBuilder: (context) {
                        final manager = ExportsManager(app.workspace!);
                        final htmlCount = manager.countHtml(project);
                        final mdCount = manager.countMd(project);
                        return [
                          PopupMenuItem(
                              value: 'rename',
                              child: Text(L.t('menu_rename'))),
                          PopupMenuItem(value: 'up', child: Text(L.t('menu_up'))),
                          PopupMenuItem(
                              value: 'down', child: Text(L.t('menu_down'))),
                          PopupMenuItem(
                              value: 'tag', child: Text(L.t('menu_tag'))),
                          PopupMenuItem(
                              value: 'color',
                              child: Text(L.t('menu_card_color'))),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                              value: 'html', child: Text(L.t('menu_html'))),
                          PopupMenuItem(
                              value: 'md', child: Text(L.t('menu_md'))),
                          PopupMenuItem(
                              value: 'cleanHtml',
                              enabled: htmlCount > 0,
                              child: Text(L.t('menu_clean_html', [htmlCount]))),
                          PopupMenuItem(
                              value: 'cleanMd',
                              enabled: mdCount > 0,
                              child: Text(L.t('menu_clean_md', [mdCount]))),
                          PopupMenuItem(
                              value: 'openExports',
                              child: Text(L.t('menu_open_exports'))),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                              value: 'backup', child: Text(L.t('menu_backup'))),
                          PopupMenuItem(
                              value: 'delete', child: Text(L.t('menu_delete'))),
                        ];
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  project.name,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: foreColor),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  '${L.t('updated')}: $updated　${L.t('items')}: ${_countNodes(project.rootNodes)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: metaColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
