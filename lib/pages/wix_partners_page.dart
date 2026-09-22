import 'dart:async';

import 'package:flutter/material.dart';

import '../data_service.dart';
import '../models/wix_partner_models.dart';
import '../services/localization_service.dart';
import '../widgets/language_selector.dart';
import '../widgets/wix_partner_widgets.dart';

class WixPartnersPage extends StatefulWidget {
  const WixPartnersPage({super.key});

  @override
  State<WixPartnersPage> createState() => _WixPartnersPageState();
}

class _WixPartnersPageState extends State<WixPartnersPage> {
  final DataService _dataService = DataService();
  final LocalizationService _localizationService = LocalizationService();

  List<WixPartner> _partners = const [];
  List<String> _categories = const [];
  String? _selectedCategory;
  bool _isLoading = true;
  bool _hasLoadError = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _localizationService.addListener(_handleLanguageChanged);
    unawaited(_loadData());
  }

  @override
  void dispose() {
    _localizationService.removeListener(_handleLanguageChanged);
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;

    setState(() {
      _categories = _sortedCategories(_categories);
    });
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (!mounted) return;

    final loadGeneration = ++_loadGeneration;
    final hadPartners = _partners.isNotEmpty;
    setState(() {
      _isLoading = !hadPartners;
      _hasLoadError = false;
    });

    try {
      final partners = await _dataService.fetchPartners(
        forceRefresh: forceRefresh,
      );
      final categories = _sortedCategories(
        partners
            .map((partner) => partner.category.trim())
            .where((category) => category.isNotEmpty)
            .toSet(),
      );

      if (!mounted || loadGeneration != _loadGeneration) return;

      setState(() {
        _partners = List.unmodifiable(partners);
        _categories = List.unmodifiable(categories);
        if (_selectedCategory != null &&
            !_categories.contains(_selectedCategory)) {
          _selectedCategory = null;
        }
        _isLoading = false;
      });
    } on Exception {
      if (!mounted || loadGeneration != _loadGeneration) return;

      setState(() {
        _isLoading = false;
        _hasLoadError = !hadPartners;
      });

      if (hadPartners) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(_localizationService.tr('error_loading_partners')),
          ),
        );
      }
    }
  }

  List<String> _sortedCategories(Iterable<String> categories) {
    final sorted = categories.toList();
    sorted.sort(
      (first, second) =>
          _categoryLabel(first).compareTo(_categoryLabel(second)),
    );
    return sorted;
  }

  String _categoryLabel(String category) {
    return PartnerCategory.getCategoryById(category)
            ?.getNameInLanguage(_localizationService.currentLanguage) ??
        category;
  }

  List<WixPartner> get _filteredPartners {
    final category = _selectedCategory;
    if (category == null) return _partners;
    return _partners
        .where((partner) => partner.category == category)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const ExcludeSemantics(
              child: Text('🤝', style: TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: 8),
            Text(_localizationService.tr('our_partners')),
          ],
        ),
        actions: const [LanguageSelector()],
      ),
      body: Column(
        children: [
          if (_partners.isNotEmpty) _buildStatsHeader(),
          if (_categories.isNotEmpty) _buildCategoryFilter(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Semantics(
        liveRegion: true,
        label: _localizationService.tr('loading'),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_hasLoadError) {
      return _buildRefreshableState(
        icon: Icons.cloud_off_outlined,
        message: _localizationService.tr('error_loading_partners'),
        actionLabel: _localizationService.tr('retry'),
        onAction: () => unawaited(_loadData(forceRefresh: true)),
      );
    }

    final filteredPartners = _filteredPartners;
    if (filteredPartners.isEmpty) {
      return _buildRefreshableState(
        icon: Icons.business_outlined,
        message: _selectedCategory != null
            ? _localizationService.tr('no_partners_in_category')
            : _localizationService.tr('no_partners_available'),
        actionLabel: _selectedCategory == null
            ? null
            : _localizationService.tr('show_all_partners'),
        onAction: _selectedCategory == null
            ? null
            : () {
                setState(() {
                  _selectedCategory = null;
                });
              },
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: filteredPartners.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final partner = filteredPartners[index];
          return WixPartnerListCard(
            key: ValueKey(partner.id),
            partner: partner,
          );
        },
      ),
    );
  }

  Widget _buildRefreshableState({
    required IconData icon,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 64, color: colorScheme.outline),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    if (actionLabel != null && onAction != null) ...[
                      const SizedBox(height: 20),
                      FilledButton.tonal(
                        onPressed: onAction,
                        child: Text(actionLabel),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader() {
    final featuredCount = _partners
        .where((partner) => partner.isFeatured)
        .length;
    final officialCount = _partners
        .where((partner) => partner.isOfficial)
        .length;
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(color: colorScheme.primary),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Row(
            children: [
              _PartnerStat(
                icon: Icons.business_outlined,
                count: _partners.length,
                label: _localizationService.tr('partners'),
              ),
              _PartnerStat(
                icon: Icons.star_outline_rounded,
                count: featuredCount,
                label: _localizationService.tr('featured'),
              ),
              _PartnerStat(
                icon: Icons.verified_outlined,
                count: officialCount,
                label: _localizationService.tr('official'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _buildCategoryChip(null, _localizationService.tr('all_categories')),
          ..._categories.map((category) {
            final categoryInfo = PartnerCategory.getCategoryById(category);
            final icon = categoryInfo?.icon ?? '📋';
            return _buildCategoryChip(
              category,
              '$icon ${_categoryLabel(category)}',
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String? category, String label) {
    final isSelected = _selectedCategory == category;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        showCheckmark: true,
        onSelected: (selected) {
          setState(() {
            _selectedCategory = selected ? category : null;
          });
        },
      ),
    );
  }
}

class _PartnerStat extends StatelessWidget {
  const _PartnerStat({
    required this.icon,
    required this.count,
    required this.label,
  });

  final IconData icon;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: Semantics(
        label: '$count $label',
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: colorScheme.onPrimary, size: 24),
              const SizedBox(height: 4),
              Text(
                '$count',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onPrimary.withValues(alpha: 0.82),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
