import 'package:flutter/foundation.dart';

/// Canal de commande minimal pour revenir à un onglet de la navigation racine.
///
/// Il ne conserve pas l’état visuel : chaque demande est consommée une fois par
/// `MainNavigationPage`, ce qui évite d’empiler une nouvelle page autonome.
final class MainNavigationController extends ChangeNotifier {
  MainNavigationController._();

  static final MainNavigationController instance = MainNavigationController._();

  static const int servicesDestination = 1;
  static const int destinationCount = 4;

  int? _pendingDestination;

  void requestDestination(int index) {
    if (index < 0 || index >= destinationCount) {
      throw ArgumentError.value(index, 'index', 'Destination invalide');
    }
    _pendingDestination = index;
    notifyListeners();
  }

  int? takePendingDestination() {
    final destination = _pendingDestination;
    _pendingDestination = null;
    return destination;
  }
}
