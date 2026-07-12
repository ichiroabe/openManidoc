import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n/strings.dart';
import '../models/tag_definition.dart';

/// 🏷 タグ管理: ワークスペースのタグを 追加/改名/削除/並べ替え/画像設定 する。
/// 本家 TagManagerDialog 準拠(workspace.settings.json の tags[] を編集)。
Future<void> showTagManagerDialog(BuildContext context, AppState app) async {
  // 編集用にコピー
  final tags = [
    for (final t in app.workspaceTags)
      TagDefinition(name: t.name, imagePath: t.imagePath)
  ];

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => _TagManager(tags: tags),
  );
  if (saved == true) {
    await app.saveWorkspaceTags(tags.where((t) => t.name.trim().isNotEmpty).toList());
  }
}

class _TagManager extends StatefulWidget {
  final List<TagDefinition> tags;
  const _TagManager({required this.tags});

  @override
  State<_TagManager> createState() => _TagManagerState();
}

class _TagManagerState extends State<_TagManager> {
  late final List<TagDefinition> _tags = widget.tags;
  final Map<int, TextEditingController> _controllers = {};

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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(L.t('tag_manager_title')),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
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
                                      : const Icon(Icons.image_outlined,
                                          size: 18),
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
    );
  }
}
