import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/models.dart';
import 'package:index_canada/widgets/coupon_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Professionnel professionnelAvecCoupon() => Professionnel(
    id: 'pro_123',
    title: 'Entreprise test',
    subtitle: '',
    ville: 'Montreal',
    address: '',
    numroDeTlphone: '',
    image: '',
    gallery: const [],
    sousCategorie: 'cat_123',
    plan: 'premium',
    couponTitle: 'Rabais test',
    couponCode: 'SECRET-NE-DOIT-PAS-ETRE-TRACE',
    couponExpirationDate: DateTime.now().add(const Duration(days: 30)),
  );

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('notifie la copie uniquement apres le succes du presse-papiers', (
    tester,
  ) async {
    var copies = 0;
    var clipboardWrites = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWrites++;
          }
          return null;
        });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CouponWidget(
              professionnel: professionnelAvecCoupon(),
              onCouponCopied: () => copies++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pump();

    expect(clipboardWrites, 1);
    expect(copies, 1);
  });

  testWidgets('ne notifie pas la copie lorsque le presse-papiers echoue', (
    tester,
  ) async {
    var copies = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'clipboard_unavailable');
          }
          return null;
        });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CouponWidget(
              professionnel: professionnelAvecCoupon(),
              onCouponCopied: () => copies++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pump();

    expect(copies, isZero);
  });
}
