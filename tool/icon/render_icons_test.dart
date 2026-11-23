// Draws the IRCade app icon and writes 1024-px masters to build/icons.
// Run through tool/make_icons.sh, which then resizes them for each
// platform. This file is the icon's source of truth.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _top = Color(0xFF7474FF);
const _bottom = Color(0xFF4141D8);
const _hash = Color(0xFF5B5BF0);

/// The white chat bubble with its tail at the bottom left, on a
/// 1024-unit canvas.
Path _bubble() => Path()
  ..moveTo(362, 232)
  ..lineTo(662, 232)
  ..arcToPoint(const Offset(812, 382), radius: const Radius.circular(150))
  ..lineTo(812, 562)
  ..arcToPoint(const Offset(662, 712), radius: const Radius.circular(150))
  ..lineTo(430, 712)
  ..lineTo(280, 822)
  ..lineTo(310, 700)
  ..arcToPoint(const Offset(212, 562), radius: const Radius.circular(150))
  ..lineTo(212, 382)
  ..arcToPoint(const Offset(362, 232), radius: const Radius.circular(150))
  ..close();

/// The bubble and the slanted IRC `#`.
void _glyph(Canvas c) {
  c.drawPath(_bubble(), Paint()..color = const Color(0xFFFFFFFF));
  final pen = Paint()
    ..color = _hash
    ..strokeWidth = 56
    ..strokeCap = StrokeCap.round;
  c
    ..drawLine(const Offset(462, 330), const Offset(432, 614), pen)
    ..drawLine(const Offset(602, 330), const Offset(572, 614), pen)
    ..drawLine(const Offset(362, 420), const Offset(672, 420), pen)
    ..drawLine(const Offset(352, 524), const Offset(662, 524), pen);
}

Paint _gradient(Rect r) =>
    Paint()
      ..shader = ui.Gradient.linear(r.topLeft, r.bottomRight, [_top, _bottom]);

Future<void> _write(String name, void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final image = await recorder.endRecording().toImage(1024, 1024);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  File('build/icons/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  test('render icons', () async {
    const full = Rect.fromLTWH(0, 0, 1024, 1024);

    // iOS: full bleed (iOS rounds the corners).
    await _write('ios', (c) {
      c.drawRect(full, _gradient(full));
      _glyph(c);
    });

    // macOS: an 824-px rounded square with a soft shadow.
    await _write('macos', (c) {
      const tile = Rect.fromLTWH(100, 100, 824, 824);
      final shape = RRect.fromRectAndRadius(tile, const Radius.circular(185));
      c
        ..drawRRect(
          shape.shift(const Offset(0, 10)),
          Paint()
            ..color = const Color(0x47000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
        )
        ..save()
        ..clipRRect(shape)
        ..drawRect(tile, _gradient(tile))
        ..translate(100, 100)
        ..scale(824 / 1024);
      _glyph(c);
      c.restore();
    });

    // Android before adaptive icons: a rounded square.
    await _write('legacy', (c) {
      const tile = Rect.fromLTWH(32, 32, 960, 960);
      c
        ..save()
        ..clipRRect(RRect.fromRectAndRadius(tile, const Radius.circular(200)))
        ..drawRect(tile, _gradient(tile))
        ..translate(32, 32)
        ..scale(960 / 1024);
      _glyph(c);
      c.restore();
    });

    // Android adaptive foreground: the bubble inside the 72dp safe zone
    // of the 108dp canvas, on transparent.
    await _write('foreground', (c) {
      c
        ..translate(512, 527)
        ..scale(0.72)
        ..translate(-512, -527);
      _glyph(c);
    });
  });
}
