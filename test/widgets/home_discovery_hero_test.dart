import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/models/wix_partner_models.dart';
import 'package:index_canada/services/localization_service.dart';
import 'package:index_canada/theme/app_theme.dart';
import 'package:index_canada/widgets/fast_image_widget.dart';
import 'package:index_canada/widgets/home_discovery_hero.dart';
import 'package:index_canada/widgets/wix_partner_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'le hero mobile présente le parcours principal sans débordement',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await LocalizationService().setLanguage('fr');
      var explored = false;

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: HomeDiscoveryHero(onExplore: () => explored = true),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('LE REPÈRE CANADIEN'), findsOneWidget);
      expect(find.text('Trouver un service'), findsOneWidget);
      await tester.tap(find.text('Trouver un service'));
      expect(explored, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('le rail partenaires reste horizontal sur un écran étroit', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(260, 360);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: HomePartnerRail(
              children: List.generate(
                5,
                (index) => ColoredBox(
                  color: AppTheme.snow,
                  child: Center(child: Text('Partenaire $index')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('home_partners_list')), findsOneWidget);
    expect(
      tester
          .widget<ListView>(find.byKey(const Key('home_partners_list')))
          .scrollDirection,
      Axis.horizontal,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('un logo partenaire rectangulaire reste centré et contenu', (
    tester,
  ) async {
    const partner = WixPartner(
      id: 'desjardins',
      title: 'Desjardins',
      titleEn: 'Desjardins',
      description: '',
      descriptionEn: '',
      logo: 'https://example.invalid/desjardins-2x1.png',
      category: 'banque',
      website: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(child: WixPartnerCard(partner: partner)),
        ),
      ),
    );
    await tester.pump();

    final canvasFinder = find.byKey(
      const ValueKey('partner_logo_canvas_desjardins'),
    );
    final imageFinder = find.descendant(
      of: canvasFinder,
      matching: find.byType(FastImageWidget),
    );
    final canvas = tester.widget<Container>(canvasFinder);
    final image = tester.widget<FastImageWidget>(imageFinder);
    final decoration = canvas.decoration! as BoxDecoration;

    expect(canvas.alignment, Alignment.center);
    expect(canvas.padding, const EdgeInsets.all(10));
    expect(decoration.color, isNotNull);
    expect(decoration.border, isNotNull);
    expect(image.fit, BoxFit.contain);
    expect(tester.getCenter(imageFinder), tester.getCenter(canvasFinder));
    expect(tester.takeException(), isNull);
  });
}
