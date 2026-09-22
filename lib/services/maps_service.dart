import 'package:url_launcher/url_launcher.dart';

final class MapsService {
  MapsService._internal();

  static final MapsService instance = MapsService._internal();

  /// Ouvrir Google Maps avec une adresse
  Future<bool> openGoogleMaps(String address) async {
    try {
      final uri = Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': address.trim(),
      });

      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  /// Ouvrir Google Maps avec des coordonnées lat/lng
  Future<bool> openGoogleMapsWithCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      final uri = Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': '$latitude,$longitude',
      });

      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  /// Ouvrir l'application Maps native (iOS) ou Google Maps (Android)
  Future<bool> openNativeMaps(String address) async {
    try {
      final normalizedAddress = address.trim();
      final iosUri = Uri(
        scheme: 'maps',
        queryParameters: {'q': normalizedAddress},
      );
      final androidUri = Uri(
        scheme: 'geo',
        path: '0,0',
        queryParameters: {'q': normalizedAddress},
      );

      if (await canLaunchUrl(iosUri)) {
        return await launchUrl(iosUri, mode: LaunchMode.externalApplication);
      }
      if (await canLaunchUrl(androidUri)) {
        return await launchUrl(
          androidUri,
          mode: LaunchMode.externalApplication,
        );
      }
      return await openGoogleMaps(address);
    } catch (_) {
      return await openGoogleMaps(address);
    }
  }
}
