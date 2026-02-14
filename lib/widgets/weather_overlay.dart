import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A high-performance weather overlay using CustomPainter.
/// Supports: 'clear', 'cloudy', 'rain', 'storm'.
class WeatherOverlay extends StatefulWidget {
  final String weatherMode; // 'clear', 'cloudy', 'rain', 'storm'
  final bool isNight;

  const WeatherOverlay({
    super.key,
    required this.weatherMode,
    this.isNight = false,
  });

  @override
  State<WeatherOverlay> createState() => _WeatherOverlayState();
}

class _WeatherOverlayState extends State<WeatherOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random _random = Random();
  
  // Particles
  final List<_Particle> _particles = [];
  final List<_Cloud> _clouds = [];
  
  // Storm state
  double _lightningOpacity = 0.0;
  int _lightningTimer = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat();
  }

  @override
  void didUpdateWidget(WeatherOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weatherMode != widget.weatherMode) {
      _resetParticles();
    }
  }

  void _resetParticles() {
    _particles.clear();
    _clouds.clear();
    
    // Initialize based on mode
    if (widget.weatherMode == 'rain' || widget.weatherMode == 'storm') {
      int count = widget.weatherMode == 'storm' ? 300 : 100;
      for (int i = 0; i < count; i++) {
        _particles.add(_createRainDrop());
      }
    }
    
    if (widget.weatherMode == 'cloudy' || widget.weatherMode == 'storm') {
        int cloudCount = widget.weatherMode == 'storm' ? 5 : 3;
        for (int i = 0; i < cloudCount; i++) {
          _clouds.add(_createCloud());
        }
    }
  }

  _Particle _createRainDrop([bool randomizeY = true]) {
    return _Particle(
      x: _random.nextDouble(),
      y: randomizeY ? _random.nextDouble() : -0.1,
      speed: 0.015 + _random.nextDouble() * 0.02, // Fast fall
      length: 0.02 + _random.nextDouble() * 0.03,
      opacity: 0.3 + _random.nextDouble() * 0.4,
    );
  }

  _Cloud _createCloud() {
    return _Cloud(
      x: _random.nextDouble() * 1.5 - 0.2, // Spread wider than screen
      y: _random.nextDouble() * 0.4, // Top 40% of screen
      speed: 0.0005 + _random.nextDouble() * 0.001, // Slow drift
      scale: 0.5 + _random.nextDouble() * 1.0,
      opacity: 0.1 + _random.nextDouble() * 0.2,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. CLEAR / SUNNY
    if (widget.weatherMode == 'clear') {
         return const SizedBox.shrink(); // No overlay for clear weather
    }

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          _updatePhysics();
          
          return Stack(
            children: [
              // TINT LAYER
              if (widget.weatherMode == 'cloudy')
                Container(color: Colors.grey.withValues(alpha: 0.1)),
              if (widget.weatherMode == 'rain')
                Container(color: Colors.blueGrey.withValues(alpha: 0.15)),
              if (widget.weatherMode == 'storm')
                Container(color: Colors.black.withValues(alpha: 0.3)),

              // PARTICLES & CLOUDS
              CustomPaint(
                painter: _WeatherPainter(
                  particles: _particles,
                  clouds: _clouds,
                  lightningOpacity: _lightningOpacity,
                  mode: widget.weatherMode,
                ),
                size: Size.infinite,
              ),
            ],
          );
        },
      ),
    );
  }

  void _updatePhysics() {
    // UPDATE RAIN
    if (widget.weatherMode == 'rain' || widget.weatherMode == 'storm') {
       if (_particles.isEmpty) _resetParticles();
       
       for (var p in _particles) {
         p.y += p.speed;
         if (p.y > 1.1) {
           // Reset to top
           p.y = -0.1;
           p.x = _random.nextDouble();
         }
       }
    }

    // UPDATE CLOUDS
    if (widget.weatherMode == 'cloudy' || widget.weatherMode == 'storm') {
       if (_clouds.isEmpty) _resetParticles();

       for (var c in _clouds) {
         c.x += c.speed;
         if (c.x > 1.3) {
           c.x = -0.3; // Loop back
         }
       }
    }

    // UPDATE LIGHTNING (Storm only)
    if (widget.weatherMode == 'storm') {
       if (_lightningOpacity > 0) {
         _lightningOpacity -= 0.1; // Fade out
         if (_lightningOpacity < 0) _lightningOpacity = 0;
       } else {
         _lightningTimer++;
         // Random flash every ~3-8 seconds (assuming 60fps)
         if (_lightningTimer > 180 + _random.nextInt(300)) {
            _lightningOpacity = 0.8 + _random.nextDouble() * 0.2; // Bright flash
            _lightningTimer = 0;
         }
       }
    }
  }
}

class _WeatherPainter extends CustomPainter {
  final List<_Particle> particles;
  final List<_Cloud> clouds;
  final double lightningOpacity;
  final String mode;

  _WeatherPainter({
    required this.particles,
    required this.clouds,
    required this.lightningOpacity,
    required this.mode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. DRAW LIGHTNING FLASH (Background)
    if (lightningOpacity > 0.01) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.white.withValues(alpha: lightningOpacity),
      );
    }

    // 2. DRAW CLOUDS
    // Drawing fluffy clouds procedurally is expensive, so we use simple soft circles/ovals
    // or we could use an asset image. For pure code, we'll draw soft gradients.
    for (var c in clouds) {
      final paint = Paint()
        ..color = (mode == 'storm' ? Colors.black : Colors.white)
            .withValues(alpha: c.opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30); // Heavy blur for "fog" look

      final center = Offset(c.x * size.width, c.y * size.height);
      final cloudSize = size.width * 0.4 * c.scale;
      
      canvas.drawCircle(center, cloudSize, paint);
      // Draw a second circle for shape irregularity
      canvas.drawCircle(
          center + Offset(cloudSize * 0.6, cloudSize * 0.2), 
          cloudSize * 0.8, 
          paint
      );
    }

    // 3. DRAW RAIN
    if (mode == 'rain' || mode == 'storm') {
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;

      for (var p in particles) {
        final start = Offset(p.x * size.width, p.y * size.height);
        final end = Offset(
          start.dx - (p.speed * size.width * 0.2), // Slight wind tilt
          start.dy + (p.length * size.height)
        );
        
        paint.color = Colors.white.withValues(alpha: p.opacity);
        canvas.drawLine(start, end, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherPainter oldDelegate) {
    return true; // Always repaint for animation
  }
}

class _Particle {
  double x;
  double y;
  double speed;
  double length;
  double opacity;

  _Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.length,
    required this.opacity,
  });
}

class _Cloud {
  double x;
  double y;
  double speed;
  double scale;
  double opacity;

  _Cloud({
    required this.x,
    required this.y,
    required this.speed,
    required this.scale,
    required this.opacity,
  });
}
