// Local, browser-only playground. Never used by the iOS release entry point.
import 'package:animal_dash/game_canvas.dart';
import 'package:animal_dash/main.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PreviewApp());
}

class PreviewApp extends StatefulWidget {
  const PreviewApp({super.key});
  @override
  State<PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<PreviewApp> {
  final game = AnimalGame();
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    home: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ColoredBox(
              color: const Color(0xffe5f3ee),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  children: [
                    const Text(
                      '動作確認用｜公開アプリは変更されません',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Text('初回は0コイン・アイテムなしから'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: GameCanvas(
                child: GameWidget<AnimalGame>(
                  game: game,
                  overlayBuilderMap: {
                    'PauseControl': (context, game) => PauseControl(game: game),
                    'PauseMenu': (context, game) => PauseMenu(game: game),
                    'TitleMenu': (context, game) => TitleOverlay(game: game),
                    'GameOverMenu': (context, game) =>
                        GameOverOverlay(game: game),
                    'Inventory': (context, game) =>
                        InventoryOverlay(game: game),
                  },
                  initialActiveOverlays: const ['TitleMenu'],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
