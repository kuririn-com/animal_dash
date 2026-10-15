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
    await game.progress.collect(180);
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
        final directory = Directory('../../outputs/update-preview')
          ..createSync(recursive: true);
        await File(
          '${directory.path}/$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('title');
    game.startGame();
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
    game.useSupply(Supply.shield);
    game.useSupply(Supply.shield);
    expect(game.shieldCharges, 2);
    expect(game.progress.count(Supply.shield), 0);
    game.prepareRun(scene: Weather.night);
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await capture('night');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await game.progress.flush();
  });
}
