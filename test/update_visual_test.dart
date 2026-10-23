import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:animal_dash/game_canvas.dart';
import 'package:animal_dash/main.dart';
import 'package:animal_dash/progress.dart';
import 'package:animal_dash/scenery.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('capture and verify the update menu and themed game', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1100, 550);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previewFont = File('C:/Windows/Fonts/meiryo.ttc');
    if (previewFont.existsSync()) {
      await tester.runAsync(() async {
        final data = ByteData.sublistView(await previewFont.readAsBytes());
        await (FontLoader(
          'PreviewJapanese',
        )..addFont(Future.value(data))).load();
        await (FontLoader('sans-serif')..addFont(Future.value(data))).load();
      });
    }
    final game = AnimalGame(audioEnabled: false, random: Random(45));
    const boundaryKey = ValueKey('capture-update');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'PreviewJapanese'),
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: GameCanvas(
              child: GameWidget<AnimalGame>(
                game: game,
                overlayBuilderMap: {
                  'TitleMenu': (context, game) => TitleOverlay(game: game),
                  'Inventory': (context, game) => InventoryOverlay(game: game),
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
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(game.isLoaded, isTrue);
    expect(game.progress.ready, isTrue);
    expect(find.text('コイン交換・もちもの'), findsOneWidget);
    await game.progress.collect(3000);
    game.progress.exchange(Supply.shield);
    game.progress.exchange(Supply.shield);
    game.progress.selectRunner(RunnerKind.rabbit);
    game.progress.selectOutfit(Outfit.blue);
    await tester.pump();

    Future<void> capture(String name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('build/update-preview')
          ..createSync(recursive: true);
        await File(
          '${directory.path}/$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('title');
    game.startGame();
    final musicChoices = <MusicTrack>{};
    final sceneryChoices = <Weather>{};
    for (var run = 0; run < 40; run++) {
      game.prepareRun();
      musicChoices.add(game.currentMusic);
      sceneryChoices.add(game.weather);
    }
    expect(musicChoices, containsAll(MusicTrack.values));
    expect(sceneryChoices.length, greaterThan(1));
    game.prepareRun(scene: Weather.blossom);
    game.player.applyAppearance();
    for (var frame = 0; frame < 25; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('🛡 バリア ×2'), findsOneWidget);
    final obstacle = Obstacle();
    game.add(obstacle);
    await tester.pump(const Duration(milliseconds: 16));
    obstacle.position.x = 650;
    await tester.pump(const Duration(milliseconds: 16));
    await capture('sakura');
    game.activateMagnet();
    await tester.tap(find.byTooltip('一時停止'));
    await tester.pump();
    expect(game.state, GameState.paused);
    expect(find.text('つづける'), findsOneWidget);
    expect(find.text('🛡 バリア ×2'), findsNothing);
    final stoppedDistance = game.distance;
    final stoppedMagnet = game.magnetTimer;
    final stoppedObstacle = obstacle.position.x;
    game.useSupply(Supply.shield);
    await tester.pump(const Duration(seconds: 1));
    game.update(1);
    expect(game.distance, stoppedDistance);
    expect(game.magnetTimer, stoppedMagnet);
    expect(obstacle.position.x, stoppedObstacle);
    expect(game.progress.count(Supply.shield), 2);
    await capture('pause');
    await tester.tap(find.text('つづける'));
    await tester.pump(const Duration(milliseconds: 32));
    // The first resumed tick establishes a new clock origin.
    await tester.pump(const Duration(milliseconds: 32));
    expect(game.state, GameState.playing);
    expect(game.distance, greaterThan(stoppedDistance));
    expect(game.magnetTimer, lessThan(stoppedMagnet));
    expect(find.text('🛡 バリア ×2'), findsOneWidget);
    game.lifecycleStateChange(AppLifecycleState.inactive);
    game.lifecycleStateChange(AppLifecycleState.resumed);
    expect(game.state, GameState.paused);
    game.continueGame();
    await tester.pump(const Duration(milliseconds: 16));
    game.useSupply(Supply.shield);
    game.useSupply(Supply.shield);
    expect(game.shieldCharges, 2);
    expect(game.progress.count(Supply.shield), 0);
    game.prepareRun(scene: Weather.night);
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await capture('night');
    game.progress.selectRunner(RunnerKind.cat);
    game.player.applyAppearance();
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await capture('cat');
    game.progress.selectRunner(RunnerKind.lion);
    game.player.applyAppearance();
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await capture('lion');
    game.progress.selectRunner(RunnerKind.human);
    for (final entry in {
      Outfit.blue: 'ninja',
      Outfit.green: 'ranger',
      Outfit.gold: 'hero',
    }.entries) {
      expect(game.progress.selectOutfit(entry.key), isTrue);
      game.player.applyAppearance();
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await capture(entry.value);
    }
    // A blast clears both obstacle types once; future obstacles still collide.
    for (final obstacle in game.children.whereType<Obstacle>().toList()) {
      obstacle.removeFromParent();
    }
    final beforeBlast = Obstacle();
    final moleBeforeBlast = MoleObstacle();
    game.addAll([beforeBlast, moleBeforeBlast]);
    await tester.pump(const Duration(milliseconds: 16));
    beforeBlast.position.x = 700;
    moleBeforeBlast.position.x = 800;
    game.activateBreaker();
    await tester.pump(const Duration(milliseconds: 16));
    expect(beforeBlast.isMounted, isFalse);
    expect(moleBeforeBlast.isMounted, isFalse);
    expect(game.itemText.text, isNot(contains('破壊')));
    final afterBlast = Obstacle();
    game.add(afterBlast);
    await tester.pump(const Duration(milliseconds: 16));
    afterBlast.position.x = 700;
    expect(afterBlast.isMounted, isTrue);
    game.player.shieldGrace = 0;
    final shieldBeforeCollision = game.shieldCharges;
    afterBlast.onCollisionStart({}, game.player);
    expect(game.shieldCharges, shieldBeforeCollision - 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await game.progress.flush();
  });
}
