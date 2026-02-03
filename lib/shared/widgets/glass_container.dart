import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/constants/app_constants.dart';

/// Glassmorphic Container - 2025 Enhanced (Luminous Architecture)
/// 
/// Key Changes for 2025:
/// - Luminous gradient borders (simulates light catching glass edges)
/// - Layered structure for proper depth
/// - Optional inner glow for premium feel
/// - Variable blur support
/// 
/// Set `useLuminousBorder: true` to enable the Spatial Glass effect
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blurAmount;
  final Color? backgroundColor;
  final Color? borderColor;
  final bool showGlow;
  final bool useSmallGlow;
  final Color glowColor;
  final VoidCallback? onTap;
  
  /// Enable luminous gradient borders (Spatial Glass architecture)
  /// Creates light-catching effect on glass edges
  final bool useLuminousBorder;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = AppConstants.borderRadiusLarge,
    this.blurAmount = AppConstants.glassBlurAmount,
    this.backgroundColor,
    this.borderColor,
    this.showGlow = false,
    this.useSmallGlow = false,
    this.glowColor = AppColors.primaryAction,
    this.onTap,
    this.useLuminousBorder = false, // Opt-in for Spatial Glass
  });

  @override
  Widget build(BuildContext context) {
    // ACCESSIBILITY FIX: Prevent "Halation" / Astigmatism Trap
    // When useLuminousBorder is true, disable the outer boxShadow glow.
    // Combining luminous borders + outer glow creates a double-glow effect
    // that causes eye strain for ~50% of users (those with astigmatism).
    // Rule: You can have ONE glow source, not both.
    final effectiveShowGlow = showGlow && !useLuminousBorder;
    
    return Container(
      margin: margin,
      decoration: effectiveShowGlow
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withAlpha(20), // Reduced to subtle outline
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            )
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: RepaintBoundary(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
            child: GestureDetector(
              onTap: onTap,
              child: useLuminousBorder
                  ? CustomPaint(
                      painter: _LuminousBorderPainter(
                        borderRadius: borderRadius,
                        borderColor: borderColor ?? AppColors.glassBorder,
                      ),
                      child: Container(
                        width: width,
                        height: height,
                        padding: padding,
                        decoration: BoxDecoration(
                          color: backgroundColor ?? AppColors.glassBackground,
                          borderRadius: BorderRadius.circular(borderRadius),
                          // No border here - painted by CustomPainter
                        ),
                        child: child,
                      ),
                    )
                  : Container(
                      width: width,
                      height: height,
                      padding: padding,
                      decoration: BoxDecoration(
                        color: backgroundColor ?? AppColors.glassBackground,
                        borderRadius: BorderRadius.circular(borderRadius),
                        border: Border.all(
                          color: borderColor ?? AppColors.glassBorder,
                          width: 1.5, // Standard border (legacy)
                        ),
                      ),
                      child: child,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// Surface gradient for depth
  LinearGradient _buildSurfaceGradient() {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withAlpha(13), // 5%
        Colors.white.withAlpha(5),  // 2%
      ],
    );
  }

  /// Rim light gradient for 3D effect
  LinearGradient _buildRimGradient() {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withAlpha(20), // 8%
        Colors.white.withAlpha(5),  // 2%
        Colors.transparent,
      ],
      stops: const [0.0, 0.3, 1.0],
    );
  }
}

/// Custom painter for luminous gradient borders (Spatial Glass)
/// Paints a gradient stroke that fades from top (light catch) to bottom (transparent)
class _LuminousBorderPainter extends CustomPainter {
  final double borderRadius;
  final Color borderColor;
  
  _LuminousBorderPainter({
    required this.borderRadius,
    required this.borderColor,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(borderRadius),
    );
    
    // Create gradient shader (top bright, bottom fades)
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        AppColors.luminousBorderTop,
        AppColors.luminousBorderBottom,
      ],
    );
    
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    canvas.drawRRect(rrect, paint);
  }
  
  @override
  bool shouldRepaint(_LuminousBorderPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius ||
           oldDelegate.borderColor != borderColor;
  }
}

/// Custom painter for luminous gradient borders on CIRCULAR shapes
/// Used for camera shutter, avatars, and other circular elements
class CircularLuminousBorderPainter extends CustomPainter {
  final double strokeWidth;
  final Color baseColor;
  
  CircularLuminousBorderPainter({
    required this.strokeWidth,
    required this.baseColor,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // Create gradient shader (top bright, bottom fades)
    // For circular shapes, we simulate top-bottom gradient radially
    final gradient = SweepGradient(
      center: Alignment.center,
      startAngle: -math.pi / 2, // Start at top (12 o'clock)
      endAngle: 3 * math.pi / 2, // End at top (full rotation)
      colors: [
        // Top (brightest)
        Color.lerp(baseColor, Colors.white, 0.6)!,
        // Sides (medium)
        baseColor,
        // Bottom (fade)
        Color.lerp(baseColor, Colors.transparent, 0.7)!,
        // Back to top
        Color.lerp(baseColor, Colors.white, 0.6)!,
      ],
      stops: const [0.0, 0.25, 0.5, 1.0],
    );
    
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    
    canvas.drawCircle(center, radius - strokeWidth / 2, paint);
  }
  
  @override
  bool shouldRepaint(CircularLuminousBorderPainter oldDelegate) {
    return oldDelegate.strokeWidth != strokeWidth ||
           oldDelegate.baseColor != baseColor;
  }
}

/// Glassmorphic Card with enhanced styling
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final VoidCallback? onTap;
  final bool isSelected;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = AppConstants.borderRadiusLarge,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: padding,
      margin: margin,
      borderRadius: borderRadius,
      showGlow: isSelected,
      glowColor: AppColors.primaryAction,
      useLuminousBorder: true, // âœ¨ Enable Spatial Glass by default
      borderColor:
          isSelected ? AppColors.primaryAction : AppColors.glassBorder,
      onTap: onTap,
      child: child,
    );
  }
}

/// Glassmorphic Button with press animation
class GlassButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final double width;
  final double height;
  final bool isLoading;
  final Color? glowColor;

  const GlassButton({
    super.key,
    required this.child,
    this.onPressed,
    this.width = 60,
    this.height = 60,
    this.isLoading = false,
    this.glowColor,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onPressed?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: GlassContainer(
              width: widget.width,
              height: widget.height,
              borderRadius: widget.width / 2,
              showGlow: widget.glowColor != null,
              glowColor: widget.glowColor ?? AppColors.primaryAction,
              child: Center(
                child: widget.isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryAction,
                        ),
                      )
                    : widget.child,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 2025: Modern pill-shaped action button
class GlassPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? accentColor;
  final bool isActive;

  const GlassPill({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.accentColor,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppColors.primaryAction;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive 
              ? color.withAlpha(51) 
              : AppColors.glassBackground,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isActive ? color : AppColors.glassBorder,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: isActive ? color : AppColors.textSecondary),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: isActive ? color : AppColors.textSecondary,
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
