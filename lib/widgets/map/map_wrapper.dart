import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// Web-safe map helpers shared across screens.
class MapWrapper {
  const MapWrapper._();

  /// `defaultMarkerWithHue` is not available on web.
  static BitmapDescriptor markerWithHue(double hue) {
    if (kIsWeb) return BitmapDescriptor.defaultMarker;
    return BitmapDescriptor.defaultMarkerWithHue(hue);
  }

  /// Google Maps lite mode is Android-only.
  static bool get liteModeEnabled => !kIsWeb;

  /// Keep overlay controls clickable above web maps rendered via HtmlElementView.
  static Widget overlay(Widget child) {
    if (!kIsWeb) return child;
    return PointerInterceptor(child: child);
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
