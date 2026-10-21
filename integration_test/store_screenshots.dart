import 'package:animal_dash/main.dart' as app;
import 'package:animal_dash/purchases.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const device = String.fromEnvironment('SCREENSHOT_DEVICE', defaultValue: 'device');
  testWidgets('capture original release ad-removal review screen', (tester) async {
    await app.main();
    await Future<void>.delayed(const Duration(seconds: 4));
    await tester.pump();
    expect(AdFreePurchase.instance.ready, isTrue);
    await binding.takeScreenshot('${device}_01_title');
    await tester.tap(find.text('広告を削除・購入を復元'));
    await Future<void>.delayed(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('広告を削除'), findsWidgets);
    expect(find.text('購入を復元'), findsOneWidget);
    await binding.takeScreenshot('${device}_04_iap');
  });
}
