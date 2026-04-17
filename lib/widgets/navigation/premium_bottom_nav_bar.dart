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
    this.forceSolidStyle = false,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<PremiumBottomNavItem> items;
  final VoidCallback? onExtraButtonTap;
  final IconData extraButtonIcon;
  final String extraButtonLabel;
  final Color? extraButtonIconColor;
  final bool forceSolidStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final bottomPadding = math.max(10.0, bottomInset * 0.55);
    final resolvedExtraIconColor =
      extraButtonIconColor ?? theme.colorScheme.onSurface.withValues(alpha: 0.78);

    final tabs = items
        .map(
          (item) => LGBottomBarTab(
            label: item.label,
            icon: item.icon,
          ),
        )
        .toList();

    if (forceSolidStyle) {
      return _SolidBottomNavBar(
        currentIndex: currentIndex,
        onTap: onTap,
        items: items,
        onExtraButtonTap: onExtraButtonTap,
        extraButtonIcon: extraButtonIcon,
        extraButtonLabel: extraButtonLabel,
        extraButtonIconColor: resolvedExtraIconColor,
        bottomPadding: bottomPadding,
      );
    }

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
      unselectedIconColor: theme.colorScheme.onSurface.withValues(alpha: 0.78),
      selectedLabelColor: theme.colorScheme.primary,
      unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.78),
      textStyle: theme.textTheme.labelSmall?.copyWith(
        letterSpacing: 0.1,
        height: 1.15,
      ),
      glassSettings: const LiquidGlassSettings(
        thickness: 32,
        blur: 18,
        chromaticAberration: 0.85,
        lightIntensity: 0.95,
        refractiveIndex: 1.28,
        saturation: 1.1,
        glassColor: Color(0x2CFFFFFF),
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

class _SolidBottomNavBar extends StatelessWidget {
  const _SolidBottomNavBar({
    required this.currentIndex,
    required this.onTap,
    required this.items,
    required this.bottomPadding,
    required this.extraButtonIcon,
    required this.extraButtonLabel,
    required this.extraButtonIconColor,
    this.onExtraButtonTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<PremiumBottomNavItem> items;
  final double bottomPadding;
  final VoidCallback? onExtraButtonTap;
  final IconData extraButtonIcon;
  final String extraButtonLabel;
  final Color extraButtonIconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPadding),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 62,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(22),
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
                child: Row(
                  children: List.generate(items.length, (index) {
                    final item = items[index];
                    final selected = index == currentIndex;

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => onTap(index),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              decoration: BoxDecoration(
                                color: selected
                                    ? theme.colorScheme.primary.withValues(alpha: 0.14)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    item.icon,
                                    size: 22,
                                    color: selected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface.withValues(alpha: 0.78),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.label,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      letterSpacing: 0.1,
                                      height: 1.15,
                                      color: selected
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface.withValues(alpha: 0.78),
                                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            if (onExtraButtonTap != null) ...[
              const SizedBox(width: 8),
              Container(
                width: 62,
                height: 62,
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
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onExtraButtonTap,
                    child: Tooltip(
                      message: extraButtonLabel,
                      child: Icon(
                        extraButtonIcon,
                        size: 22,
                        color: extraButtonIconColor,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
