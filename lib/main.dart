import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'pages/home_page.dart';
import 'theme/app_theme.dart';
import 'services/localization_service.dart';
import 'services/firebase_analytics_service.dart';
import 'services/ios_optimization_service.dart';

void main() async {
  // S'assurer que les widgets sont initialisés
  WidgetsFlutterBinding.ensureInitialized();

  // Configuration complète des optimisations iOS
  await IOSOptimizationService.configureIOSOptimizations();

  // Initialiser Firebase Analytics
  await FirebaseAnalyticsService().initialize();

  // Charger la langue sauvegardée
  await LocalizationService().loadSavedLanguage();

  // Initialiser Stripe avec votre clé publique et configuration complète
  try {
    Stripe.publishableKey =
        'pk_live_51IB8spJeQ0XvzjbEFaXNXaJHIXI7xBHCV9cECWNT92HNaymfrF4XV58NdbxkAcviydgGa9dZwiqSFEzwLAlsPK8U00K0shyiR9';

    await Stripe.instance.applySettings();
  } catch (e) {
    // Continue sans bloquer l'app - les fonctionnalités de paiement seront désactivées
  }

  // Optimiser le cache des images (plus conservateur sur mobile)
  CachedNetworkImage.logLevel = CacheManagerLogLevel.none;
  PaintingBinding.instance.imageCache.maximumSize = 200; // était 500
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20; // ~50MB

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Index',
  theme: AppTheme.light(),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
      // Optimisations pour iOS et performances
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              1.0,
            ), // Éviter les problèmes de scale iOS
          ),
          child: child!,
        );
      },
    );
  }
}
