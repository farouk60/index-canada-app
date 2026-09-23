import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/widgets/engagement_visibility_tracker.dart';

void main() {
  testWidgets(
    'qualifie une impression apres une seconde a au moins 50 pour cent',
    (tester) async {
      var impressions = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EngagementVisibilityTracker(
              onQualifiedVisibility: () => impressions++,
              child: const SizedBox(width: 200, height: 100),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 999));
      expect(impressions, isZero);

      await tester.pump(const Duration(milliseconds: 101));
      expect(impressions, 1);

      await tester.pump(const Duration(seconds: 2));
      expect(impressions, 1, reason: 'une instance ne compte qu une fois');
    },
  );

  testWidgets('exige une seconde de visibilite continue', (tester) async {
    var impressions = 0;
    final top = ValueNotifier<double>(0);
    addTearDown(top.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<double>(
            valueListenable: top,
            builder: (context, value, child) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: value,
                    left: 0,
                    child: EngagementVisibilityTracker(
                      onQualifiedVisibility: () => impressions++,
                      child: const SizedBox(width: 200, height: 100),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    top.value = -60;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(impressions, isZero);

    top.value = 0;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 999));
    expect(impressions, isZero);

    await tester.pump(const Duration(milliseconds: 101));
    expect(impressions, 1);
  });

  testWidgets('detecte une apparition par defilement sous RepaintBoundary', (
    tester,
  ) async {
    var impressions = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: Column(
              children: [
                const SizedBox(height: 650),
                RepaintBoundary(
                  child: EngagementVisibilityTracker(
                    onQualifiedVisibility: () => impressions++,
                    child: const SizedBox(width: 200, height: 100),
                  ),
                ),
                const SizedBox(height: 650),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 2));
    expect(impressions, isZero);

    controller.jumpTo(500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(impressions, 1);
  });

  testWidgets('ne compte pas lorsque la route est masquee', (tester) async {
    var impressions = 0;
    late BuildContext pageContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return Scaffold(
              body: EngagementVisibilityTracker(
                onQualifiedVisibility: () => impressions++,
                child: const SizedBox(width: 200, height: 100),
              ),
            );
          },
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    Navigator.of(pageContext).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SizedBox.expand()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(impressions, isZero);

    Navigator.of(pageContext).pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(impressions, 1);
  });

  testWidgets('reinitialise la duree lorsque l application est en pause', (
    tester,
  ) async {
    var impressions = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EngagementVisibilityTracker(
            onQualifiedVisibility: () => impressions++,
            child: const SizedBox(width: 200, height: 100),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 900));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    await tester.pump(const Duration(milliseconds: 200));
    expect(impressions, isZero);

    await tester.pump(const Duration(milliseconds: 900));
    expect(impressions, 1);
  });

  testWidgets('ne compte pas un enfant cache par un IndexedStack', (
    tester,
  ) async {
    var impressions = 0;
    final selectedIndex = ValueNotifier<int>(0);
    addTearDown(selectedIndex.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: selectedIndex,
            builder: (context, value, child) => IndexedStack(
              index: value,
              children: [
                EngagementVisibilityTracker(
                  onQualifiedVisibility: () => impressions++,
                  child: const SizedBox(width: 200, height: 100),
                ),
                const SizedBox.expand(),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    selectedIndex.value = 1;
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(impressions, isZero);

    selectedIndex.value = 0;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(impressions, 1);
  });

  testWidgets('respecte exactement le seuil de cinquante pour cent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var impressions = 0;
    final top = ValueNotifier<double>(550.1);
    addTearDown(top.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<double>(
            valueListenable: top,
            builder: (context, value, child) => Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: value,
                  child: EngagementVisibilityTracker(
                    onQualifiedVisibility: () => impressions++,
                    child: const SizedBox(width: 200, height: 100),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 2));
    expect(impressions, isZero);

    top.value = 550;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(impressions, 1);
  });
}
