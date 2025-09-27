import 'package:flutter/material.dart';

import 'app_theme.dart';

class BrandSpacing {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 20;
  static const double lg = 28;
  static const double xl = 36;
  static const double xxl = 48;
}

class BrandRadii {
  static const double small = 14;
  static const double medium = 20;
  static const double large = 28;
  static const double pill = 999;
}

class BrandShadows {
  static List<BoxShadow> card = [
    BoxShadow(
      color: BrandColors.navy.withValues(alpha: 0.08),
      blurRadius: 48,
      offset: const Offset(0, 32),
    ),
  ];

  static List<BoxShadow> surface = [
    BoxShadow(
      color: BrandColors.navy.withValues(alpha: 0.06),
      blurRadius: 36,
      spreadRadius: 0,
      offset: const Offset(0, 24),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> primaryButton(bool enabled) => [
        BoxShadow(
          color: BrandColors.primary.withValues(alpha: enabled ? 0.32 : 0.18),
          blurRadius: enabled ? 42 : 24,
          offset: const Offset(0, 18),
        ),
      ];
}

class BrandGradients {
  static const LinearGradient background = LinearGradient(
    colors: [Color(0xFF111C2D), Color(0xFF0B1522)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient halo = LinearGradient(
    colors: [Color(0x3329F1CF), Color(0x0005E2CF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient primary(bool enabled) => LinearGradient(
        colors: enabled
            ? const [BrandColors.primaryBright, BrandColors.primary]
            : [
                BrandColors.primary.withValues(alpha: 0.55),
                BrandColors.primary.withValues(alpha: 0.45),
              ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static const LinearGradient surface = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF2F7FB)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class BrandBackground extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool withHeroOverlay;

  const BrandBackground({
    super.key,
    required this.child,
    this.padding,
    this.withHeroOverlay = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(gradient: BrandGradients.background),
          child: const SizedBox.expand(),
        ),
        if (withHeroOverlay) ...[
          Positioned(
            top: -180,
            left: -120,
            child: _GlowOrb(
              size: 420,
              color: BrandColors.primaryBright.withValues(alpha: 0.35),
            ),
          ),
          Positioned(
            bottom: -200,
            right: -140,
            child: _GlowOrb(
              size: 520,
              color: BrandColors.aqua.withValues(alpha: 0.28),
            ),
          ),
          Positioned(
            top: 120,
            right: 60,
            child: _LinearHalo(width: 280, height: 280),
          ),
        ],
        Positioned.fill(
          child: Container(
            padding: padding ?? EdgeInsets.zero,
            child: child,
          ),
        ),
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;
  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0.0)],
            stops: const [0, 1],
          ),
        ),
      ),
    );
  }
}

class _LinearHalo extends StatelessWidget {
  final double width;
  final double height;
  const _LinearHalo({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width / 2),
          gradient: BrandGradients.halo,
        ),
      ),
    );
  }
}

class BrandScaffold extends StatelessWidget {
  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool centerTitle;
  final bool heroBackground;
  final EdgeInsetsGeometry padding;

  const BrandScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.centerTitle = false,
    this.heroBackground = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
  });

  @override
  Widget build(BuildContext context) {
    return BrandBackground(
      withHeroOverlay: heroBackground,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: title == null
            ? null
            : AppBar(
                title: Text(
                  title!,
                  style: heroBackground
                      ? Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: Colors.white)
                      : null,
                ),
                actions: actions,
                centerTitle: centerTitle,
                backgroundColor: Colors.transparent,
                foregroundColor: heroBackground ? Colors.white : null,
                iconTheme: heroBackground
                    ? const IconThemeData(color: Colors.white)
                    : null,
              ),
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
        body: SafeArea(
          child: Padding(
            padding: padding,
            child: body,
          ),
        ),
      ),
    );
  }
}

class FrostedPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final List<BoxShadow>? shadows;
  final double? width;

  const FrostedPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(32),
    this.margin,
    this.borderRadius = BrandRadii.large,
    this.shadows,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        gradient: BrandGradients.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: BrandColors.primary.withValues(alpha: 0.08), width: 1),
        boxShadow: shadows ?? BrandShadows.surface,
      ),
      child: child,
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool expand;
  final double borderRadius;

  const PrimaryButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
    this.expand = true,
    this.borderRadius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(borderRadius);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.6,
      child: SizedBox(
        width: expand ? double.infinity : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: BrandGradients.primary(enabled),
            borderRadius: radius,
            boxShadow: BrandShadows.primaryButton(enabled),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: onPressed,
              child: Padding(
                padding: padding,
                child: DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        letterSpacing: 0.25,
                      ) ??
                      const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                  textAlign: TextAlign.center,
                  child: Center(child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool expand;
  final double borderRadius;

  const SecondaryButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
    this.expand = true,
    this.borderRadius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(borderRadius);
    return SizedBox(
      width: expand ? double.infinity : null,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.5), width: 1.2),
          textStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scheme.primary,
                letterSpacing: 0.2,
              ),
        ),
        child: child,
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? caption;
  final Widget? trailing;
  final CrossAxisAlignment alignment;

  const SectionHeader({
    super.key,
    required this.title,
    this.caption,
    this.trailing,
    this.alignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: alignment,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineSmall,
              ),
              if (caption != null) ...[
                const SizedBox(height: BrandSpacing.xs),
                Text(
                  caption!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: BrandSpacing.sm),
          trailing!,
        ],
      ],
    );
  }
}

class InfoBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const InfoBadge({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(BrandRadii.pill),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  letterSpacing: 0.2,
                ),
          ),
        ],
      ),
    );
  }
}
