import 'package:flutter/material.dart';

import '../pages/favorites_page.dart';
import '../pages/home_page.dart';
import '../pages/services_page.dart';
import '../pages/wix_partners_page.dart';
import '../services/localization_service.dart';
import '../services/main_navigation_controller.dart';
import '../theme/app_theme.dart';

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  static const double _railBreakpoint = 840;
  static const double _extendedRailBreakpoint = 1180;

  final LocalizationService _localizationService = LocalizationService();
  final MainNavigationController _navigationController =
      MainNavigationController.instance;

  int _currentIndex = 0;
  int _favoritesRevision = 0;

  List<Widget> get _pages => [
    HomePage(
      onExploreServices: () => _selectDestination(1),
      onOpenFavorites: () => _selectDestination(3),
    ),
    ServicesPage(),
    WixPartnersPage(),
    FavoritesPage(key: ValueKey(_favoritesRevision)),
  ];

  @override
  void initState() {
    super.initState();
    _localizationService.addListener(_handleLanguageChanged);
    _navigationController.addListener(_handleDestinationRequest);
    _handleDestinationRequest();
  }

  @override
  void dispose() {
    _localizationService.removeListener(_handleLanguageChanged);
    _navigationController.removeListener(_handleDestinationRequest);
    super.dispose();
  }

  void _handleDestinationRequest() {
    final destination = _navigationController.takePendingDestination();
    if (destination != null) {
      _selectDestination(destination);
    }
  }

  void _handleLanguageChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _selectDestination(int index) {
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
      if (index == 3) {
        _favoritesRevision++;
      }
    });
  }

  List<_AppDestination> get _destinations => [
    _AppDestination(
      label: _localizationService.tr('home'),
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _AppDestination(
      label: _localizationService.tr('services'),
      icon: Icons.search_outlined,
      selectedIcon: Icons.search_rounded,
    ),
    _AppDestination(
      label: _localizationService.tr('partners'),
      icon: Icons.handshake_outlined,
      selectedIcon: Icons.handshake_rounded,
    ),
    _AppDestination(
      label: _localizationService.tr('favorites'),
      icon: Icons.favorite_border_rounded,
      selectedIcon: Icons.favorite_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useNavigationRail = constraints.maxWidth >= _railBreakpoint;
        final extendNavigationRail =
            constraints.maxWidth >= _extendedRailBreakpoint;

        return Scaffold(
          body: useNavigationRail
              ? Row(
                  children: [
                    SafeArea(
                      right: false,
                      child: NavigationRail(
                        selectedIndex: _currentIndex,
                        onDestinationSelected: _selectDestination,
                        extended: extendNavigationRail,
                        minExtendedWidth: 224,
                        groupAlignment: -0.8,
                        labelType: extendNavigationRail
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.all,
                        leading: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.sm,
                            AppSpacing.sm,
                            AppSpacing.sm,
                            AppSpacing.lg,
                          ),
                          child: Semantics(
                            image: true,
                            label: 'Index Canada',
                            child: Image.asset(
                              'assets/images/store.png',
                              width: extendNavigationRail ? 64 : 48,
                              height: extendNavigationRail ? 64 : 48,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        destinations: _destinations
                            .map(
                              (destination) => NavigationRailDestination(
                                icon: Icon(destination.icon),
                                selectedIcon: Icon(destination.selectedIcon),
                                label: Text(destination.label),
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.xs,
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildPageStack()),
                  ],
                )
              : _buildPageStack(),
          bottomNavigationBar: useNavigationRail
              ? null
              : SafeArea(
                  top: false,
                  child: NavigationBar(
                    selectedIndex: _currentIndex,
                    onDestinationSelected: _selectDestination,
                    destinations: _destinations
                        .map(
                          (destination) => NavigationDestination(
                            icon: Icon(destination.icon),
                            selectedIcon: Icon(destination.selectedIcon),
                            label: destination.label,
                            tooltip: destination.label,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildPageStack() {
    return FocusTraversalGroup(
      child: IndexedStack(index: _currentIndex, children: _pages),
    );
  }
}

class _AppDestination {
  const _AppDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
