import 'dart:async';

import 'package:flutter/material.dart';

import 'main.dart' show AnimalGame;
import 'progress.dart';
import 'scenery.dart';

Future<void> showGameShop(
  BuildContext context,
  AnimalGame game, {
  int initialTab = 0,
}) => showDialog<void>(
  context: context,
  builder: (context) => DefaultTabController(
    length: 3,
    initialIndex: initialTab,
    child: Dialog(
      child: SizedBox(
        width: 740,
        height: 450,
        child: ListenableBuilder(
          listenable: game.progress,
          builder: (context, _) {
            final progress = game.progress;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 8, 0),
                  child: Row(
                    children: [
                      const Text(
                        'Animal Dash',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Text(
                        '🪙 ${progress.wallet}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        tooltip: '閉じる',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const TabBar(
                  tabs: [
                    Tab(text: 'コイン交換'),
                    Tab(text: 'キャラ・服'),
                    Tab(text: 'BGM・背景'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const Text(
                            '集めたコインで交換。所持品は次のプレイにも持ち越せます。\nプレイ中、画面下のボタンをタップして使います。',
                          ),
                          const SizedBox(height: 8),
                          for (final item in Supply.values)
                            Card(
                              child: ListTile(
                                leading: Text(
                                  item.icon,
                                  style: const TextStyle(fontSize: 25),
                                ),
                                title: Text(
                                  '${item.label}　所持 ${progress.count(item)}個',
                                ),
                                subtitle: Text(item.description),
                                trailing: FilledButton(
                                  onPressed: progress.wallet >= item.cost
                                      ? () {
                                          if (progress.exchange(item)) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  '${item.label}を1個交換しました',
                                                ),
                                                duration: const Duration(
                                                  seconds: 1,
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      : null,
                                  child: Text('${item.cost}コイン'),
                                ),
                              ),
                            ),
                          const Text('コインはゲーム内で獲得します。現金での購入はありません。'),
                        ],
                      ),
                      ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const Text('見た目を変えて楽しもう。どのキャラ・服でも走る性能は同じです。'),
                          const SizedBox(height: 10),
                          const Text(
                            'キャラクター',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          for (final runner in RunnerKind.values)
                            ListTile(
                              leading: Text(
                                runner.icon,
                                style: const TextStyle(fontSize: 28),
                              ),
                              title: Text(runner.label),
                              trailing: OutlinedButton(
                                onPressed:
                                    progress.runner == runner ||
                                        (!progress.ownsRunner(runner) &&
                                            progress.wallet < runner.cost)
                                    ? null
                                    : () {
                                        progress.selectRunner(runner);
                                        if (game.isLoaded) {
                                          game.player.applyAppearance();
                                        }
                                      },
                                child: Text(
                                  progress.runner == runner
                                      ? '使用中'
                                      : progress.ownsRunner(runner)
                                      ? '使う'
                                      : '${runner.cost}コインで解放',
                                ),
                              ),
                            ),
                          const Divider(),
                          const Text(
                            '着せ替え',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          for (final outfit in Outfit.values)
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: outfitColor(outfit),
                                radius: 14,
                              ),
                              title: Text(outfit.label),
                              trailing: OutlinedButton(
                                onPressed:
                                    progress.outfit == outfit ||
                                        (!progress.ownsOutfit(outfit) &&
                                            progress.wallet < outfit.cost)
                                    ? null
                                    : () {
                                        progress.selectOutfit(outfit);
                                        if (game.isLoaded) {
                                          game.player.applyAppearance();
                                        }
                                      },
                                child: Text(
                                  progress.outfit == outfit
                                      ? '着用中'
                                      : progress.ownsOutfit(outfit)
                                      ? '着る'
                                      : '${outfit.cost}コインで解放',
                                ),
                              ),
                            ),
                        ],
                      ),
                      ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const Text(
                            'BGMを選ぶ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          for (final track in MusicTrack.values)
                            ListTile(
                              title: Text(track.label),
                              trailing: progress.music == track
                                  ? const Icon(
                                      Icons.check_circle,
                                      color: Colors.teal,
                                    )
                                  : null,
                              onTap: () => unawaited(game.changeMusic(track)),
                            ),
                          Text(
                            'BGM音量 ${(progress.musicVolume * 100).round()}%',
                          ),
                          Slider(
                            value: progress.musicVolume,
                            divisions: 10,
                            label: '${(progress.musicVolume * 100).round()}%',
                            onChanged: (v) =>
                                unawaited(game.changeMusicVolume(v)),
                          ),
                          const Text(
                            'iPhoneのマナーモード中は無音です。マナーモードを解除すると、本体の音量ボタンでも調整できます。',
                          ),
                          const Divider(),
                          const Text(
                            '背景はプレイごとに抽選',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final weather in Weather.values)
                                Chip(
                                  label: Text(
                                    '${weather.label} ${weather.weight}%${weather.rare ? " ・レア" : ""}',
                                  ),
                                ),
                            ],
                          ),
                          const Text(
                            '雷は短い稲妻のみで、画面全体の点滅はありません。背景による当たり判定の変化はありません。',
                          ),
                          if (game.audioError != null)
                            Text(
                              game.audioError!,
                              style: const TextStyle(color: Colors.deepOrange),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (progress.saveError != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      progress.saveError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  ),
);

Color outfitColor(Outfit outfit) => switch (outfit) {
  Outfit.red => Colors.red,
  Outfit.blue => Colors.indigo,
  Outfit.green => Colors.teal,
  Outfit.gold => const Color(0xffc98a14),
};
