import 'package:animal_dash/main.dart' as app;
import 'package:animal_dash/game_canvas.dart';
import 'package:animal_dash/purchases.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const device = String.fromEnvironment(
    'SCREENSHOT_DEVICE',
    defaultValue: 'device',
  );

  testWidgets('capture real title, running and jump screens', (tester) async {
    await app.main();
    await Future<void>.delayed(const Duration(seconds: 4));
    await tester.pump();
    expect(
      AdFreePurchase.instance.ready,
      isTrue,
      reason: 'Native StoreKit entitlement channel must respond on iOS',
    );
    expect(find.text('スタート'), findsOneWidget);
    await binding.takeScreenshot('${device}_01_title');

    await tester.tap(find.text('広告を削除・購入を復元'));
    await Future<void>.delayed(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('購入を復元'), findsOneWidget);
    await binding.takeScreenshot('${device}_04_iap');
    await tester.tap(find.text('閉じる'));
    await tester.pump();

    await tester.tap(find.text('スタート'));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
    await tester.tap(find.byTooltip('一時停止'));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('つづける'), findsOneWidget);
    await binding.takeScreenshot('${device}_05_pause');
    await tester.tap(find.text('つづける'));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('つづける'), findsNothing);
    await binding.takeScreenshot('${device}_02_run');

    await tester.tapAt(tester.getRect(find.byType(GameCanvas)).center);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.text('ドカーン！'), findsNothing);
    await binding.takeScreenshot('${device}_03_jump');
  });
}
