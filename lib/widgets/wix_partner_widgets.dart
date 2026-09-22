import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/wix_partner_models.dart';
import '../services/localization_service.dart';
import '../utils.dart';
import 'fast_image_widget.dart';

Uri? _parsePartnerWebsite(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final uri = Uri.tryParse(candidate);
  if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;

  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') return null;
  return uri;
}

Future<void> _launchPartnerWebsite(BuildContext context, Uri uri) async {
  var launched = false;
  try {
    launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Exception {
    launched = false;
  }

  if (launched || !context.mounted) return;

  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(LocalizationService().tr('error_opening_link'))),
  );
}

VoidCallback? _websiteAction(BuildContext context, Uri? uri) {
  if (uri == null) return null;
  return () => unawaited(_launchPartnerWebsite(context, uri));
}

class WixPartnerCarousel extends StatelessWidget {
  const WixPartnerCarousel({
    super.key,
    required this.partners,
    required this.title,
  });

  final List<WixPartner> partners;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (partners.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const ExcludeSemantics(
                  child: Text('🤝', style: TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: partners.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final partner = partners[index];
                return SizedBox(
                  key: ValueKey(partner.id),
                  width: 110,
                  child: _WixPartnerCard(partner: partner),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WixPartnerCard extends StatelessWidget {
  const _WixPartnerCard({required this.partner});

  final WixPartner partner;

  @override
  Widget build(BuildContext context) {
    final localization = LocalizationService();
    final title = partner.getTitleInLanguage(localization.currentLanguage);
    final websiteUri = _parsePartnerWebsite(partner.website);
    final actionLabel = '${localization.tr('visit_website')}: $title';
    final colorScheme = Theme.of(context).colorScheme;
    final onOpen = _websiteAction(context, websiteUri);

    return Tooltip(
      message: websiteUri == null ? title : actionLabel,
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        link: websiteUri != null,
        label: websiteUri == null ? title : actionLabel,
        onTap: onOpen,
        child: Material(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            excludeFromSemantics: true,
            onTap: onOpen,
            child: Ink(
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: _PartnerLogo(partner: partner, size: 90),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WixPartnerPromoBanner extends StatelessWidget {
  const WixPartnerPromoBanner({
    super.key,
    required this.partner,
    this.customTitle,
    this.customDescription,
  });

  final WixPartner partner;
  final String? customTitle;
  final String? customDescription;

  @override
  Widget build(BuildContext context) {
    final localization = LocalizationService();
    final title =
        customTitle ?? partner.getTitleInLanguage(localization.currentLanguage);
    final description =
        customDescription ??
        partner.getDescriptionInLanguage(localization.currentLanguage);
    final websiteUri = _parsePartnerWebsite(partner.website);
    final actionLabel = '${localization.tr('visit_website')}: $title';
    final colorScheme = Theme.of(context).colorScheme;
    final onOpen = _websiteAction(context, websiteUri);

    return Semantics(
      container: true,
      link: websiteUri != null,
      label: websiteUri == null
          ? '$title. $description'
          : '$actionLabel. $description',
      onTap: onOpen,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: colorScheme.primaryContainer,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          excludeFromSemantics: true,
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _PartnerLogo(partner: partner, size: 60),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onPrimaryContainer),
                        ),
                      ],
                    ],
                  ),
                ),
                if (websiteUri != null) ...[
                  const SizedBox(width: 12),
                  ExcludeSemantics(
                    child: Icon(
                      Icons.open_in_new_rounded,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WixPartnerListCard extends StatelessWidget {
  const WixPartnerListCard({super.key, required this.partner});

  final WixPartner partner;

  @override
  Widget build(BuildContext context) {
    final localization = LocalizationService();
    final language = localization.currentLanguage;
    final title = partner.getTitleInLanguage(language);
    final description = partner.getDescriptionInLanguage(language);
    final category =
        PartnerCategory.getCategoryById(partner.category)
            ?.getNameInLanguage(language) ??
        partner.category;
    final websiteUri = _parsePartnerWebsite(partner.website);
    final actionLabel = '${localization.tr('visit_website')}: $title';
    final colorScheme = Theme.of(context).colorScheme;
    final onOpen = _websiteAction(context, websiteUri);

    return Semantics(
      container: true,
      link: websiteUri != null,
      label: websiteUri == null
          ? '$title. $description'
          : '$actionLabel. $description',
      onTap: onOpen,
      child: Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: InkWell(
          excludeFromSemantics: true,
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PartnerLogo(partner: partner, size: 64),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (partner.isFeatured || partner.isOfficial) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (partner.isFeatured)
                              _PartnerBadge(
                                icon: Icons.star_rounded,
                                label: localization.tr('featured_badge'),
                                foreground: colorScheme.onTertiaryContainer,
                                background: colorScheme.tertiaryContainer,
                              ),
                            if (partner.isOfficial)
                              _PartnerBadge(
                                icon: Icons.verified_rounded,
                                label: localization.tr('official_partner'),
                                foreground: colorScheme.onPrimaryContainer,
                                background: colorScheme.primaryContainer,
                              ),
                          ],
                        ),
                      ],
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                      if (category.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          category,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (websiteUri != null) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: ExcludeSemantics(
                      child: Icon(
                        Icons.open_in_new_rounded,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WixPartnerCard extends StatelessWidget {
  const WixPartnerCard({super.key, required this.partner});

  final WixPartner partner;

  @override
  Widget build(BuildContext context) {
    return _WixPartnerCard(partner: partner);
  }
}

class _PartnerLogo extends StatelessWidget {
  const _PartnerLogo({required this.partner, required this.size});

  final WixPartner partner;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.business_rounded,
        color: colorScheme.onSurfaceVariant,
        size: size * 0.45,
      ),
    );

    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox.square(
          dimension: size,
          child: FastImageWidget(
            imageUrl: getValidImageUrl(partner.logo),
            width: size,
            height: size,
            fit: BoxFit.contain,
            placeholder: ColoredBox(
              color: colorScheme.surfaceContainerHighest,
              child: const Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            errorWidget: fallback,
          ),
        ),
      ),
    );
  }
}

class _PartnerBadge extends StatelessWidget {
  const _PartnerBadge({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: foreground, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
