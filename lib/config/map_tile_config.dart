import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Centralized map tile configuration for a clean, custom-looking map style.
///
/// Uses CartoDB Positron — a free, minimal, pastel-toned basemap that avoids
/// the visual clutter of default OpenStreetMap tiles while preserving all
/// essential geographic features (roads, labels, parks, water).
class MapTileConfig {
  MapTileConfig._();

  // ─── Tile providers ──────────────────────────────────────────────────

  /// Clean, light basemap with muted colours – perfect for overlaying
  /// markers, circles and routes without visual noise.
  static const String positron =
      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';

  /// Even cleaner variant without labels — useful for backgrounds where the
  /// app's own markers provide all context.
  static const String positronNoLabels =
      'https://{s}.basemaps.cartocdn.com/light_nolabels/{z}/{x}/{y}{r}.png';

  /// Dark variant for potential future dark-mode support.
  static const String darkMatter =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

  // ─── Subdomains ──────────────────────────────────────────────────────

  /// CartoDB CDN subdomains for load balancing.
  static const List<String> subdomains = ['a', 'b', 'c', 'd'];

  // ─── Attribution ─────────────────────────────────────────────────────

  static const String attribution =
      '© OpenStreetMap contributors © CARTO';

  // ─── Widget builders ─────────────────────────────────────────────────

  /// Returns the standard [TileLayer] used across the app.
  ///
  /// By default uses the labeled Positron style. Pass [urlTemplate] to
  /// override (e.g. for dark mode or no-label variant).
  static TileLayer tileLayer({
    String? urlTemplate,
    double tileOpacity = 1.0,
  }) {
    return TileLayer(
      urlTemplate: urlTemplate ?? positron,
      subdomains: subdomains,
      userAgentPackageName: 'com.wakemap.wakeMap',
      retinaMode: true,
      maxZoom: 20,
      // Keep the tile layer lighter to match the app's muted palette
      tileBuilder: tileOpacity < 1.0
          ? (context, tileWidget, tile) => Opacity(
                opacity: tileOpacity,
                child: tileWidget,
              )
          : null,
    );
  }

  /// Returns the [RichAttributionWidget] with correct credits for the
  /// selected tile provider.
  static RichAttributionWidget attributionWidget() {
    return const RichAttributionWidget(
      popupInitialDisplayDuration: Duration.zero,
      attributions: [
        TextSourceAttribution('OpenStreetMap contributors'),
        TextSourceAttribution('CARTO'),
      ],
    );
  }
}
