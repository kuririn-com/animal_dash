import 'package:animal_dash/ads.dart';
import 'package:animal_dash/game_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('interstitial is due after three games and remains due until shown', () {
    final schedule = InterstitialSchedule();
    schedule.completeGame();
    schedule.completeGame();
    expect(schedule.isDue, isFalse);
    schedule.completeGame();
    expect(schedule.isDue, isTrue);
    // No fill must not postpone the ad another three games.
    schedule.completeGame();
    expect(schedule.isDue, isTrue);
    schedule.didShowAd();
    expect(schedule.isDue, isFalse);
  });

  for (final screen in [const Size(568, 320), const Size(844, 390), const Size(1024, 768)]) {
    testWidgets('full game remains visible with banner at $screen', (tester) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const canvasKey = ValueKey('logical-canvas');
      const bannerKey = ValueKey('banner-space');
      int taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: screen,
            padding: const EdgeInsets.fromLTRB(44, 0, 44, 21)),
          child: Scaffold(body: SafeArea(child: Column(children: [
            Expanded(child: GameCanvas(child: GestureDetector(
              key: canvasKey,
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const ColoredBox(color: Colors.lightGreen),
            ))),
            const SizedBox(key: bannerKey, height: 50, width: double.infinity),
          ]))),
        ),
      ));
      final canvas = tester.renderObject<RenderBox>(find.byKey(canvasKey));
      final topLeft = canvas.localToGlobal(Offset.zero);
      final bottomRight = canvas.localToGlobal(Offset(canvas.size.width, canvas.size.height));
      final banner = tester.getRect(find.byKey(bannerKey));
      expect(topLeft.dx, greaterThanOrEqualTo(44 - 0.01));
      expect(topLeft.dy, greaterThanOrEqualTo(0));
      expect(bottomRight.dx, lessThanOrEqualTo(screen.width - 44 + 0.01));
      expect(bottomRight.dy, lessThanOrEqualTo(banner.top + 0.01));
      expect(canvas.size.height, greaterThan(400));
      // Input at the ground line must survive the viewport's scaling transform.
      await tester.tapAt(canvas.localToGlobal(const Offset(120, 390)));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
