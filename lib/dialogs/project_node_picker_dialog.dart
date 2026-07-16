import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';

/// 「他のプロジェクトからノードを追加」用の選択ダイアログ(本家NodeImportDialog準拠)。
/// プロジェクトを選び、そのノードツリーから1ノード(サブツリー)を選んで返す。
Future<({ManidocProject project, ManidocNode node})?>
    showProjectNodePickerDialog(
        BuildContext context, List<ManidocProject> projects) {
  return showDialog<({ManidocProject project, ManidocNode node})>(
    context: context,
    builder: (context) => _ProjectNodePicker(projects: projects),
  );
}

class _ProjectNodePicker extends StatefulWidget {
  final List<ManidocProject> projects;
  const _ProjectNodePicker({required this.projects});

  @override
  State<_ProjectNodePicker> createState() => _ProjectNodePickerState();
}

class _ProjectNodePickerState extends State<_ProjectNodePicker> {
  late ManidocProject _project = widget.projects.first;
  String _query = '';

  List<({String number, ManidocNode node})> _flatten() {
    final flat = <({String number, ManidocNode node})>[];
    void walk(List<ManidocNode> nodes, String prefix) {
      var i = 1;
      for (final node in nodes) {
        final number = prefix.isEmpty ? '$i' : '$prefix.$i';
        flat.add((number: number, node: node));
        walk(node.children, number);
        i++;
      }
    }

    walk(_project.rootNodes, '');
    return flat;
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final entries = _flatten();
    final filtered = q.isEmpty
        ? entries
        : entries
            .where((e) => e.node.title.toLowerCase().contains(q))
            .toList();
    return AlertDialog(
      title: Text(L.t('import_from_project')),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<ManidocProject>(
              initialValue: _project,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: L.t('ifp_pick_project'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final p in widget.projects)
                  DropdownMenuItem(value: p, child: Text(p.name)),
              ],
              onChanged: (p) => setState(() => _project = p!),
            ),
            const SizedBox(height: 8),
            TextField(
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
                          subtitle: e.node.children.isEmpty
                              ? null
                              : Text(
                                  L.t('ifp_with_children',
                                      [e.node.children.length]),
                                  style:
                                      Theme.of(context).textTheme.bodySmall),
                          onTap: () => Navigator.pop(
                              context, (project: _project, node: e.node)),
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
