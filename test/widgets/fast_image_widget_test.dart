import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/widgets/fast_image_widget.dart';

void main() {
  Widget subject(String imageUrl) {
    return MaterialApp(
      home: Scaffold(
        body: FastImageWidget(
          imageUrl: imageUrl,
          errorWidget: const Text('image indisponible'),
        ),
      ),
    );
  }

  testWidgets('affiche le repli quand l’URL est vide', (tester) async {
    await tester.pumpWidget(subject(''));

    expect(find.text('image indisponible'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejette une data URL base64 invalide sans planter', (
    tester,
  ) async {
    await tester.pumpWidget(subject('data:image/png;base64,%%%'));

    expect(find.text('image indisponible'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
