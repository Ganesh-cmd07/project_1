import 'package:flutter/material.dart';
import '../models/route_model.dart';
import '../theme/app_theme.dart';

/// A custom marker widget that displays the user's vehicle with a pulse animation.
class VehicleMarker extends StatefulWidget {
  final VehicleType vehicleType;
  final bool isNavigating;

  const VehicleMarker({
    super.key,
    required this.vehicleType,
    this.isNavigating = false,
  });

  @override
  State<VehicleMarker> createState() => _VehicleMarkerState();
}

class _VehicleMarkerState extends State<VehicleMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData _getVehicleIcon() {
    switch (widget.vehicleType) {
      case VehicleType.bike:
        return Icons.two_wheeler;
      case VehicleType.car:
        return Icons.directions_car;
      case VehicleType.truck:
        return Icons.local_shipping; // Better than plain truck
      case VehicleType.bus:
        return Icons.directions_bus;
    }
  }
  
  Color _getVehicleColor() {
    // Return a distinct color for the vehicle to stand out
    return AppColors.primary; 
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Pulse Effect
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _getVehicleColor().withValues(alpha: _opacityAnimation.value),
                ),
              ),
            );
          },
        ),
        
        // Main Marker Circle
        Container(
          width: 40, 
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(
              color: Colors.white,
              width: 2,
            ),
          ),
          child: Center(
            child: Icon(
              _getVehicleIcon(),
              color: _getVehicleColor(),
              size: 24,
            ),
          ),
        ),
        
        // Direction Arrow (only if navigating)
        if (widget.isNavigating)
           Positioned(
             top: -5,
             child: Icon(Icons.arrow_drop_up, color: _getVehicleColor(), size: 20),
           ),
      ],
    );
  }
}
