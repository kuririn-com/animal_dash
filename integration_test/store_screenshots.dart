import 'package:animal_dash/main.dart' as app;
import 'package:animal_dash/game_canvas.dart';
import 'package:animal_dash/purchases.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const device = String.fromEnvironment(
    'SCREENSHOT_DEVICE',
    defaultValue: 'device',
  );

  testWidgets('capture real progression menu and pause/resume screens', (
    tester,
  ) async {
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
    await tester.pump();
    expect(find.text('購入を復元'), findsOneWidget);
    await tester.tap(find.text('閉じる'));
    await tester.pump();

    await tester.tap(find.text('コイン交換・もちもの'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('バリア　所持 0個'), findsOneWidget);
    await binding.takeScreenshot('${device}_02_exchange');
    await tester.tap(find.byTooltip('閉じる'));
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.text('スタート'));
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    await tester.pump();
    expect(find.text('ドカーン！'), findsNothing);
    await binding.takeScreenshot('${device}_03_run');

    await tester.tap(find.byTooltip('一時停止'));
    await tester.pump();
    final game = tester
        .widget<GameWidget<app.AnimalGame>>(
          find.byType(GameWidget<app.AnimalGame>),
        )
        .game;
    expect(game.state, app.GameState.paused);
    final pausedDistance = game.distance;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pump();
    expect(game.distance, pausedDistance);
    await binding.takeScreenshot('${device}_04_pause');
    await tester.tap(find.text('つづける'));
    await tester.pump();
    expect(game.state, app.GameState.playing);

    await tester.tapAt(tester.getRect(find.byType(GameCanvas)).center);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.text('ドカーン！'), findsNothing);
    await binding.takeScreenshot('${device}_05_jump');
  });
}
