import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../app_state.dart';
import '../dialogs/ai_assistant_dialog.dart';
import '../dialogs/expanded_edit_dialog.dart';
import '../dialogs/image_editor_dialog.dart';
import '../dialogs/theme_generator_dialog.dart';
import '../l10n/strings.dart';
import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';
import '../services/html_exporter.dart';
import '../services/html_import.dart';
import '../services/markdown_io.dart';
import '../widgets/markdown_toolbar.dart';
import '../widgets/mindmap_view.dart';

/// 編集画面。本家ProjectView準拠:
/// ツールバー / 検索・置換付きツリー(D&D対応) / 記事編集 / ズーム+同期プレビュー / マインドマップ
class EditorScreen extends StatefulWidget {
  final AppState appState;
  final ManidocProject project;
  final String? initialNodeId;

  const EditorScreen({
    super.key,
    required this.appState,
    required this.project,
    this.initialNodeId,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  ManidocNode? _selected;
  bool _dirty = false;
  bool _includeToc = true;
  bool _showMindMap = false;
  double _treeWidth = 300;
  double _previewWidth = 420;
  double _zoom = 0.75;
  bool _generatingImage = false;
  List<String> _themeFiles = [];

  // 検索・置換
  final _searchController = TextEditingController();
  final _replaceController = TextEditingController();
  List<ManidocNode> _searchHits = [];
  int _searchIndex = -1;

  // D&D
  ManidocNode? _dropTarget;
  String _dropZone = 'child'; // 'before' | 'child' | 'after'

  // プレビュー同期用: ノードidごとのキー
  final Map<String, GlobalKey> _previewKeys = {};

  final _titleController = TextEditingController();
  final _articleController = TextEditingController();
  final _commentController = TextEditingController();
  final _aiPromptController = TextEditingController();

  ManidocProject get project => widget.project;
  AppState get app => widget.appState;

  @override
  void initState() {
    super.initState();
    _loadThemes();
    if (project.rootNodes.isNotEmpty) {
      final initial = widget.initialNodeId != null
          ? _findById(project.rootNodes, widget.initialNodeId!)
          : null;
      final node = initial ??
          _findById(project.rootNodes, project.lastSelectedNodeId) ??
          project.rootNodes.first;
      if (initial != null) _expandAncestors(initial);
      _select(node);
    }
  }

  Future<void> _loadThemes() async {
    final files = await app.workspace!.listThemeCssFiles();
    if (mounted) setState(() => _themeFiles = files);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _articleController.dispose();
    _commentController.dispose();
    _aiPromptController.dispose();
    _searchController.dispose();
    _replaceController.dispose();
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

  // ---------- ツリー探索 ----------

  ManidocNode? _findById(List<ManidocNode> nodes, String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
      final found = _findById(node.children, id);
      if (found != null) return found;
    }
    return null;
  }

  (List<ManidocNode>, int, ManidocNode?)? _locate(
      List<ManidocNode> list, ManidocNode target,
      [ManidocNode? parent]) {
    for (var i = 0; i < list.length; i++) {
      if (identical(list[i], target)) return (list, i, parent);
      final found = _locate(list[i].children, target, list[i]);
      if (found != null) return found;
    }
    return null;
  }

  void _expandAncestors(ManidocNode target) {
    bool walk(List<ManidocNode> nodes) {
      for (final node in nodes) {
        if (identical(node, target)) return true;
        if (walk(node.children)) {
          node.isExpanded = true;
          return true;
        }
      }
      return false;
    }

    walk(project.rootNodes);
  }

  bool _isDescendant(ManidocNode ancestor, ManidocNode maybe) {
    for (final child in ancestor.children) {
      if (identical(child, maybe) || _isDescendant(child, maybe)) return true;
    }
    return false;
  }

  // ---------- ノード操作 ----------

  void _select(ManidocNode node) {
    setState(() {
      _selected = node;
      project.lastSelectedNodeId = node.id;
      _titleController.text = node.title;
      _articleController.text = node.article;
      _commentController.text = node.comment;
      _aiPromptController.text = node.aiPrompt;
    });
    _syncPreviewToSelection();
  }

  void _syncPreviewToSelection() {
    final node = _selected;
    if (node == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _previewKeys[node.id];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 300),
            alignment: 0.1,
            curve: Curves.easeInOut);
      }
    });
  }

  void _addNode({bool asChild = false}) {
    final node = ManidocNode();
    setState(() {
      final sel = _selected;
      if (sel == null) {
        project.rootNodes.add(node);
      } else if (asChild) {
        sel.children.add(node);
        sel.isExpanded = true;
      } else {
        final loc = _locate(project.rootNodes, sel)!;
        loc.$1.insert(loc.$2 + 1, node);
      }
      _dirty = true;
    });
    _select(node);
  }

  Future<void> _deleteSelected() async {
    final sel = _selected;
    if (sel == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.t('item_delete')),
        content: Text(L.t('item_delete_confirm', [sel.title])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(L.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(L.t('do_delete'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      final loc = _locate(project.rootNodes, sel)!;
      loc.$1.removeAt(loc.$2);
      _selected = null;
      _dirty = true;
    });
  }

  void _moveVertical(int delta) {
    final sel = _selected;
    if (sel == null) return;
    final loc = _locate(project.rootNodes, sel)!;
    final newIndex = loc.$2 + delta;
    if (newIndex < 0 || newIndex >= loc.$1.length) return;
    setState(() {
      loc.$1.removeAt(loc.$2);
      loc.$1.insert(newIndex, sel);
      _dirty = true;
    });
  }

  void _demote() {
    final sel = _selected;
    if (sel == null) return;
    final loc = _locate(project.rootNodes, sel)!;
    if (loc.$2 == 0) return;
    setState(() {
      final prevSibling = loc.$1[loc.$2 - 1];
      loc.$1.removeAt(loc.$2);
      prevSibling.children.add(sel);
      prevSibling.isExpanded = true;
      _dirty = true;
    });
  }

  void _promote() {
    final sel = _selected;
    if (sel == null) return;
    final loc = _locate(project.rootNodes, sel)!;
    final parent = loc.$3;
    if (parent == null) return;
    final parentLoc = _locate(project.rootNodes, parent)!;
    setState(() {
      loc.$1.removeAt(loc.$2);
      parentLoc.$1.insert(parentLoc.$2 + 1, sel);
      _dirty = true;
    });
  }

  /// D&D: draggedをtargetの前/子/後へ移動する
  void _moveByDrag(ManidocNode dragged, ManidocNode target, String zone) {
    if (identical(dragged, target)) return;
    if (_isDescendant(dragged, target)) return; // 自分の子孫へは移動不可
    setState(() {
      final loc = _locate(project.rootNodes, dragged)!;
      loc.$1.removeAt(loc.$2);
      if (zone == 'child') {
        target.children.add(dragged);
        target.isExpanded = true;
      } else {
        final targetLoc = _locate(project.rootNodes, target)!;
        final insertAt = zone == 'after' ? targetLoc.$2 + 1 : targetLoc.$2;
        targetLoc.$1.insert(insertAt, dragged);
      }
      _dirty = true;
    });
  }

  // ---------- 検索・置換 ----------

  void _runSearch(String query) {
    _searchHits = [];
    _searchIndex = -1;
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      void walk(List<ManidocNode> nodes) {
        for (final node in nodes) {
          if (node.title.toLowerCase().contains(q) ||
              node.article.toLowerCase().contains(q) ||
              node.comment.toLowerCase().contains(q)) {
            _searchHits.add(node);
          }
          walk(node.children);
        }
      }

      walk(project.rootNodes);
    }
    setState(() {});
  }

  void _jumpSearch(int delta) {
    if (_searchHits.isEmpty) return;
    _searchIndex = (_searchIndex + delta) % _searchHits.length;
    if (_searchIndex < 0) _searchIndex += _searchHits.length;
    final node = _searchHits[_searchIndex];
    _expandAncestors(node);
    _select(node);
  }

  /// 現在の選択ノード(検索ヒット)で1件置換
  void _replaceOne() {
    final query = _searchController.text;
    final replacement = _replaceController.text;
    if (query.isEmpty || _searchIndex < 0 || _searchIndex >= _searchHits.length) {
      return;
    }
    final node = _searchHits[_searchIndex];
    setState(() {
      node.title = _replaceInsensitive(node.title, query, replacement);
      node.article = _replaceInsensitive(node.article, query, replacement);
      node.comment = _replaceInsensitive(node.comment, query, replacement);
      _dirty = true;
      if (identical(node, _selected)) {
        _titleController.text = node.title;
        _articleController.text = node.article;
        _commentController.text = node.comment;
      }
    });
    _runSearch(query);
  }

  void _replaceAll() {
    final query = _searchController.text;
    final replacement = _replaceController.text;
    if (query.isEmpty) return;
    var count = 0;
    void walk(List<ManidocNode> nodes) {
      for (final node in nodes) {
        final t = _countOccurrences(node.title, query) +
            _countOccurrences(node.article, query) +
            _countOccurrences(node.comment, query);
        if (t > 0) {
          count += t;
          node.title = _replaceInsensitive(node.title, query, replacement);
          node.article = _replaceInsensitive(node.article, query, replacement);
          node.comment = _replaceInsensitive(node.comment, query, replacement);
        }
        walk(node.children);
      }
    }

    setState(() {
      walk(project.rootNodes);
      _dirty = true;
      final sel = _selected;
      if (sel != null) {
        _titleController.text = sel.title;
        _articleController.text = sel.article;
        _commentController.text = sel.comment;
      }
    });
    _runSearch(query);
    _snack(L.t('replaced_all', [count]));
  }

  int _countOccurrences(String text, String query) {
    if (query.isEmpty) return 0;
    return RegExp(RegExp.escape(query), caseSensitive: false)
        .allMatches(text)
        .length;
  }

  String _replaceInsensitive(String text, String query, String replacement) {
    if (query.isEmpty) return text;
    return text.replaceAll(
        RegExp(RegExp.escape(query), caseSensitive: false), replacement);
  }

  // ---------- 保存・再読込・出力 ----------

  Future<void> _save({bool silent = false}) async {
    await app.workspace!.saveProject(project);
    final removed = await app.workspace!.cleanupUnusedImages(project);
    setState(() => _dirty = false);
    if (!silent) {
      _snack(removed > 0 ? L.t('saved_cleaned', [removed]) : L.t('saved'));
    }
  }

  Future<void> _reload() async {
    final loaded = await app.workspace!.loadProjectById(project.id);
    if (loaded == null) return;
    setState(() {
      project
        ..name = loaded.name
        ..description = loaded.description
        ..tag = loaded.tag
        ..themeCssFileName = loaded.themeCssFileName
        ..rootNodes = loaded.rootNodes;
      _dirty = false;
      _selected = null;
    });
    if (project.rootNodes.isNotEmpty) {
      _select(_findById(project.rootNodes, project.lastSelectedNodeId) ??
          project.rootNodes.first);
    }
    _snack(L.t('reloaded'));
  }

  String _exportDirBase() {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    final safeName = project.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return '${app.workspace!.workspacePath}${Platform.pathSeparator}exports'
        '${Platform.pathSeparator}${safeName}_$stamp';
  }

  Future<void> _exportHtml() async {
    await _save(silent: true);
    final s = app.settings;
    final path = await HtmlExporter(app.workspace!).export(
      project,
      _exportDirBase(),
      includeToc: _includeToc,
      numbering: s.exportHeadingNumbering,
      tts: s.enableExportTts,
      ttsSpeed: s.exportTtsSpeed,
      optimize: s.enableExportOptimization,
      jpegQuality: s.exportJpegQuality,
      maxDimension: s.exportMaxDimension,
      articleFontSize: s.articleFontSize,
      themeCss: await app.workspace!.readThemeCss(project.themeCssFileName),
    );
    _snack(L.t('html_exported'), folderPath: path);
  }

  Future<void> _exportMd() async {
    await _save(silent: true);
    final outDir =
        '${app.workspace!.workspacePath}${Platform.pathSeparator}exports';
    final path = await MarkdownIo.exportToFile(project, outDir,
        numbering: app.settings.exportHeadingNumbering);
    _snack(L.t('md_exported'), folderPath: File(path).parent.path);
  }

  // ---------- テーマ ----------

  Future<void> _openThemeMenu(Offset globalPos) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
          globalPos & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        CheckedPopupMenuItem(
          value: '',
          checked: project.themeCssFileName.isEmpty,
          child: Text(L.t('theme_none')),
        ),
        for (final f in _themeFiles)
          CheckedPopupMenuItem(
            value: f,
            checked: project.themeCssFileName == f,
            child: Text(f),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(value: '__gen__', child: Text('${L.t('theme_generator')}...')),
      ],
    );
    if (selected == null || !mounted) return;
    if (selected == '__gen__') {
      final fileName =
          await showThemeGeneratorDialog(context, app, project.name);
      if (fileName != null) {
        await _loadThemes();
        setState(() {
          project.themeCssFileName = fileName;
          _dirty = true;
        });
        _snack(L.t('theme_saved', [fileName]));
      }
    } else {
      setState(() {
        project.themeCssFileName = selected;
        _dirty = true;
      });
    }
  }

  // ---------- 画像・AI ----------

  Future<void> _attachImage() async {
    final sel = _selected;
    if (sel == null) return;
    final relative = await _pickImageToProject();
    if (relative == null) return;
    setState(() {
      sel.imagePath = relative;
      _dirty = true;
    });
  }

  Future<String?> _pickImageToProject() async {
    const typeGroup = XTypeGroup(
        label: 'image',
        extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return null;
    return app.workspace!.importImage(project.id, file.path);
  }

  Future<void> _editImage() async {
    final sel = _selected;
    if (sel == null || sel.imagePath.isEmpty) return;
    final absolute =
        app.workspace!.resolveImagePath(project.id, sel.imagePath);
    final bytes = await showImageEditorDialog(context, absolute);
    if (bytes == null) return;
    final relative =
        await app.workspace!.importImageBytes(project.id, bytes);
    setState(() {
      sel.imagePath = relative;
      _dirty = true;
    });
  }

  Future<void> _importIntoTree(String kind) async {
    ManidocProject imported;
    try {
      switch (kind) {
        case 'md':
          const typeGroup =
              XTypeGroup(label: 'Markdown', extensions: ['md', 'markdown', 'txt']);
          final file = await openFile(acceptedTypeGroups: [typeGroup]);
          if (file == null) return;
          imported = MarkdownIo.importAsProject(
              file.name, await File(file.path).readAsString());
        case 'html':
          const typeGroup =
              XTypeGroup(label: 'HTML', extensions: ['html', 'htm']);
          final file = await openFile(acceptedTypeGroups: [typeGroup]);
          if (file == null) return;
          imported = await HtmlImport.importHtmlFile(app.workspace!, file.path);
          await _adoptImages(imported);
        case 'web':
          final url = await _askUrl();
          if (url == null) return;
          imported = await HtmlImport.importUrl(app.workspace!, url);
          await _adoptImages(imported);
        default:
          return;
      }
    } catch (e) {
      _snack(L.t('import_failed', [e]));
      return;
    }
    setState(() {
      final sel = _selected;
      if (sel == null) {
        project.rootNodes.addAll(imported.rootNodes);
      } else {
        sel.children.addAll(imported.rootNodes);
        sel.isExpanded = true;
      }
      _dirty = true;
    });
  }

  Future<void> _adoptImages(ManidocProject imported) async {
    final srcDir = Directory(app.workspace!.imagesDirPath(imported.id));
    if (!await srcDir.exists()) return;
    final destDir = Directory(app.workspace!.imagesDirPath(project.id));
    await destDir.create(recursive: true);
    await for (final entity in srcDir.list()) {
      if (entity is File) {
        final name = entity.uri.pathSegments.last;
        await entity.copy('${destDir.path}${Platform.pathSeparator}$name');
      }
    }
    await srcDir.parent.delete(recursive: true);
  }

  Future<String?> _askUrl() async {
    final controller = TextEditingController(text: 'https://');
    return showDialog<String>(
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
  }

  Future<void> _generateAiImage() async {
    final sel = _selected;
    if (sel == null || _generatingImage) return;
    final prompt = _aiPromptController.text.trim();
    if (prompt.isEmpty) {
      _snack(L.t('ai_prompt_empty'));
      return;
    }
    setState(() => _generatingImage = true);
    try {
      final bytes = await app.ai.generateImage(prompt);
      final relative =
          await app.workspace!.importImageBytes(project.id, bytes);
      setState(() {
        sel.imagePath = relative;
        _dirty = true;
      });
      _snack(L.t('ai_image_done'));
    } catch (e) {
      _snack('$e');
    } finally {
      setState(() => _generatingImage = false);
    }
  }

  Future<void> _aiAssist({required bool forComment}) async {
    final sel = _selected;
    if (sel == null) return;
    final original = forComment ? sel.comment : sel.article;
    final result = await showAiAssistantDialog(context, app, original);
    if (result == null) return;
    setState(() {
      if (forComment) {
        sel.comment = result;
        _commentController.text = result;
      } else {
        sel.article = result;
        _articleController.text = result;
      }
      _dirty = true;
    });
  }

  Future<void> _expandedEdit({required bool forComment}) async {
    final sel = _selected;
    if (sel == null) return;
    final result = await showExpandedEditDialog(
        context,
        forComment ? L.t('comment_label') : L.t('expanded_article'),
        forComment ? sel.comment : sel.article);
    if (result == null) return;
    setState(() {
      if (forComment) {
        sel.comment = result;
        _commentController.text = result;
      } else {
        sel.article = result;
        _articleController.text = result;
      }
      _dirty = true;
    });
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        await _save(silent: true);
        navigator.pop();
      },
      child: Scaffold(
        body: Column(
          children: [
            _buildToolbar(context),
            const Divider(height: 1),
            Expanded(
              child: _showMindMap
                  ? _buildMindMap(context)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                            width: _treeWidth,
                            child: _buildTreePanel(context)),
                        _buildSplitter((dx) => setState(() => _treeWidth =
                            (_treeWidth + dx).clamp(200.0, 500.0))),
                        Expanded(child: _buildEditPanel(context)),
                        _buildSplitter((dx) => setState(() => _previewWidth =
                            (_previewWidth - dx).clamp(240.0, 800.0))),
                        SizedBox(
                            width: _previewWidth,
                            child: _buildPreviewPanel(context)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMindMap(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Text(L.t('mindmap_title'),
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: MindMapView(
            rootNodes: project.rootNodes,
            selected: _selected,
            onSelect: (node) {
              _expandAncestors(node);
              _select(node);
              setState(() => _showMindMap = false);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSplitter(void Function(double dx) onDrag) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: Container(
          width: 6,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final provider = app.settings.effectiveAIProvider;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(L.t('back')),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: () => _save(),
            child: Text('${L.t('save')}${_dirty ? ' *' : ''}'),
          ),
          const SizedBox(width: 4),
          TextButton(onPressed: _reload, child: Text(L.t('reload'))),
          _toolbarDivider(),
          // ビュー
          _MindMapButton(active: _showMindMap, onTap: () {
            setState(() => _showMindMap = !_showMindMap);
          }),
          Builder(
            builder: (btnContext) => TextButton(
              onPressed: () {
                final box = btnContext.findRenderObject()! as RenderBox;
                final pos = box.localToGlobal(box.size.bottomLeft(Offset.zero));
                _openThemeMenu(pos);
              },
              child: Text(L.t('theme_menu')),
            ),
          ),
          _toolbarDivider(),
          // AI
          Text(L.t('ai_label'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 6),
          DropdownButton<String>(
            value: app.settings.aiProvider,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem(value: 'None', child: Text(L.t('ai_none'))),
              const DropdownMenuItem(value: 'Gemini', child: Text('Gemini')),
              DropdownMenuItem(
                  value: 'LocalLLM', child: Text(L.isJa ? 'ローカルLLM' : 'Local LLM')),
            ],
            onChanged: (v) {
              app.settings.aiProvider = v!;
              app.saveSettings();
              setState(() {});
            },
          ),
          if (provider == 'None')
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Tooltip(
                message: L.t('ai_unset_tip'),
                child: Icon(Icons.warning_amber,
                    size: 16, color: Theme.of(context).colorScheme.error),
              ),
            ),
          _toolbarDivider(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _includeToc,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => setState(() => _includeToc = v ?? true),
              ),
              Text(L.t('include_toc'), style: const TextStyle(fontSize: 13)),
            ],
          ),
          const SizedBox(width: 4),
          TextButton(onPressed: _exportHtml, child: Text(L.t('html_export'))),
          TextButton(onPressed: _exportMd, child: Text(L.t('md_export'))),
          const Spacer(),
          Flexible(
            child: Text(project.name,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: L.t('toggle_theme'),
            iconSize: 20,
            icon: Icon(app.themeMode == ThemeMode.dark
                ? Icons.light_mode
                : Icons.dark_mode),
            onPressed: app.toggleTheme,
          ),
        ],
      ),
    );
  }

  Widget _toolbarDivider() => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: Theme.of(context).colorScheme.outlineVariant,
      );

  Widget _buildTreePanel(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(L.t('doc_structure'),
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: L.t('search_hint'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onChanged: _runSearch,
                  onSubmitted: (_) => _jumpSearch(1),
                ),
              ),
              IconButton(
                  tooltip: L.t('prev'),
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: () => _jumpSearch(-1)),
              IconButton(
                  tooltip: L.t('next'),
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: () => _jumpSearch(1)),
            ],
          ),
          const SizedBox(height: 4),
          // 置換行
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _replaceController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: L.t('replace_hint'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              OutlinedButton(
                onPressed: _searchIndex >= 0 ? _replaceOne : null,
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Text(L.t('replace')),
              ),
              const SizedBox(width: 4),
              OutlinedButton(
                onPressed: _searchHits.isNotEmpty ? _replaceAll : null,
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Text(L.t('replace_all')),
              ),
            ],
          ),
          if (_searchController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Text(
                _searchHits.isEmpty
                    ? L.t('no_match')
                    : L.t('match_count',
                        [_searchIndex + 1 > 0 ? _searchIndex + 1 : '-', _searchHits.length]),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(children: _buildTreeItems(project.rootNodes, 0)),
          ),
          const Divider(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 2,
            children: [
              _treeButton('↑', L.t('move_up'), () => _moveVertical(-1)),
              _treeButton('↓', L.t('move_down'), () => _moveVertical(1)),
              _treeButton('←', L.t('promote'), _promote),
              _treeButton('→', L.t('demote'), _demote),
              GestureDetector(
                onSecondaryTapDown: (details) async {
                  final overlay = Overlay.of(context)
                      .context
                      .findRenderObject()! as RenderBox;
                  final kind = await showMenu<String>(
                    context: context,
                    position: RelativeRect.fromRect(
                      details.globalPosition & const Size(1, 1),
                      Offset.zero & overlay.size,
                    ),
                    items: [
                      PopupMenuItem(value: 'md', child: Text(L.t('add_from_md'))),
                      PopupMenuItem(
                          value: 'html', child: Text(L.t('add_from_html'))),
                      PopupMenuItem(
                          value: 'web', child: Text(L.t('add_from_web'))),
                    ],
                  );
                  if (kind != null) await _importIntoTree(kind);
                },
                child: OutlinedButton(
                    onPressed: () => _addNode(),
                    child: Text(L.t('add_node'))),
              ),
              OutlinedButton(
                  onPressed: () => _addNode(asChild: true),
                  child: Text(L.t('add_child'))),
              OutlinedButton(
                onPressed: _deleteSelected,
                style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                child: Text(L.t('delete_node_btn')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _treeButton(String label, String tooltip, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(38, 36),
            padding: const EdgeInsets.symmetric(horizontal: 8)),
        child: Text(label),
      ),
    );
  }

  List<Widget> _buildTreeItems(List<ManidocNode> nodes, int depth) {
    final items = <Widget>[];
    for (final node in nodes) {
      items.add(_buildTreeRow(node, depth));
      if (node.isExpanded) {
        items.addAll(_buildTreeItems(node.children, depth + 1));
      }
    }
    return items;
  }

  Widget _buildTreeRow(ManidocNode node, int depth) {
    final selected = identical(node, _selected);
    final isHit = _searchHits.contains(node);
    final isDropTarget = identical(node, _dropTarget);

    final row = InkWell(
      onTap: () => _select(node),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : isHit
                  ? Theme.of(context)
                      .colorScheme
                      .tertiaryContainer
                      .withValues(alpha: 0.5)
                  : null,
          borderRadius: BorderRadius.circular(4),
          border: isDropTarget && _dropZone == 'child'
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary, width: 2)
              : Border(
                  top: BorderSide(
                    color: isDropTarget && _dropZone == 'before'
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                  bottom: BorderSide(
                    color: isDropTarget && _dropZone == 'after'
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
        ),
        padding: EdgeInsets.only(left: 4.0 + depth * 16, top: 4, bottom: 4),
        child: Row(
          children: [
            if (node.children.isNotEmpty)
              GestureDetector(
                onTap: () =>
                    setState(() => node.isExpanded = !node.isExpanded),
                child: Icon(
                  node.isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                ),
              )
            else
              const SizedBox(width: 18),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                node.title.isEmpty ? (L.isJa ? '(無題)' : '(untitled)') : node.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // ドラッグ元 + ドロップ先
    return Draggable<ManidocNode>(
      data: node,
      onDragEnd: (_) => setState(() => _dropTarget = null),
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(node.title.isEmpty ? '(untitled)' : node.title),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: row),
      child: DragTarget<ManidocNode>(
        onWillAcceptWithDetails: (details) =>
            !identical(details.data, node) &&
            !_isDescendant(details.data, node),
        onMove: (details) {
          // 行内の縦位置で before/child/after を判定
          var zone = 'child';
          final rowBox =
              _rowKey(node).currentContext?.findRenderObject() as RenderBox?;
          if (rowBox != null) {
            final p = rowBox.globalToLocal(details.offset);
            final h = rowBox.size.height;
            if (p.dy < h * 0.3) {
              zone = 'before';
            } else if (p.dy > h * 0.7) {
              zone = 'after';
            }
          }
          if (!identical(_dropTarget, node) || _dropZone != zone) {
            setState(() {
              _dropTarget = node;
              _dropZone = zone;
            });
          }
        },
        onLeave: (_) {
          if (identical(_dropTarget, node)) {
            setState(() => _dropTarget = null);
          }
        },
        onAcceptWithDetails: (details) {
          _moveByDrag(details.data, node, _dropZone);
          setState(() => _dropTarget = null);
        },
        builder: (context, candidate, rejected) =>
            Container(key: _rowKey(node), child: row),
      ),
    );
  }

  final Map<String, GlobalKey> _rowKeys = {};
  GlobalKey _rowKey(ManidocNode node) =>
      _rowKeys.putIfAbsent(node.id, () => GlobalKey());

  Widget _buildEditPanel(BuildContext context) {
    final sel = _selected;
    if (sel == null) {
      return Center(child: Text(L.t('select_node_hint')));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L.t('title_label'), style: _labelStyle(context)),
          const SizedBox(height: 6),
          TextField(
            controller: _titleController,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
                border: OutlineInputBorder(), isDense: true),
            onChanged: (v) => setState(() {
              sel.title = v;
              _dirty = true;
            }),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(L.t('article_label'), style: _labelStyle(context)),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () => _aiAssist(forComment: false),
                style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                child: Text(L.t('ai_assistant')),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _expandedEdit(forComment: false),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                child: Text(L.t('expanded_edit')),
              ),
              const Spacer(),
              Tooltip(
                message: L.t('bigger'),
                child: TextButton(
                    onPressed: () => _changeFontSize(1),
                    child: const Text('A+')),
              ),
              Tooltip(
                message: L.t('smaller'),
                child: TextButton(
                    onPressed: () => _changeFontSize(-1),
                    child: const Text('A-')),
              ),
              TextButton(
                  onPressed: () => _changeFontSize(0),
                  child: Text(L.t('reset'))),
            ],
          ),
          const SizedBox(height: 6),
          MarkdownToolbar(
            controller: _articleController,
            onChanged: () => setState(() {
              sel.article = _articleController.text;
              _dirty = true;
            }),
            onPickImage: _pickImageToProject,
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _articleController,
            maxLines: 10,
            minLines: 6,
            style: TextStyle(
                fontFamily: 'monospace',
                fontSize: app.settings.articleFontSize),
            decoration: InputDecoration(
              hintText: L.t('article_hint'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() {
              sel.article = v;
              _dirty = true;
            }),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(L.t('ai_image_prompt'), style: _labelStyle(context)),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: _generatingImage ? null : _generateAiImage,
                style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                child: _generatingImage
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(L.t('ai_generate_image')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _aiPromptController,
            maxLines: 2,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: L.t('ai_image_hint'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() {
              sel.aiPrompt = v;
              _dirty = true;
            }),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(L.t('image_label'), style: _labelStyle(context)),
              const SizedBox(width: 12),
              if (sel.imagePath.isNotEmpty)
                OutlinedButton(
                  onPressed: _editImage,
                  style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  child: Text(L.t('edit_image')),
                ),
              if (sel.imagePath.isNotEmpty) const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _attachImage,
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                child: Text(L.t('select_image')),
              ),
              const SizedBox(width: 8),
              if (sel.imagePath.isNotEmpty)
                OutlinedButton(
                  onPressed: () => setState(() {
                    sel.imagePath = '';
                    _dirty = true;
                  }),
                  style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Theme.of(context).colorScheme.error),
                  child: Text(L.t('clear')),
                ),
              const SizedBox(width: 8),
              if (sel.imagePath.isNotEmpty)
                Expanded(
                  child: Text(sel.imagePath,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 120, maxHeight: 320),
            decoration: BoxDecoration(
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: sel.imagePath.isEmpty
                ? Center(
                    child: Text(L.t('no_image'),
                        style: Theme.of(context).textTheme.bodySmall))
                : Padding(
                    padding: const EdgeInsets.all(8),
                    child: _previewImage(sel),
                  ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(L.t('comment_label'), style: _labelStyle(context)),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () => _aiAssist(forComment: true),
                style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                child: Text(L.t('ai_assistant')),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _expandedEdit(forComment: true),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                child: Text(L.t('expanded_edit')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _commentController,
            maxLines: 4,
            minLines: 3,
            style: TextStyle(fontSize: app.settings.articleFontSize),
            decoration: InputDecoration(
              hintText: L.t('comment_hint'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() {
              sel.comment = v;
              _dirty = true;
            }),
          ),
        ],
      ),
    );
  }

  TextStyle? _labelStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .labelLarge
      ?.copyWith(fontWeight: FontWeight.bold);

  void _changeFontSize(int delta) {
    setState(() {
      app.settings.articleFontSize = delta == 0
          ? 14.0
          : (app.settings.articleFontSize + delta * 1.5).clamp(10.0, 28.0);
    });
    app.settings.save();
  }

  Widget _buildPreviewPanel(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final config =
        isDark ? MarkdownConfig.darkConfig : MarkdownConfig.defaultConfig;
    final sections = <Widget>[];
    _previewKeys.clear();

    void walk(List<ManidocNode> nodes, int depth, String numberPrefix) {
      var index = 1;
      for (final node in nodes) {
        final number =
            numberPrefix.isEmpty ? '$index' : '$numberPrefix.$index';
        final selected = identical(node, _selected);
        final key = GlobalKey();
        _previewKeys[node.id] = key;
        sections.add(Container(
          key: key,
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(8),
          decoration: selected
              ? BoxDecoration(
                  border: Border.all(
                      color: Theme.of(context).colorScheme.primary, width: 2),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                app.settings.exportHeadingNumbering
                    ? '$number. ${node.title}'
                    : node.title,
                style: TextStyle(
                  fontSize: (22.0 - depth * 2).clamp(15.0, 22.0),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (node.article.trim().isNotEmpty)
                MarkdownBlock(data: node.article, config: config),
              if (node.imagePath.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: _previewImage(node),
                ),
              if (node.comment.trim().isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF2A2618)
                        : const Color(0xFFFFF8E1),
                    border: const Border(
                        left: BorderSide(color: Color(0xFFFFCA28), width: 4)),
                  ),
                  child: MarkdownBlock(data: node.comment, config: config),
                ),
            ],
          ),
        ));
        walk(node.children, depth + 1, number);
        index++;
      }
    }

    walk(project.rootNodes, 0, '');

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Row(
              children: [
                Text(L.t('realtime_preview'),
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${(_zoom * 100).round()}%',
                    style: Theme.of(context).textTheme.bodySmall),
                SizedBox(
                  width: 110,
                  child: Slider(
                    value: _zoom,
                    min: 0.5,
                    max: 1.5,
                    divisions: 20,
                    onChanged: (v) => setState(() => _zoom = v),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(_zoom)),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: sections,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewImage(ManidocNode node) {
    final path = app.workspace!.resolveImagePath(project.id, node.imagePath);
    final file = File(path);
    if (!file.existsSync()) {
      return Text(L.t('image_not_found', [node.imagePath]),
          style: TextStyle(color: Theme.of(context).colorScheme.error));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(file, key: ValueKey('$path${file.lengthSync()}')),
    );
  }
}

/// マインドマップ切替トグル
class _MindMapButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _MindMapButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return active
        ? FilledButton.tonal(onPressed: onTap, child: Text(L.t('mindmap')))
        : TextButton(onPressed: onTap, child: Text(L.t('mindmap')));
  }
}
