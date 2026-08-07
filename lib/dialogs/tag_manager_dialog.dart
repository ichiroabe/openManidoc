import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n/strings.dart';
import '../models/tag_definition.dart';

/// 🏷 タグ管理ダイアログ。2タブ構成:
/// - タグ定義: ワークスペースのタグを 追加/改名/削除/並べ替え/画像設定 する
///   (本家 TagManagerDialog 準拠。workspace.settings.json の tags[] を編集)。
/// - 一括タグ設定: プロジェクトを複数選択して、対象タグへまとめて更新する。
Future<void> showTagManagerDialog(BuildContext context, AppState app) async {
  // タグ定義タブは編集用にコピーを渡し、[保存] 時にまとめて反映する。
  final tags = [
    for (final t in app.workspaceTags)
      TagDefinition(name: t.name, imagePath: t.imagePath)
  ];

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => _TagManager(app: app, tags: tags),
  );
  if (saved == true) {
    await app.saveWorkspaceTags(
        tags.where((t) => t.name.trim().isNotEmpty).toList());
  }
}

class _TagManager extends StatefulWidget {
  final AppState app;
  final List<TagDefinition> tags;
  const _TagManager({required this.app, required this.tags});

  @override
  State<_TagManager> createState() => _TagManagerState();
}

class _TagManagerState extends State<_TagManager> {
  late final List<TagDefinition> _tags = widget.tags;
  final Map<int, TextEditingController> _controllers = {};

  // 一括タグ設定タブの状態
  final Set<String> _selectedProjectIds = {};
  String? _targetTag; // null=未選択, ''=タグを外す, それ以外=タグ名

  TextEditingController _ctrl(int i) => _controllers.putIfAbsent(
      i, () => TextEditingController(text: _tags[i].name));

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _rebuildControllers() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
  }

  void _move(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _tags.length) return;
    setState(() {
      final t = _tags.removeAt(i);
      _tags.insert(j, t);
      _rebuildControllers();
    });
  }

  Future<void> _pickImage(int i) async {
    const typeGroup = XTypeGroup(
        label: 'image', extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    setState(() => _tags[i].imagePath = file.path);
  }

  Future<void> _applyBulk() async {
    final tag = _targetTag;
    if (tag == null) return;
    final targets = widget.app.projects
        .where((p) => _selectedProjectIds.contains(p.id))
        .toList();
    if (targets.isEmpty) return;
    await widget.app.setProjectsTag(targets, tag);
    if (!mounted) return;
    final n = targets.length;
    setState(() => _selectedProjectIds.clear());
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(L.t('tag_bulk_applied', [n]))));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: AlertDialog(
        title: Text(L.t('tag_manager_title')),
        content: SizedBox(
          width: 560,
          height: 500,
          child: Column(
            children: [
              TabBar(
                tabs: [
                  Tab(text: L.t('tag_tab_defs')),
                  Tab(text: L.t('tag_tab_bulk')),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildDefsTab(context),
                    _buildBulkTab(context),
                  ],
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
              child: Text(L.t('save'))),
        ],
      ),
    );
  }

  // --- タグ定義タブ（従来の内容） ---
  Widget _buildDefsTab(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _tags.isEmpty
              ? Center(child: Text(L.t('tag_none_yet')))
              : ListView.builder(
                  itemCount: _tags.length,
                  itemBuilder: (context, i) {
                    final tag = _tags[i];
                    final hasImg = tag.imagePath.isNotEmpty &&
                        File(tag.imagePath).existsSync();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          // 画像サムネイル
                          InkWell(
                            onTap: () => _pickImage(i),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                                image: hasImg
                                    ? DecorationImage(
                                        image: FileImage(File(tag.imagePath)),
                                        fit: BoxFit.cover)
                                    : null,
                              ),
                              child: hasImg
                                  ? null
                                  : const Icon(Icons.image_outlined, size: 18),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _ctrl(i),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => tag.name = v,
                            ),
                          ),
                          IconButton(
                            tooltip: L.t('move_up'),
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.arrow_upward),
                            onPressed: () => _move(i, -1),
                          ),
                          IconButton(
                            tooltip: L.t('move_down'),
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.arrow_downward),
                            onPressed: () => _move(i, 1),
                          ),
                          IconButton(
                            tooltip: L.t('delete'),
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                            color: Theme.of(context).colorScheme.error,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(() {
                              _tags.removeAt(i);
                              _rebuildControllers();
                            }),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => setState(() {
              _tags.add(TagDefinition(name: ''));
              _rebuildControllers();
            }),
            icon: const Icon(Icons.add),
            label: Text(L.t('tag_add')),
          ),
        ),
      ],
    );
  }

  // --- 一括タグ設定タブ ---
  Widget _buildBulkTab(BuildContext context) {
    final app = widget.app;
    final projects = app.projects;
    // 対象タグ候補: 定義済み+使用中のタグ + 「タグを外す」
    final tagOptions = app.allTags;
    _targetTag ??= tagOptions.isNotEmpty ? tagOptions.first : '';

    if (projects.isEmpty) {
      return Center(child: Text(L.t('tag_bulk_no_projects')));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 対象タグ選択
        Row(
          children: [
            Text(L.t('tag_bulk_target')),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _targetTag,
                isDense: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final t in tagOptions)
                    DropdownMenuItem(value: t, child: Text(t)),
                  DropdownMenuItem(
                      value: '',
                      child: Text(
                        L.t('tag_bulk_remove'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline),
                      )),
                ],
                onChanged: (v) => setState(() => _targetTag = v ?? ''),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 全選択/全解除 + 選択件数
        Row(
          children: [
            TextButton.icon(
              icon: const Icon(Icons.select_all, size: 18),
              label: Text(L.t('tag_bulk_select_all')),
              onPressed: () => setState(() {
                _selectedProjectIds
                  ..clear()
                  ..addAll(projects.map((p) => p.id));
              }),
            ),
            TextButton.icon(
              icon: const Icon(Icons.deselect, size: 18),
              label: Text(L.t('tag_bulk_clear')),
              onPressed: () =>
                  setState(() => _selectedProjectIds.clear()),
            ),
            const Spacer(),
            Text(L.t('tag_bulk_selected', [_selectedProjectIds.length]),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 12)),
          ],
        ),
        const Divider(height: 1),
        // プロジェクト一覧(複数選択)
        Expanded(
          child: ListView.builder(
            itemCount: projects.length,
            itemBuilder: (context, i) {
              final p = projects[i];
              final checked = _selectedProjectIds.contains(p.id);
              final currentTag =
                  p.tag.isNotEmpty ? p.tag : L.t('tag_none');
              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: checked,
                title: Text(p.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(currentTag,
                    style: const TextStyle(fontSize: 12)),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selectedProjectIds.add(p.id);
                  } else {
                    _selectedProjectIds.remove(p.id);
                  }
                }),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            icon: const Icon(Icons.local_offer_outlined, size: 18),
            label: Text(L.t('tag_bulk_apply')),
            onPressed:
                _selectedProjectIds.isEmpty ? null : _applyBulk,
          ),
        ),
      ],
    );
  }
}
