// lib/widgets/empty_friends_state.dart
import 'package:flutter/material.dart';
import 'dart:math' as math;

class EmptyFriendsState extends StatelessWidget {
  final VoidCallback onDiscoverTap;

  const EmptyFriendsState({super.key, required this.onDiscoverTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Ana görsel ve avatarlar
              SizedBox(
                width: 280,
                height: 280,
                child: Stack(
                  children: [
                    // Sağ üstte ok ve "Keşfet" butonu
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Ok işareti
                          CustomPaint(
                            size: const Size(100, 100),
                            painter: _ArrowPainter(
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Keşfet butonu
                          Transform.rotate(
                            angle: -0.15,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: onDiscoverTap,
                                borderRadius: BorderRadius.circular(25),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor,
                                    borderRadius: BorderRadius.circular(25),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Theme.of(
                                          context,
                                        ).primaryColor.withOpacity(0.4),
                                        blurRadius: 15,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: const Text(
                                    'Keşfet',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Merkezdeki ana içerik
                    Center(
                      child: SizedBox(
                        width: 256,
                        height: 256,
                        child: Stack(
                          children: [
                            // Dış kesik çizgili daire
                            Center(
                              child: CustomPaint(
                                size: const Size(256, 256),
                                painter: _DashedCirclePainter(
                                  color: isDark
                                      ? Colors.grey[700]!
                                      : Colors.grey[300]!,
                                ),
                              ),
                            ),

                            // İç solid daire
                            Center(
                              child: Container(
                                width: 192,
                                height: 192,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.grey[800]!
                                        : Colors.grey[200]!,
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),

                            // Ana ikon (merkez)
                            Center(
                              child: Container(
                                width: 128,
                                height: 128,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.grey[800]
                                      : Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.15),
                                      blurRadius: 30,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.person_search,
                                  size: 64,
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                            ),

                            // Küçük avatar 1 (Sağ üst)
                            Positioned(
                              top: 0,
                              right: 16,
                              child: _SmallAvatar(
                                color: Colors.blue[100]!,
                                icon: Icons.person,
                              ),
                            ),

                            // Küçük avatar 2 (Sol orta)
                            Positioned(
                              top: 100,
                              left: 0,
                              child: _SmallAvatar(
                                color: Colors.pink[100]!,
                                icon: Icons.person,
                                size: 48,
                              ),
                            ),

                            // Küçük avatar 3 (Sağ alt)
                            Positioned(
                              bottom: 8,
                              right: 48,
                              child: _SmallAvatar(
                                color: Colors.green[100]!,
                                icon: Icons.person,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Başlık ve açıklama
              Text(
                'Henüz kimse yok',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.grey[900],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Yeni arkadaşlar bulmak ve topluluğa katılmak için menüden keşfetmeye başla.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Küçük avatar widget'ı
class _SmallAvatar extends StatelessWidget {
  final Color color;
  final IconData icon;
  final double size;

  const _SmallAvatar({required this.color, required this.icon, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.grey[700], size: size * 0.6),
      ),
    );
  }
}

// Ok çizen painter
class _ArrowPainter extends CustomPainter {
  final Color color;

  _ArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Eğri çizgi (Bezier curve)
    final path = Path();
    path.moveTo(size.width * 0.2, size.height * 0.8);
    path.quadraticBezierTo(
      size.width * 0.4,
      size.height * 0.6,
      size.width * 0.7,
      size.height * 0.4,
    );
    path.quadraticBezierTo(
      size.width * 0.85,
      size.height * 0.25,
      size.width * 0.85,
      size.height * 0.15,
    );

    // Kesikli çizgi efekti
    final dashPath = _createDashedPath(path, 4, 4);
    canvas.drawPath(dashPath, paint);

    // Ok başı
    final arrowPaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final arrowPath = Path();
    arrowPath.moveTo(size.width * 0.75, size.height * 0.18);
    arrowPath.lineTo(size.width * 0.85, size.height * 0.15);
    arrowPath.lineTo(size.width * 0.82, size.height * 0.25);

    canvas.drawPath(arrowPath, arrowPaint);
  }

  Path _createDashedPath(Path source, double dashLength, double dashSpace) {
    final Path dest = Path();
    for (var metric in source.computeMetrics()) {
      double distance = 0.0;
      bool draw = true;
      while (distance < metric.length) {
        final double length = draw ? dashLength : dashSpace;
        if (distance + length > metric.length) {
          if (draw) {
            dest.addPath(
              metric.extractPath(distance, metric.length),
              Offset.zero,
            );
          }
          break;
        } else {
          if (draw) {
            dest.addPath(
              metric.extractPath(distance, distance + length),
              Offset.zero,
            );
          }
          distance += length;
          draw = !draw;
        }
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Kesikli daire çizen painter
class _DashedCirclePainter extends CustomPainter {
  final Color color;

  _DashedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final radius = size.width / 2;
    final center = Offset(size.width / 2, size.height / 2);

    const dashLength = 8.0;
    const gapLength = 6.0;
    final circumference = 2 * math.pi * radius;
    final dashCount = (circumference / (dashLength + gapLength)).floor();

    for (int i = 0; i < dashCount; i++) {
      final startAngle = (i * (dashLength + gapLength) / radius);
      final sweepAngle = dashLength / radius;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
