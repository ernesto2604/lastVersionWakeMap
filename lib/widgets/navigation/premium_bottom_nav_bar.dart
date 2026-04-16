import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_liquid_glass_plus/flutter_liquid_glass.dart';

class PremiumBottomNavItem {
  const PremiumBottomNavItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

class PremiumBottomNavBar extends StatelessWidget {
  const PremiumBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.onExtraButtonTap,
    this.extraButtonIcon = Icons.mic_none_rounded,
    this.extraButtonLabel = 'Voice',
    this.extraButtonIconColor,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<PremiumBottomNavItem> items;
  final VoidCallback? onExtraButtonTap;
  final IconData extraButtonIcon;
  final String extraButtonLabel;
  final Color? extraButtonIconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final bottomPadding = math.max(10.0, bottomInset * 0.55);
    final resolvedExtraIconColor =
      extraButtonIconColor ?? theme.colorScheme.onSurface.withValues(alpha: 0.62);

    final tabs = items
        .map(
          (item) => LGBottomBarTab(
            label: item.label,
            icon: item.icon,
          ),
        )
        .toList();

    return LGBottomBar(
      tabs: tabs,
      selectedIndex: currentIndex,
      onTabSelected: onTap,
      extraButton: onExtraButtonTap == null
          ? null
          : LGBottomBarExtraButton(
              icon: Icon(
                extraButtonIcon,
                size: 22,
                color: resolvedExtraIconColor,
              ),
              onTap: onExtraButtonTap!,
              label: extraButtonLabel,
              size: 62,
            ),
      quality: LGQuality.premium,
      horizontalPadding: 12,
      verticalPadding: bottomPadding,
      spacing: 8,
      barHeight: 62,
      barBorderRadius: 22,
      tabPadding: const EdgeInsets.symmetric(horizontal: 4),
      blendAmount: 14,
      showIndicator: true,
      iconSize: 22,
      showLabel: true,
      selectedIconColor: theme.colorScheme.primary,
      unselectedIconColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      selectedLabelColor: theme.colorScheme.primary,
      unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      textStyle: theme.textTheme.labelSmall?.copyWith(
        letterSpacing: 0.1,
        height: 1.15,
      ),
      glassSettings: const LiquidGlassSettings(
        thickness: 32,
        blur: 18,
        chromaticAberration: 0.85,
        lightIntensity: 0.85,
        refractiveIndex: 1.28,
        saturation: 1.1,
      ),
      indicatorSettings: const LiquidGlassSettings(
        thickness: 18,
        blur: 0,
        chromaticAberration: 0.55,
        lightIntensity: 1.6,
        refractiveIndex: 1.12,
      ),
      indicatorColor: theme.colorScheme.primary.withValues(alpha: 0.18),
    );
  }
}
