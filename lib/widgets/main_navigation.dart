import 'package:flutter/material.dart';
import '../services/localization_service.dart';
import '../pages/home_page.dart';
import '../pages/services_page.dart';
import '../pages/partners_page.dart';
import '../pages/favorites_page.dart';

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  final LocalizationService _localizationService = LocalizationService();
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const HomePage(),
    const ServicesPage(),
    const PartnersPage(),
    const FavoritesPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: Colors.blue.shade600,
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home),
            label: _localizationService.tr('home'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.search),
            label: _localizationService.tr('services'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.business),
            label: _localizationService.tr('partners'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.favorite),
            label: _localizationService.tr('favorites'),
          ),
        ],
      ),
    );
  }
}
