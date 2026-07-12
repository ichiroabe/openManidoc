import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../dialogs/settings_dialog.dart';
import '../dialogs/tag_dialog.dart';
import '../l10n/strings.dart';
import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';
import '../services/backup_service.dart';
import '../services/exports_manager.dart';
import '../services/html_exporter.dart';
import '../services/html_import.dart';
import '../services/markdown_io.dart';
import '../services/portal_exporter.dart';
import 'ai_chat_screen.dart';
import 'editor_screen.dart';

/// 検索ヒット(全プロジェクト横断)
class _GlobalHit {
  final ManidocProject project;
  final ManidocNode node;
  final String area; // 'title' | 'article' | 'comment'
  final String snippet;
  _GlobalHit(this.project, this.node, this.area, this.snippet);
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

  @override
  void dispose() {
    _globalSearchController.dispose();
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
                final snippet =
                    '${start > 0 ? '…' : ''}${entry.$2.substring(start, end).replaceAll('\n', ' ')}${end < entry.$2.length ? '…' : ''}';
                hits.add(_GlobalHit(project, node, entry.$1, snippet));
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
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.t('portal_dialog_title', [app.projects.length])),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
              labelText: L.t('portal_title_label'),
              border: const OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(L.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(L.t('export'))),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    final s = app.settings;
    final dir = await PortalExporter(app.workspace!).export(
      app.projects,
      title,
      numbering: s.exportHeadingNumbering,
      tts: s.enableExportTts,
      ttsSpeed: s.exportTtsSpeed,
      articleFontSize: s.articleFontSize,
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

  Future<void> _editTag(ManidocProject project) async {
    final tag = await showTagDialog(context, app, project.tag);
    if (tag != null) await app.setProjectTag(project, tag);
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
    final deleted = html
        ? await manager.deleteOldestHtml(project)
        : await manager.deleteOldestMd(project);
    setState(() {});
    _snack(deleted ? L.t('cleaned_oldest') : L.t('nothing_to_clean'));
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Scaffold(
        body: Column(
          children: [
            _buildTopBar(context),
            Expanded(
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
                      _buildProjectGrid(context),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
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
              subtitle: Text(hit.snippet,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
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
            DropdownMenuItem(value: 'Manual', child: Text(L.t('sort_manual'))),
          ],
          onChanged: (v) {
            app.settings.projectSortAxis = v!;
            app.saveSettings();
          },
        ),
        const Spacer(),
        if (app.workspace != null) ...[
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
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [for (final p in app.projects) _buildProjectCard(context, p)],
    );
  }

  Widget _buildProjectCard(BuildContext context, ManidocProject project) {
    final updated =
        project.lastModifiedAt.toLocal().toString().substring(0, 16);
    return SizedBox(
      width: 300,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openProject(project),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (project.tag.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .secondaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(project.tag,
                            style: const TextStyle(fontSize: 11)),
                      )
                    else
                      const SizedBox(height: 20),
                    const Spacer(),
                    PopupMenuButton<String>(
                      tooltip: L.t('operations'),
                      icon: const Icon(Icons.more_horiz, size: 20),
                      onSelected: (value) {
                        switch (value) {
                          case 'up':
                            app.moveProject(project, -1);
                          case 'down':
                            app.moveProject(project, 1);
                          case 'tag':
                            _editTag(project);
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
                          PopupMenuItem(value: 'up', child: Text(L.t('menu_up'))),
                          PopupMenuItem(
                              value: 'down', child: Text(L.t('menu_down'))),
                          PopupMenuItem(
                              value: 'tag', child: Text(L.t('menu_tag'))),
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
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  '${L.t('updated')}: $updated　${L.t('items')}: ${_countNodes(project.rootNodes)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
