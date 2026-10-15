import 'dart:math';
import 'dart:ui' as ui;

import 'package:animal_dash/main.dart';
import 'package:animal_dash/progress.dart';
import 'package:animal_dash/scenery.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TicketRandom implements Random {
  TicketRandom(this.ticket);
  final int ticket;
  @override
  int nextInt(int max) => ticket % max;
  @override
  double nextDouble() => ticket / 100;
  @override
  bool nextBool() => ticket.isEven;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'earned wallet, two barriers, use and reload preserve a single balance',
    () async {
      final progress = GameProgress();
      await progress.load();
      await progress.collect(40);
      expect(progress.exchange(Supply.shield), isTrue);
      expect(progress.exchange(Supply.shield), isTrue);
      expect(progress.count(Supply.shield), 2);
      expect(progress.wallet, 10);
      expect(progress.exchange(Supply.shield), isFalse);
      expect(progress.use(Supply.shield), isTrue);
      await progress.flush();
      final reloaded = GameProgress();
      await reloaded.load();
      expect(reloaded.wallet, 10);
      expect(reloaded.count(Supply.shield), 1);
      expect(reloaded.use(Supply.shield), isTrue);
      expect(reloaded.use(Supply.shield), isFalse);
    },
  );

  test(
    'old record is preserved without being duplicated as spendable currency',
    () async {
      SharedPreferences.setMockInitialValues({'highCoins': 500});
      final progress = GameProgress();
      await progress.load();
      expect(progress.wallet, 0);
      expect((await SharedPreferences.getInstance()).getInt('highCoins'), 500);
    },
  );

  test(
    'unlocks charge once; selected appearance and audio survive restart',
    () async {
      final progress = GameProgress();
      await progress.load();
      await progress.collect(200);
      expect(progress.selectRunner(RunnerKind.rabbit), isTrue);
      expect(progress.selectOutfit(Outfit.blue), isTrue);
      progress.selectRunner(RunnerKind.human);
      progress.selectRunner(RunnerKind.rabbit);
      progress.setMusic(MusicTrack.blossom);
      progress.setVolume(.3);
      await progress.flush();
      final reloaded = GameProgress();
      await reloaded.load();
      expect(reloaded.wallet, 115);
      expect(reloaded.runner, RunnerKind.rabbit);
      expect(reloaded.outfit, Outfit.blue);
      expect(reloaded.music, MusicTrack.blossom);
      expect(reloaded.musicVolume, .3);
    },
  );

  test(
    'corrupt save cannot be overwritten by an exchange or a pickup',
    () async {
      SharedPreferences.setMockInitialValues({
        GameProgress.storageKey: 'invalid',
      });
      final progress = GameProgress();
      await progress.load();
      expect(progress.ready, isFalse);
      expect(progress.exchange(Supply.shield), isFalse);
      await progress.collect(20);
      expect(
        (await SharedPreferences.getInstance()).getString(
          GameProgress.storageKey,
        ),
        'invalid',
      );
    },
  );

  test('barriers stack and shield grace protects against two colliders', () {
    final game = AnimalGame()..player = Player();
    game.activateShield();
    game.activateShield();
    expect(game.shieldCharges, 2);
    expect(game.consumeShield(), isTrue);
    expect(game.shieldCharges, 1);
    expect(game.player.shieldGrace, greaterThan(0));
    game.activateMagnet();
    game.activateMagnet();
    expect(game.magnetTimer, 14);
  });

  test(
    'all eight backgrounds have exact declared weights including rare ones',
    () {
      final counts = <Weather, int>{};
      for (var ticket = 0; ticket < 100; ticket++) {
        final weather = randomWeather(TicketRandom(ticket));
        counts[weather] = (counts[weather] ?? 0) + 1;
      }
      expect(counts.length, 8);
      for (final weather in Weather.values) {
        expect(counts[weather], weather.weight);
      }
      expect(counts[Weather.thunder], 3);
      expect(counts[Weather.blossom], 5);
    },
  );

  testWidgets(
    'ground paints to the new right edge after growing the viewport',
    (tester) async {
      final size = Vector2(900, 500);
      final landscape = Landscape(
        canvasSize: () => size,
        weather: () => Weather.sunny,
      );
      await tester.runAsync(() async {
        for (final width in [900.0, 1400.0, 950.0]) {
          size.x = width;
          final recorder = ui.PictureRecorder();
          landscape.render(Canvas(recorder));
          final picture = recorder.endRecording();
          final image = await picture.toImage(width.toInt(), 500);
          final data = (await image.toByteData())!;
          final edge = (450 * width.toInt() + width.toInt() - 1) * 4;
          expect(
            data.getUint8(edge + 3),
            255,
            reason: 'right edge must be opaque',
          );
          expect(
            data.getUint8(edge + 1),
            greaterThan(data.getUint8(edge)),
            reason: 'right edge must be green',
          );
          image.dispose();
          picture.dispose();
        }
      });
    },
  );

  for (final screen in [const Size(568, 320), const Size(844, 390)]) {
    testWidgets('shop and title fit the small landscape viewport $screen', (
      tester,
    ) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final game = AnimalGame()..bootReady = true;
      await game.progress.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TitleOverlay(game: game)),
        ),
      );
      await tester.tap(find.text('コイン交換・もちもの'));
      await tester.pumpAndSettle();
      expect(find.text('バリア　所持 0個'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('キャラ・服'));
      await tester.pumpAndSettle();
      expect(find.text('うさぎ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
