import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math';
import '../models/route_model.dart';

// ===============================================================
// PREMIUM BOTTOM SHEET — Compact Dark Glassmorphism Route Panel
// ===============================================================

class PremiumBottomSheet extends StatelessWidget {
  final RouteModel? route;
  final String statusMessage;
  final String weatherForecast;
  final Color routeColor;
  final bool isNavigating;
  final bool isRaining;

  const PremiumBottomSheet({
    super.key,
    required this.route,
    required this.statusMessage,
    required this.weatherForecast,
    required this.routeColor,
    this.isNavigating = false,
    this.isRaining = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF0F172A).withValues(alpha: 0.92),
                const Color(0xFF1E293B).withValues(alpha: 0.88),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: routeColor.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: routeColor.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, -3),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 32,
                height: 3,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              if (route != null) ...[
                // ROW 1: Safety Ring + Status + Inline Stats
                _buildMainRow(),
                
                // ROW 2: AI Alert (only if needed, compact)
                if (route!.isRaining || route!.hydroplaningRisk || route!.elevationDips.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildCompactAlert(),
                ],
              ] else
                _buildIdleStatus(),
            ],
          ),
        ),
      ),
    );
  }

  // ------ MAIN ROW: Safety Ring + Status + Stats ------
  Widget _buildMainRow() {
    final safetyPercent = _calculateSafety();
    final riskColor = _getRiskColor(route!.riskLevel);

    return Row(
      children: [
        // Safety Ring
        _SafetyScoreRing(
          percentage: safetyPercent,
          color: riskColor,
          size: 40,
        ),
        const SizedBox(width: 10),

        // Status text
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                statusMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  _buildRiskChip(route!.riskLevel, riskColor),
                  const SizedBox(width: 6),
                  if (weatherForecast.isNotEmpty)
                    Flexible(
                      child: Text(
                        weatherForecast,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // Inline stat chips
        Expanded(
          flex: 4,
          child: Row(
            children: [
              _buildMiniStat(Icons.schedule, "${route!.durationMinutes}", "min", const Color(0xFF00F0FF)),
              const SizedBox(width: 6),
              _buildMiniStat(Icons.straighten, (route!.distanceMeters / 1000).toStringAsFixed(1), "km", const Color(0xFF7C3AED)),
              const SizedBox(width: 6),
              _buildMiniStat(Icons.shield, "${safetyPercent.toInt()}", "%", riskColor),
              const SizedBox(width: 6),
              _buildMiniStat(
                Icons.water_drop,
                route!.isRaining ? "WET" : "DRY",
                "",
                route!.isRaining ? const Color(0xFF3B82F6) : const Color(0xFF10B981),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat(IconData icon, String value, String unit, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 12),
            const SizedBox(height: 2),
            Text(
              unit.isNotEmpty ? "$value$unit" : value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskChip(String risk, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        risk.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  // ------ COMPACT ALERT (single line) ------
  Widget _buildCompactAlert() {
    String alertText;
    IconData alertIcon;
    Color alertColor;

    if (route!.hydroplaningRisk) {
      alertText = "Hydroplaning risk on high-speed segments";
      alertIcon = Icons.speed;
      alertColor = const Color(0xFFEF4444);
    } else if (route!.elevationDips.isNotEmpty) {
      alertText = "${route!.elevationDips.length} waterlogging zones along route";
      alertIcon = Icons.waves;
      alertColor = const Color(0xFFF59E0B);
    } else {
      alertText = "Rain detected — reduced visibility";
      alertIcon = Icons.cloud;
      alertColor = const Color(0xFF3B82F6);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: alertColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: alertColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(alertIcon, color: alertColor, size: 14),
          const SizedBox(width: 8),
          Text(
            "AI ALERT",
            style: TextStyle(
              color: alertColor,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              alertText,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ------ IDLE STATUS (no route) ------
  Widget _buildIdleStatus() {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF00F0FF).withValues(alpha: 0.1),
            border: Border.all(color: const Color(0xFF00F0FF).withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.navigation, color: Color(0xFF00F0FF), size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            statusMessage,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  // ------ HELPERS ------
  double _calculateSafety() {
    if (route == null) return 0;
    switch (route!.riskLevel) {
      case 'Safe':
        return 92;
      case 'Medium':
        return 65;
      case 'High':
        return 30;
      default:
        return 75;
    }
  }

  Color _getRiskColor(String risk) {
    switch (risk) {
      case 'Safe':
        return const Color(0xFF10B981);
      case 'Medium':
        return const Color(0xFFF59E0B);
      case 'High':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF00F0FF);
    }
  }
}

// ===============================================================
// SAFETY SCORE RING — Animated Circular Progress
// ===============================================================

class _SafetyScoreRing extends StatefulWidget {
  final double percentage;
  final Color color;
  final double size;

  const _SafetyScoreRing({
    required this.percentage,
    required this.color,
    required this.size,
  });

  @override
  State<_SafetyScoreRing> createState() => _SafetyScoreRingState();
}

class _SafetyScoreRingState extends State<_SafetyScoreRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = Tween<double>(begin: 0, end: widget.percentage / 100)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _SafetyScoreRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.percentage != widget.percentage) {
      _animation = Tween<double>(
        begin: _animation.value,
        end: widget.percentage / 100,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _RingPainter(
              progress: _animation.value,
              color: widget.color,
            ),
            child: Center(
              child: Text(
                "${widget.percentage.toInt()}%",
                style: TextStyle(
                  color: widget.color,
                  fontSize: widget.size * 0.22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 6) / 2;

    // Background ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    // Progress arc
    final progressPaint = Paint()
      ..shader = SweepGradient(
        startAngle: -pi / 2,
        endAngle: 3 * pi / 2,
        colors: [
          color.withValues(alpha: 0.3),
          color,
          color,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      progressPaint,
    );

    // Glow dot at end
    if (progress > 0.01) {
      final angle = -pi / 2 + 2 * pi * progress;
      final dotCenter = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      canvas.drawCircle(dotCenter, 3, Paint()..color = color);
      canvas.drawCircle(dotCenter, 6, Paint()..color = color.withValues(alpha: 0.2));
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
