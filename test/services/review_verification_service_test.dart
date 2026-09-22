import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/services/review_verification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('un avis local ne conserve jamais le nom en clair', () async {
    final service = ReviewVerificationService();

    await service.recordReviewPost(
      'professional-1',
      'Alice Example',
      'Un service rapide et vraiment professionnel.',
    );

    final preferences = await SharedPreferences.getInstance();
    final reviewKey = preferences.getKeys().singleWhere(
      (key) =>
          key.startsWith('review_') && key != 'review_verification_salt_v1',
    );
    final stored = preferences.getString(reviewKey)!;
    final payload = jsonDecode(stored) as Map<String, dynamic>;

    expect(payload.containsKey('authorName'), isFalse);
    expect(stored.toLowerCase(), isNot(contains('alice')));

    final result = await service.canPostReview(
      'professional-2',
      'Alice Example',
      'Une autre expérience détaillée et constructive.',
      'Très bon service',
    );
    expect(result.canPost, isFalse);
    expect(result.code, ReviewVerificationCode.cooldown);
    expect(result.remainingMinutes, greaterThan(0));
    expect(preferences.containsKey('review_verification_salt_v1'), isTrue);
  });

  test('les tentatives bloquées utilisent un code et aucun nom brut', () async {
    final service = ReviewVerificationService();

    final result = await service.canPostReview(
      'professional-1',
      'Bob Example',
      'Visitez https://example.com pour une promotion immédiate.',
      'Offre',
    );

    expect(result.canPost, isFalse);
    expect(result.code, ReviewVerificationCode.suspiciousContent);

    final preferences = await SharedPreferences.getInstance();
    final blockedKey = preferences.getKeys().singleWhere(
      (key) => key.startsWith('blocked_review_'),
    );
    final stored = preferences.getString(blockedKey)!;
    final payload = jsonDecode(stored) as Map<String, dynamic>;

    expect(payload['reason'], 'suspiciousContent');
    expect(payload.containsKey('authorName'), isFalse);
    expect(stored.toLowerCase(), isNot(contains('bob')));
  });

  test(
    'le nettoyage retire les anciennes traces et anonymise les récentes',
    () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final old = now - const Duration(hours: 25).inMilliseconds;
      SharedPreferences.setMockInitialValues(<String, Object>{
        'blocked_review_old': jsonEncode(<String, Object>{
          'timestamp': old,
          'reason': 'legacy',
          'authorName': 'Ancien nom',
        }),
        'blocked_review_recent': jsonEncode(<String, Object>{
          'timestamp': now,
          'reason': 'legacy',
          'authorName': 'Nom récent',
        }),
      });

      await ReviewVerificationService().recordReviewPost(
        'professional-1',
        'Carol Example',
        'Une intervention claire, rapide et très professionnelle.',
      );

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey('blocked_review_old'), isFalse);
      final recent = jsonDecode(
        preferences.getString('blocked_review_recent')!,
      ) as Map<String, dynamic>;
      expect(recent.containsKey('authorName'), isFalse);
    },
  );
}
