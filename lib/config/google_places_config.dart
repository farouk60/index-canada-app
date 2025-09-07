// Deprecated: Google Places integration removed.
// This stub remains only to avoid import errors if referenced by mistake.
@Deprecated('Google Places integration was removed; do not use.')
class GooglePlacesConfig {
  const GooglePlacesConfig();
  static String get apiKey => throw UnimplementedError('Google Places removed');
  static String get baseUrl => throw UnimplementedError('Google Places removed');
  static String get autocompleteEndpoint => throw UnimplementedError('Google Places removed');
  static String get detailsEndpoint => throw UnimplementedError('Google Places removed');
  static String get defaultCountry => 'ca';
  static String get defaultLanguage => 'fr';
  static String get defaultTypes => 'address';
  static bool get isConfigured => false;
}
