import 'package:flutter/material.dart';

import '../services/localization_service.dart';
import '../theme/app_theme.dart';

class HomeDiscoveryHero extends StatelessWidget {
  const HomeDiscoveryHero({required this.onExplore, super.key});

  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final localization = LocalizationService();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? colorScheme.surfaceContainerHighest : AppTheme.ink,
          borderRadius: BorderRadius.circular(AppRadii.dialog),
          border: Border.all(
            color: isDark
                ? colorScheme.outlineVariant
                : AppTheme.snow.withValues(alpha: 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.ink.withValues(alpha: isDark ? 0.18 : 0.14),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
          child: Stack(
            children: [
              PositionedDirectional(
                top: 0,
                bottom: 0,
                start: 0,
                child: Container(width: 6, color: AppTheme.mapleRed),
              ),
              PositionedDirectional(
                top: -36,
                end: -28,
                child: ExcludeSemantics(
                  child: Icon(
                    Icons.explore_rounded,
                    size: 152,
                    color: AppTheme.snow.withValues(alpha: 0.06),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(
                  MediaQuery.sizeOf(context).width < 360
                      ? AppSpacing.sm
                      : AppSpacing.lg,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = MediaQuery.sizeOf(context).width < 360;
                    final largeText =
                        MediaQuery.textScalerOf(context).scale(16) >= 21;
                    final isWide = constraints.maxWidth >= 720 && !largeText;
                    final logo = _BrandMark(size: isCompact ? 56 : 72);
                    final message = _HeroMessage(
                      eyebrow: localization.tr('home_eyebrow'),
                      title: localization.tr('welcome_title'),
                      subtitle: localization.tr('welcome_subtitle'),
                      browseHint: localization.tr('home_browse_hint'),
                      textTheme: textTheme,
                    );
                    final action = FilledButton.icon(
                      onPressed: onExplore,
                      icon: const Icon(Icons.search_rounded),
                      label: Text(localization.tr('explore_services')),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.mapleRedDark,
                        foregroundColor: AppTheme.snow,
                      ),
                    );

                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          logo,
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(child: message),
                          const SizedBox(width: AppSpacing.lg),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 190),
                            child: action,
                          ),
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        logo,
                        SizedBox(
                          height: isCompact ? AppSpacing.xs : AppSpacing.md,
                        ),
                        message,
                        SizedBox(
                          height: isCompact ? AppSpacing.sm : AppSpacing.lg,
                        ),
                        SizedBox(width: double.infinity, child: action),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeLoadErrorBanner extends StatelessWidget {
  const HomeLoadErrorBanner({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final localization = LocalizationService();

    return Semantics(
      liveRegion: true,
      child: Card(
        color: colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final message = Row(
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    color: colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      localization.tr('loading_error'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              );
              final retryButton = TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(localization.tr('retry')),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.onErrorContainer,
                ),
              );

              if (constraints.maxWidth < 440) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    message,
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: retryButton,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: message),
                  const SizedBox(width: AppSpacing.sm),
                  retryButton,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Index Canada',
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.control),
            color: AppTheme.snow,
            border: Border.all(color: AppTheme.snow.withValues(alpha: 0.72)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: ExcludeSemantics(
              child: Image.asset(
                'assets/images/store.png',
                fit: BoxFit.contain,
                cacheWidth: 176,
                cacheHeight: 176,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroMessage extends StatelessWidget {
  const _HeroMessage({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.browseHint,
    required this.textTheme,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final String browseHint;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.trustTeal,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            child: Text(
              eyebrow.toUpperCase(),
              style: textTheme.labelSmall?.copyWith(
                color: AppTheme.snow,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          header: true,
          child: Text(
            title,
            style: textTheme.headlineSmall?.copyWith(color: AppTheme.snow),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: textTheme.bodyLarge?.copyWith(
            color: AppTheme.snow.withValues(alpha: 0.82),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.tune_rounded,
                size: 18,
                color: AppTheme.trustTeal,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                browseHint,
                style: textTheme.bodySmall?.copyWith(
                  color: AppTheme.snow.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Horizontally scrollable partner rail with stable card dimensions at every
/// breakpoint. A rail avoids the fixed three-column overflow of the former
/// implementation while keeping partner logos easy to scan.
class HomePartnerRail extends StatelessWidget {
  const HomePartnerRail({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemsPerViewport = constraints.maxWidth < 480 ? 2.2 : 4.4;
        final itemWidth =
            ((constraints.maxWidth - AppSpacing.md) / itemsPerViewport)
                .clamp(112.0, 152.0)
                .toDouble();

        return SizedBox(
          height: 116,
          child: ListView.separated(
            key: const Key('home_partners_list'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) =>
                SizedBox(width: itemWidth, height: 116, child: children[index]),
          ),
        );
      },
    );
  }
}
