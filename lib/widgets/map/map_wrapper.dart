import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_liquid_glass_plus/flutter_liquid_glass.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'map_style_config.dart';

/// Web-safe map helpers shared across screens.
class MapWrapper {
  const MapWrapper._();

  /// Optional cloud map id reserved for future rollout.
  static const String _definedCloudMapId = String.fromEnvironment(
    'GOOGLE_MAP_CLOUD_MAP_ID',
  );

  static String? get cloudMapId {
    final value = _definedCloudMapId.trim();
    return value.isEmpty ? null : value;
  }

  /// `defaultMarkerWithHue` is not available on web.
  static BitmapDescriptor markerWithHue(double hue) {
    if (kIsWeb) return BitmapDescriptor.defaultMarker;
    return BitmapDescriptor.defaultMarkerWithHue(hue);
  }

  /// Google Maps lite mode is Android-only.
  static bool get liteModeEnabled => !kIsWeb;

  static String styleFor(Brightness brightness) {
    return brightness == Brightness.dark
        ? MapStyleConfig.dark
        : MapStyleConfig.light;
  }

  static Future<void> applyThemeStyle({
    required GoogleMapController controller,
    required Brightness brightness,
  }) async {
    try {
      // ignore: deprecated_member_use
      await controller.setMapStyle(styleFor(brightness));
    } catch (error) {
      // Styling should never block map usage if unsupported on a platform.
      debugPrint('[MapStyle] Unable to apply style: $error');
    }
  }

  /// Keep overlay controls clickable above web maps rendered via HtmlElementView.
  static Widget overlay(Widget child) {
    if (!kIsWeb) return child;
    return PointerInterceptor(child: child);
  }

  static Widget frostedPill({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 8,
    ),
    Color? backgroundColor,
    double borderRadius = 14,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? CupertinoColors.systemBackground.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: CupertinoColors.separator.withValues(alpha: 0.35),
          width: 0.8,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 14,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }

  static Widget circularControl({
    required BuildContext context,
    required VoidCallback onPressed,
    required IconData icon,
    String? tooltip,
    double size = 48,
    bool useLiquidGlass = true,
    Color? iconColor,
  }) {
    final resolvedIconColor = iconColor ??
        Theme.of(context).colorScheme.onSurface.withValues(
      alpha: 0.78,
    );

    if (!useLiquidGlass) {
      final theme = Theme.of(context);
      return overlay(
        Tooltip(
          message: tooltip ?? '',
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.94),
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.2),
                width: 0.8,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: IconButton(
              onPressed: onPressed,
              icon: Icon(icon, color: resolvedIconColor, size: 22),
              splashRadius: size * 0.45,
              tooltip: tooltip,
            ),
          ),
        ),
      );
    }

    return overlay(
      Tooltip(
        message: tooltip ?? '',
        child: LGButton.custom(
          label: tooltip ?? '',
          onTap: onPressed,
          width: size,
          height: size,
          quality: LGQuality.premium,
          useOwnLayer: true,
          settings: const LiquidGlassSettings(
            thickness: 32,
            blur: 18,
            chromaticAberration: 0.85,
            lightIntensity: 0.95,
            refractiveIndex: 1.28,
            saturation: 1.1,
            glassColor: Color(0x2CFFFFFF),
          ),
          glowColor: const Color(0x0EFFFFFF),
          glowRadius: 0.95,
          child: Icon(
            icon,
            color: resolvedIconColor,
            size: 22,
          ),
        ),
      ),
    );
  }

  static Widget primaryCircularControl({
    required BuildContext context,
    required VoidCallback onPressed,
    required IconData icon,
    String? tooltip,
    double size = 56,
  }) {
    final primary = CupertinoTheme.of(context).primaryColor;

    return overlay(
      Tooltip(
        message: tooltip ?? '',
        child: LGButton.custom(
          label: tooltip ?? '',
          onTap: onPressed,
          width: size,
          height: size,
          quality: LGQuality.premium,
          useOwnLayer: true,
          settings: LiquidGlassSettings(
            thickness: 30,
            blur: 12,
            chromaticAberration: 0.85,
            lightIntensity: 1.1,
            refractiveIndex: 1.22,
            saturation: 1.25,
            glassColor: primary.withValues(alpha: 0.45),
          ),
          glowColor: primary.withValues(alpha: 0.28),
          glowRadius: 1.05,
          child: Icon(
            icon,
            color: CupertinoColors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  /// Temporary web diagnostics for map container sizing/visibility.
  static Widget withLayoutDiagnostics({
    required String tag,
    required Widget child,
  }) {
    if (!(kIsWeb && kDebugMode)) return child;
    return _MapLayoutDiagnostics(tag: tag, child: child);
  }
}

class _MapLayoutDiagnostics extends StatefulWidget {
  const _MapLayoutDiagnostics({required this.tag, required this.child});

  final String tag;
  final Widget child;

  @override
  State<_MapLayoutDiagnostics> createState() => _MapLayoutDiagnosticsState();
}

class _MapLayoutDiagnosticsState extends State<_MapLayoutDiagnostics> {
  static const double _sizeEpsilon = 0.5;

  Size? _lastContainerSize;
  Size? _lastMediaSize;
  bool _didLogBuildReach = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaSize = MediaQuery.sizeOf(context);
        final containerSize = Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : double.nan,
          constraints.hasBoundedHeight ? constraints.maxHeight : double.nan,
        );

        final shouldLogBuildReach = !_didLogBuildReach;
        final shouldLogSizeChange =
            _lastContainerSize == null ||
            _lastMediaSize == null ||
            (containerSize.width - _lastContainerSize!.width).abs() >
                _sizeEpsilon ||
            (containerSize.height - _lastContainerSize!.height).abs() >
                _sizeEpsilon ||
            (mediaSize.width - _lastMediaSize!.width).abs() > _sizeEpsilon ||
            (mediaSize.height - _lastMediaSize!.height).abs() > _sizeEpsilon;

        if (shouldLogBuildReach || shouldLogSizeChange) {
          final nonZeroContainer = containerSize.width > 0 &&
              containerSize.height > 0 &&
              containerSize.width.isFinite &&
              containerSize.height.isFinite;
          debugPrint(
            '[MapLayout:${widget.tag}] '
            'buildReached=true '
            'constraints=$constraints '
            'container=${containerSize.width.toStringAsFixed(1)}x${containerSize.height.toStringAsFixed(1)} '
            'media=${mediaSize.width.toStringAsFixed(1)}x${mediaSize.height.toStringAsFixed(1)} '
            'nonZero=$nonZeroContainer',
          );
          _didLogBuildReach = true;
          _lastContainerSize = containerSize;
          _lastMediaSize = mediaSize;
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x2200BCD4),
            border: Border.all(
              color: const Color(0xFF00BCD4),
              width: 2,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              Positioned(
                top: 8,
                left: 8,
                child: MapWrapper.overlay(
                  IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      color: const Color(0xCC000000),
                      child: const Text(
                        'MAP CONTAINER',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
