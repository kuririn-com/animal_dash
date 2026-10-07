import 'package:animal_dash/main.dart' as app;
import 'package:animal_dash/game_canvas.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const device = String.fromEnvironment('SCREENSHOT_DEVICE', defaultValue: 'device');

  testWidgets('capture real title, running and jump screens', (tester) async {
    await app.main();
    await Future<void>.delayed(const Duration(seconds: 4));
    await tester.pump();
    expect(find.text('スタート'), findsOneWidget);
    await binding.takeScreenshot('${device}_01_title');

    await tester.tap(find.text('スタート'));
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    await tester.pump();
    expect(find.text('ドカーン！'), findsNothing);
    await binding.takeScreenshot('${device}_02_run');

    await tester.tapAt(tester.getRect(find.byType(GameCanvas)).center);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.text('ドカーン！'), findsNothing);
    await binding.takeScreenshot('${device}_03_jump');
  });
}
