import 'package:flutter/material.dart';

import '../models/manidoc_node.dart';

/// ノードツリーをマインドマップ状に可視化する。
/// プロジェクト名を単一のルートとし、各ルートノードをその子として配置する。
/// 各ノードは深さ(列)×リーフ順(行)に配置し、親子を曲線で結ぶ。
/// ノードをタップすると onSelect が呼ばれる(プロジェクト名ルートは選択不可)。
class MindMapView extends StatelessWidget {
  final String projectName;
  final List<ManidocNode> rootNodes;
  final ManidocNode? selected;
  final void Function(ManidocNode node) onSelect;

  const MindMapView({
    super.key,
    required this.projectName,
    required this.rootNodes,
    required this.selected,
    required this.onSelect,
  });

  static const double _colW = 210;
  static const double _rowH = 56;
  static const double _boxW = 180;
  static const double _boxH = 40;

  @override
  Widget build(BuildContext context) {
    final positions = <ManidocNode, Offset>{};
    final edges = <(ManidocNode, ManidocNode)>[];
    var leafRow = 0;

    // 深さ優先でy座標を割り当て(親は子の中央)
    double layout(ManidocNode node, int depth) {
      final x = depth * _colW;
      double y;
      if (node.children.isEmpty) {
        y = leafRow * _rowH;
        leafRow++;
      } else {
        final childYs = <double>[];
        for (final child in node.children) {
          childYs.add(layout(child, depth + 1));
          edges.add((node, child));
        }
        y = (childYs.first + childYs.last) / 2;
      }
      positions[node] = Offset(x, y);
      return y;
    }

    // プロジェクト名を単一のルートにし、各ルートノードをその子として繋ぐ。
    // (このノードは表示・配線専用の一時オブジェクト。保存には影響しない)
    final projectRoot = ManidocNode(
      title: projectName.isEmpty ? '(無題)' : projectName,
      children: rootNodes,
    );
    layout(projectRoot, 0);

    if (rootNodes.isEmpty) {
      return const Center(child: Text('項目がありません'));
    }

    final maxX =
        positions.values.map((o) => o.dx).reduce((a, b) => a > b ? a : b);
    final maxY =
        positions.values.map((o) => o.dy).reduce((a, b) => a > b ? a : b);
    final width = maxX + _boxW + 40;
    final height = maxY + _boxH + 40;
    final lineColor = Theme.of(context).colorScheme.outline;

    return InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.all(200),
      minScale: 0.3,
      maxScale: 2.0,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            // 接続線
            Positioned.fill(
              child: CustomPaint(
                painter: _EdgePainter(
                  positions: positions,
                  edges: edges,
                  boxW: _boxW,
                  boxH: _boxH,
                  color: lineColor,
                ),
              ),
            ),
            // ノード
            for (final entry in positions.entries)
              Positioned(
                left: entry.value.dx + 20,
                top: entry.value.dy + 20,
                width: _boxW,
                height: _boxH,
                child: _MindNode(
                  node: entry.key,
                  selected: identical(entry.key, selected),
                  isRoot: identical(entry.key, projectRoot),
                  onTap: identical(entry.key, projectRoot)
                      ? null
                      : () => onSelect(entry.key),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MindNode extends StatelessWidget {
  final ManidocNode node;
  final bool selected;
  final bool isRoot;
  final VoidCallback? onTap;

  const _MindNode(
      {required this.node,
      required this.selected,
      this.isRoot = false,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // プロジェクト名ルートは強調(primaryContainer + 太字)。選択中は従来通り。
    final Color bg = selected
        ? scheme.primary
        : isRoot
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest;
    final Color fg = selected
        ? scheme.onPrimary
        : isRoot
            ? scheme.onPrimaryContainer
            : scheme.onSurface;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      elevation: selected ? 4 : (isRoot ? 2 : 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Center(
            child: Text(
              node.title.isEmpty ? '(無題)' : node.title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: fg,
                fontWeight:
                    (selected || isRoot) ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  final Map<ManidocNode, Offset> positions;
  final List<(ManidocNode, ManidocNode)> edges;
  final double boxW;
  final double boxH;
  final Color color;

  _EdgePainter({
    required this.positions,
    required this.edges,
    required this.boxW,
    required this.boxH,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final (parent, child) in edges) {
      final p = positions[parent]!;
      final c = positions[child]!;
      // 親の右辺中央 → 子の左辺中央 をベジェで結ぶ
      final start = Offset(p.dx + 20 + boxW, p.dy + 20 + boxH / 2);
      final end = Offset(c.dx + 20, c.dy + 20 + boxH / 2);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          (start.dx + end.dx) / 2, start.dy,
          (start.dx + end.dx) / 2, end.dy,
          end.dx, end.dy,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) => true;
}
