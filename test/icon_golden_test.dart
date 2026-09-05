import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Generates the launcher-icon PNGs under `assets/icon/` using Flutter's own
/// renderer, so the artwork is code (no external design tool needed).
///
/// Regenerate after changing the painter with:
///   flutter test --update-goldens test/icon_golden_test.dart
///   dart run flutter_launcher_icons
///
/// The drawing is pure vector (no text/fonts), so the goldens are stable and
/// the comparisons pass on normal `flutter test` runs.
void main() {
  Future<void> render(WidgetTester tester, Widget child, String golden) async {
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(RepaintBoundary(child: child));
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile(golden),
    );
  }

  testWidgets('app icon (legacy, full bleed)', (tester) async {
    await render(
      tester,
      const CustomPaint(painter: _IconPainter(background: true, scale: 1.0)),
      '../assets/icon/app_icon.png',
    );
  });

  testWidgets('app icon (adaptive foreground, transparent)', (tester) async {
    // Adaptive icons mask to the inner ~66% of the canvas; shrink the artwork
    // so nothing important is clipped.
    await render(
      tester,
      const CustomPaint(painter: _IconPainter(background: false, scale: 0.72)),
      '../assets/icon/app_icon_foreground.png',
    );
  });
}

/// Player-wheel launcher icon: four color sectors (the players), white
/// separators, and a white hub with a "next turn" arrow.
class _IconPainter extends CustomPainter {
  const _IconPainter({required this.background, required this.scale});

  final bool background;
  final double scale;

  static const Color navy = Color(0xFF1E2A44);
  static const List<Color> sectors = [
    Color(0xFFE53935), // red
    Color(0xFFFDD835), // amber
    Color(0xFF43A047), // green
    Color(0xFF1E88E5), // blue
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(s / 2, s / 2);

    if (background) {
      canvas.drawRect(Offset.zero & size, Paint()..color = navy);
    }

    final wheelR = 0.40 * s * scale;
    final rect = Rect.fromCircle(center: c, radius: wheelR);

    // Four 90° sectors, rotated 45° so colors sit on the diagonals.
    for (var i = 0; i < 4; i++) {
      final start = (-45 + 90 * i) * math.pi / 180;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(rect, start, math.pi / 2, false)
        ..close();
      canvas.drawPath(path, Paint()..color = sectors[i]);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.035 * s * scale
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // White hub.
    final hubR = 0.175 * s * scale;
    canvas.drawCircle(c, hubR, Paint()..color = Colors.white);

    // Navy "next turn" play arrow, nudged right so it looks centered.
    final a = hubR * 0.52;
    final arrow = Path()
      ..moveTo(c.dx - a * 0.62, c.dy - a)
      ..lineTo(c.dx + a * 0.95, c.dy)
      ..lineTo(c.dx - a * 0.62, c.dy + a)
      ..close();
    canvas.drawPath(arrow, Paint()..color = navy);
  }

  @override
  bool shouldRepaint(covariant _IconPainter old) =>
      old.background != background || old.scale != scale;
}
