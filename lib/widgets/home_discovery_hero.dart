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

    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.surface,
              colorScheme.primaryContainer.withValues(alpha: 0.58),
            ],
          ),
          borderRadius: BorderRadius.circular(AppRadii.dialog),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 12),
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
                child: Container(width: 6, color: colorScheme.primary),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 640;
                    const logo = _BrandMark();
                    final message = _HeroMessage(
                      title: localization.tr('welcome_title'),
                      subtitle: localization.tr('welcome_subtitle'),
                      textTheme: textTheme,
                      colorScheme: colorScheme,
                    );
                    final action = FilledButton.icon(
                      onPressed: onExplore,
                      icon: const Icon(Icons.search_rounded),
                      label: Text(localization.tr('explore_services')),
                    );

                    if (isWide) {
                      return Row(
                        children: [
                          logo,
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(child: message),
                          const SizedBox(width: AppSpacing.lg),
                          action,
                        ],
                      );
                    }

                    return Column(
                      children: [
                        logo,
                        const SizedBox(height: AppSpacing.md),
                        message,
                        const SizedBox(height: AppSpacing.lg),
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
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Index Canada',
      child: ExcludeSemantics(
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
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
    required this.title,
    required this.subtitle,
    required this.textTheme,
    required this.colorScheme,
  });

  final String title;
  final String subtitle;
  final TextTheme textTheme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
