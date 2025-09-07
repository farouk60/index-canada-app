import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Service simple pour décider si on doit précharger (prefetch) des images.
/// - Mode économie de données manuel (toggle global possible)
/// - Détection réseau basique: considère le cellulaire comme mesuré
class DataSaverService {
  DataSaverService._internal();
  static final DataSaverService instance = DataSaverService._internal();

  bool _manualDataSaver = false;
  void setManualDataSaver(bool enabled) => _manualDataSaver = enabled;
  bool get isManualDataSaver => _manualDataSaver;

  /// Considère les connexions cellulaires comme mesurées.
  Future<bool> isMeteredConnection() async {
    try {
      final result = await Connectivity().checkConnectivity();
      // Traiter plusieurs types comme potentiellement mesurés
      if (result.contains(ConnectivityResult.mobile) ||
          result.contains(ConnectivityResult.vpn) ||
          result.contains(ConnectivityResult.bluetooth)) {
        return true;
      }
      return false;
    } catch (_) {
      // En cas d'échec, être conservateur et considérer mesuré
      return true;
    }
  }

  /// Retourne true si on peut précharger sans risque
  Future<bool> shouldPrefetch() async {
    if (_manualDataSaver) return false;
    final metered = await isMeteredConnection();
    return !metered;
  }
}
