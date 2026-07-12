import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';

/// `[[` などから呼ぶノード選択ダイアログ。
/// プロジェクト内の全ノードを一覧表示し、選んだノードの id/title を返す。
Future<({String id, String title})?> showNodePickerDialog(
    BuildContext context, ManidocProject project,
    {ManidocNode? exclude}) {
  // 深さ優先で (番号, ノード) の平坦リストを作る
  final flat = <({String number, ManidocNode node})>[];
  void walk(List<ManidocNode> nodes, String prefix) {
    var i = 1;
    for (final node in nodes) {
      final number = prefix.isEmpty ? '$i' : '$prefix.$i';
      if (!identical(node, exclude)) {
        flat.add((number: number, node: node));
      }
      walk(node.children, number);
      i++;
    }
  }

  walk(project.rootNodes, '');

  return showDialog<({String id, String title})>(
    context: context,
    builder: (context) => _NodePicker(entries: flat),
  );
}

class _NodePicker extends StatefulWidget {
  final List<({String number, ManidocNode node})> entries;
  const _NodePicker({required this.entries});

  @override
  State<_NodePicker> createState() => _NodePickerState();
}

class _NodePickerState extends State<_NodePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.entries
        : widget.entries
            .where((e) => e.node.title.toLowerCase().contains(q))
            .toList();
    return AlertDialog(
      title: Text(L.t('node_link_title')),
      content: SizedBox(
        width: 460,
        height: 440,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: L.t('node_link_search'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text(L.t('no_match')))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final e = filtered[i];
                        return ListTile(
                          dense: true,
                          leading: Text(e.number,
                              style: Theme.of(context).textTheme.bodySmall),
                          title: Text(
                            e.node.title.isEmpty
                                ? (L.isJa ? '(無題)' : '(untitled)')
                                : e.node.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(
                              context,
                              (
                                id: e.node.id,
                                title: e.node.title.isEmpty
                                    ? e.node.id
                                    : e.node.title
                              )),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L.t('cancel'))),
      ],
    );
  }
}
