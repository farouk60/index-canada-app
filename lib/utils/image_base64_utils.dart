import 'dart:async';
import 'dart:convert';
import 'package:image/image.dart' as img;

/// Rough byte size estimation from a Base64 string (without data URL header)
int _base64SizeBytes(String base64) {
  final sanitized = base64.trim();
  // Remove data URL prefix if present
  final comma = sanitized.indexOf(',');
  final pure = comma > 0 && sanitized.substring(0, comma).contains('base64')
      ? sanitized.substring(comma + 1)
      : sanitized;
  final len = pure.length;
  if (len == 0) return 0;
  // Base64 encodes 3 bytes as 4 chars; account for padding
  final padding = pure.endsWith('==')
      ? 2
      : pure.endsWith('=')
          ? 1
          : 0;
  return ((len * 3) / 4).floor() - padding;
}

String _stripDataUrl(String base64) {
  final idx = base64.indexOf(',');
  if (idx > 0 && base64.substring(0, idx).contains('base64')) {
    return base64.substring(idx + 1);
  }
  return base64;
}

/// Compress a Base64 image targeting given constraints. Returns Base64 (no data URL).
Future<String> compressBase64(
  String base64, {
  int maxWidth = 800,
  int maxHeight = 800,
  int maxKB = 50,
  int minQuality = 55,
  int startQuality = 85,
}) async {
  try {
    if (base64.trim().isEmpty) return base64;
    // Early exit if already under size threshold
    if ((_base64SizeBytes(base64) / 1024).ceil() <= maxKB) {
      return _stripDataUrl(base64);
    }

    final raw = base64Decode(_stripDataUrl(base64));
    final decoded = img.decodeImage(raw);
    if (decoded == null) return _stripDataUrl(base64);

    // Resize if needed
    img.Image processed = decoded;
    if (decoded.width > maxWidth || decoded.height > maxHeight) {
      processed = img.copyResize(
        decoded,
        width: maxWidth,
        height: maxHeight,
        interpolation: img.Interpolation.average,
      );
    }

    int q = startQuality;
    List<int> jpeg = img.encodeJpg(processed, quality: q);

    // Decrease quality until we meet size, but not below minQuality
    int attempts = 0;
  while ((jpeg.length / 1024) > maxKB && q > minQuality && attempts < 6) {
      q -= 5;
      jpeg = img.encodeJpg(processed, quality: q);
      attempts++;
    }

    return base64Encode(jpeg);
  } catch (_) {
    // On failure, return original without data URL prefix
    return _stripDataUrl(base64);
  }
}

/// Compress multiple gallery images. Limits to first [limit] items.
Future<List<String>> compressGallery(
  List<String> gallery, {
  int limit = 5,
  int maxWidth = 1024,
  int maxHeight = 1024,
  int maxKB = 60,
}) async {
  if (gallery.isEmpty) return const [];
  final items = gallery.take(limit).toList();
  final List<String> out = [];
  for (final b64 in items) {
    out.add(await compressBase64(
      b64,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      maxKB: maxKB,
    ));
  }
  return out;
}
