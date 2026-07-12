import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';

/// 画像編集: 画像上に枠線(矩形)を描画する。本家ImageEditorWindow準拠。
/// 色は赤・青・緑・黄・橙・黒。全消去可。保存でPNGバイト列を返す(キャンセルはnull)。
Future<List<int>?> showImageEditorDialog(
    BuildContext context, String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  if (!context.mounted) return null;
  return showDialog<List<int>>(
    context: context,
    builder: (context) => _ImageEditorDialog(image: frame.image),
  );
}

class _Stroke {
  final Rect rect;
  final Color color;
  _Stroke(this.rect, this.color);
}

class _ImageEditorDialog extends StatefulWidget {
  final ui.Image image;

  const _ImageEditorDialog({required this.image});

  @override
  State<_ImageEditorDialog> createState() => _ImageEditorDialogState();
}

class _ImageEditorDialogState extends State<_ImageEditorDialog> {
  static const _colors = <(String, Color)>[
    ('赤', Color(0xFFFF3B30)),
    ('青', Color(0xFF0A84FF)),
    ('緑', Color(0xFF34C759)),
    ('黄', Color(0xFFFFCC00)),
    ('橙', Color(0xFFFF9500)),
    ('黒', Color(0xFF000000)),
  ];

  final List<_Stroke> _strokes = [];
  Color _color = _colors.first.$2;
  Offset? _dragStart;
  Rect? _dragRect;

  /// 表示座標→画像座標のスケールを求めるための表示サイズ
  Size _fittedSize(Size available) {
    final iw = widget.image.width.toDouble();
    final ih = widget.image.height.toDouble();
    final scale =
        (available.width / iw).clamp(0.0, available.height / ih);
    return Size(iw * scale, ih * scale);
  }

  Future<void> _saveAndClose() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(widget.image, Offset.zero, Paint());
    // 枠線太さは画像サイズに応じてスケール
    final strokeWidth =
        (widget.image.width / 300).clamp(2.0, 10.0);
    for (final stroke in _strokes) {
      canvas.drawRect(
        stroke.rect,
        Paint()
          ..color = stroke.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
    }
    final picture = recorder.endRecording();
    final rendered =
        await picture.toImage(widget.image.width, widget.image.height);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    Navigator.pop(context, data!.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 980,
        height: 700,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text(L.t('image_editor'),
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 20),
                for (final (label, color) in _colors)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: label,
                      child: InkWell(
                        onTap: () => setState(() => _color = color),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == color
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _strokes.isEmpty
                      ? null
                      : () => setState(() => _strokes.clear()),
                  child: Text(L.t('clear_all')),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  onPressed: _strokes.isEmpty
                      ? null
                      : () => setState(() => _strokes.removeLast()),
                  child: Text(L.t('undo_one')),
                ),
                const Spacer(),
                Text(L.t('drag_to_draw'),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = _fittedSize(
                      Size(constraints.maxWidth, constraints.maxHeight));
                  final scale = size.width / widget.image.width;
                  return Center(
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: GestureDetector(
                        onPanStart: (d) => setState(() {
                          _dragStart = d.localPosition;
                          _dragRect = null;
                        }),
                        onPanUpdate: (d) => setState(() {
                          _dragRect =
                              Rect.fromPoints(_dragStart!, d.localPosition);
                        }),
                        onPanEnd: (_) => setState(() {
                          final r = _dragRect;
                          if (r != null &&
                              r.width > 4 &&
                              r.height > 4) {
                            // 表示座標→画像座標へ変換して保存
                            _strokes.add(_Stroke(
                              Rect.fromLTRB(r.left / scale, r.top / scale,
                                  r.right / scale, r.bottom / scale),
                              _color,
                            ));
                          }
                          _dragStart = null;
                          _dragRect = null;
                        }),
                        child: CustomPaint(
                          painter: _EditorPainter(
                            image: widget.image,
                            strokes: _strokes,
                            scale: scale,
                            dragRect: _dragRect,
                            dragColor: _color,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(L.t('cancel'))),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: _saveAndClose, child: Text(L.t('save'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorPainter extends CustomPainter {
  final ui.Image image;
  final List<_Stroke> strokes;
  final double scale;
  final Rect? dragRect;
  final Color dragColor;

  _EditorPainter({
    required this.image,
    required this.strokes,
    required this.scale,
    required this.dragRect,
    required this.dragColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint(),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final stroke in strokes) {
      paint.color = stroke.color;
      canvas.drawRect(
        Rect.fromLTRB(
            stroke.rect.left * scale,
            stroke.rect.top * scale,
            stroke.rect.right * scale,
            stroke.rect.bottom * scale),
        paint,
      );
    }
    final drag = dragRect;
    if (drag != null) {
      paint.color = dragColor;
      canvas.drawRect(drag, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EditorPainter old) => true;
}
