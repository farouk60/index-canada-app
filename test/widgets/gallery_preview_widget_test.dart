import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/services/localization_service.dart';
import 'package:index_canada/widgets/gallery_preview_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offre une cible de 48 px et un libellé vocal localisé', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await LocalizationService().setLanguage('fr');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GalleryPreviewWidget(
            images: const ['https://example.invalid/gallery.jpg'],
            size: 40,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(GalleryPreviewWidget)),
      const Size.square(48),
    );
    expect(find.bySemanticsLabel('Ouvrir la galerie, 1 image'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accepte un libellé vocal fourni par le parent', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GalleryPreviewWidget(
            images: const ['https://example.invalid/gallery.jpg'],
            semanticLabel: 'Galerie du cabinet Exemple',
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Galerie du cabinet Exemple'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
