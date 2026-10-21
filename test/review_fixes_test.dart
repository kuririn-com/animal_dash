import 'dart:io';
import 'dart:ui' as ui;
import 'package:animal_dash/main.dart';
import 'package:animal_dash/game_canvas.dart';
import 'package:animal_dash/purchases.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('ground covers each resized logical canvas right edge', (
    tester,
  ) async {
    final ground = ResponsiveGround();
    await tester.runAsync(() async {
      for (final width in [900.0, 1400.0, 950.0]) {
        ground.onGameResize(Vector2(width, 500));
        expect(ground.position.y, 400);
        final recorder = ui.PictureRecorder();
        ground.render(Canvas(recorder));
        final picture = recorder.endRecording();
        final image = await picture.toImage(width.toInt(), 100);
        final data = (await image.toByteData())!;
        final edge = (50 * width.toInt() + width.toInt() - 1) * 4;
        expect(data.getUint8(edge + 3), 255);
        expect(data.getUint8(edge + 1), greaterThan(data.getUint8(edge)));
        image.dispose();
        picture.dispose();
      }
    });
  });

  testWidgets('pause freezes world and timers, resume and background work', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1100, 550);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = File('C:/Windows/Fonts/meiryo.ttc');
    if (font.existsSync()) {
      await tester.runAsync(() async {
        final data = ByteData.sublistView(await font.readAsBytes());
        await (FontLoader(
          'PreviewJapanese',
        )..addFont(Future.value(data))).load();
        await (FontLoader('sans-serif')..addFont(Future.value(data))).load();
      });
    }
    final game = AnimalGame(audioEnabled: false);
    const captureKey = ValueKey('review-capture');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'PreviewJapanese'),
        home: Scaffold(
          body: RepaintBoundary(
            key: captureKey,
            child: GameCanvas(
              child: GameWidget<AnimalGame>(
                game: game,
                overlayBuilderMap: {
                  'TitleMenu': (context, game) => TitleOverlay(game: game),
                  'GameOverMenu': (context, game) =>
                      GameOverOverlay(game: game),
                  'PauseControl': (context, game) => PauseControl(game: game),
                  'PauseMenu': (context, game) => PauseMenu(game: game),
                },
                initialActiveOverlays: const ['TitleMenu'],
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(game.isLoaded, isTrue);
    await tester.tap(find.text('スタート'));
    await tester.pump(const Duration(milliseconds: 16));
    game.activateMagnet();
    final obstacle = Obstacle();
    game.add(obstacle);
    await tester.pump(const Duration(milliseconds: 16));
    obstacle.position.x = 700;
    await tester.tap(find.byTooltip('一時停止'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.state, GameState.paused);
    final distance = game.distance,
        timer = game.magnetTimer,
        x = obstacle.position.x;
    await tester.pump(const Duration(seconds: 2));
    expect(game.distance, distance);
    expect(game.magnetTimer, timer);
    expect(obstacle.position.x, x);
    expect(find.text('つづける'), findsOneWidget);
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(captureKey),
      );
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/review-preview')
        ..createSync(recursive: true);
      await File(
        '${dir.path}/pause.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(find.text('つづける'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 100));
    expect(game.state, GameState.playing);
    expect(game.distance, greaterThan(distance));
    game.lifecycleStateChange(AppLifecycleState.inactive);
    expect(game.state, GameState.paused);
    game.lifecycleStateChange(AppLifecycleState.resumed);
    expect(game.state, GameState.paused);
    await tester.pump();
    await tester.tap(find.text('タイトルへ戻る'));
    await tester.pump();
    expect(game.state, GameState.title);
    expect(find.text('スタート'), findsOneWidget);
    expect(find.byTooltip('一時停止'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'sandbox Japan reference never grants ownership or hides native purchase',
    () async {
      const channel = MethodChannel('animal_dash/review_price_test');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Object? product = {
        'available': true,
        'price': '100円',
        'referencePrice': true,
      };
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'product') return product;
        if (call.method == 'entitlement') return false;
        if (call.method == 'purchase') return {'status': 'cancelled'};
        return null;
      });
      final store = AdFreePurchase(channel: channel);
      await store.initialize();
      await store.loadProduct();
      expect(store.price, '100円');
      expect(store.referencePrice, isTrue);
      await store.purchase();
      expect(store.owned, isFalse);
      product = {'available': false, 'message': '日本向けの商品です。'};
      await store.loadProduct();
      expect(store.available, isFalse);
      expect(store.price, isNull);
      expect(store.referencePrice, isFalse);
      expect(store.message, '日本向けの商品です。');
      store.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
}
