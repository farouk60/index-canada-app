import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/services/localization_service.dart';
import 'package:index_canada/theme/app_theme.dart';
import 'package:index_canada/widgets/home_discovery_hero.dart';
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
}
