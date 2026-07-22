// Brand marks drawn in code (no raster assets needed): the Willong "leaf"
// petal and the NQE wordmark with its Narrative · Quality · Execution tagline.
import 'package:flutter/material.dart';
import '../theme.dart';

class LeafMark extends StatelessWidget {
  final double size;
  final Color? color;
  const LeafMark({super.key, this.size = 40, this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _LeafPainter(color ?? context.nqe.textHi),
    );
  }
}

class _LeafPainter extends CustomPainter {
  final Color color;
  _LeafPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // A petal/leaf: rounded top-left, tapering to a point at bottom-right.
    final path = Path()
      ..moveTo(w * 0.12, h * 0.12)
      ..cubicTo(w * 0.75, h * -0.05, w * 1.05, h * 0.28, w * 0.9, h * 0.9)
      ..cubicTo(w * 0.30, h * 1.05, w * -0.05, h * 0.72, w * 0.12, h * 0.12)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LeafPainter old) => old.color != color;
}

/// Large stacked logo for the lock / splash screen.
class NqeLogo extends StatelessWidget {
  final double scale;
  final bool showTagline;
  final Color? color;
  const NqeLogo({super.key, this.scale = 1, this.showTagline = true, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.nqe.textHi;
    final lo = context.nqe.textLo;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'NQE',
              style: TextStyle(
                fontSize: 64 * scale,
                fontWeight: FontWeight.w800,
                letterSpacing: -2,
                color: c,
                height: 1,
              ),
            ),
            SizedBox(width: 8 * scale),
            Padding(
              padding: EdgeInsets.only(top: 18 * scale),
              child: Text(
                'FUND',
                style: TextStyle(
                  fontSize: 22 * scale,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                  color: c,
                ),
              ),
            ),
          ],
        ),
        if (showTagline) ...[
          SizedBox(height: 8 * scale),
          Text(
            'NARRATIVE · QUALITY · EXECUTION',
            style: TextStyle(
              fontSize: 11 * scale,
              letterSpacing: 2,
              color: lo,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// Small "managed by" lockup with the leaf mark.
class WillongByline extends StatelessWidget {
  final double scale;
  final Color? color;
  const WillongByline({super.key, this.scale = 1, this.color});

  @override
  Widget build(BuildContext context) {
    final hi = color ?? context.nqe.textHi;
    final lo = context.nqe.textLo;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LeafMark(size: 20 * scale, color: lo),
        SizedBox(width: 8 * scale),
        Text.rich(
          TextSpan(children: [
            TextSpan(
              text: 'Funds managed by ',
              style: TextStyle(color: lo, fontSize: 12 * scale),
            ),
            TextSpan(
              text: 'WILLONG ',
              style: TextStyle(
                color: hi,
                fontSize: 12 * scale,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: 'Capital',
              style: TextStyle(
                color: hi,
                fontSize: 12 * scale,
                fontWeight: FontWeight.w500,
              ),
            ),
          ]),
        ),
      ],
    );
  }
}
