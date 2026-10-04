import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:flame/game.dart';

import 'package:flame/components.dart';

import 'package:flame/events.dart';

import 'package:flame/collisions.dart';

import 'package:flame/text.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flame_audio/flame_audio.dart';



enum GameState { title, playing, gameOver }



Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 今回は iPhone のみリリース。
  // Chrome(Web)では広告SDKを初期化しないため、ゲーム本体の確認は可能です。
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    await MobileAds.instance.initialize();
  }

  runApp(const GameApp());
}



class GameApp extends StatelessWidget {

  const GameApp({super.key});



  @override

  Widget build(BuildContext context) {

    return MaterialApp(

      debugShowCheckedModeBanner: false,

      home: Scaffold(

        body: SafeArea(

          child: GameWidget<AnimalGame>.controlled(

            gameFactory: AnimalGame.new,

            overlayBuilderMap: {

              'TitleMenu': (context, game) => TitleOverlay(game: game),

              'GameOverMenu': (context, game) => GameOverOverlay(game: game),

            },

            initialActiveOverlays: const ['TitleMenu'],

          ),

        ),

      ),

    );

  }

}



/// iOS用インタースティシャル広告管理。
/// iOS本番用インタースティシャル広告管理。
class InterstitialAdManager {
  InterstitialAd? _interstitialAd;
  bool _isLoading = false;

  static const String _iosAdUnitId =
      'ca-app-pub-9003840415284448/7344704711';

  bool get isReady => _interstitialAd != null;

  bool get _canUseAds =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  void loadAd() {
    if (!_canUseAds || _isLoading || _interstitialAd != null) return;

    _isLoading = true;

    InterstitialAd.load(
      adUnitId: _iosAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _isLoading = false;
          _interstitialAd = ad;
          debugPrint('Interstitial ad loaded.');
        },
        onAdFailedToLoad: (LoadAdError error) {
          _isLoading = false;
          _interstitialAd = null;
          debugPrint('Interstitial ad failed to load: $error');
        },
      ),
    );
  }

  void showAd({required VoidCallback onFinished}) {
    final ad = _interstitialAd;

    // 広告が未準備ならゲームを止めず、そのまま次へ進む。
    if (ad == null) {
      loadAd();
      onFinished();
      return;
    }

    _interstitialAd = null;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        ad.dispose();
        onFinished();
        loadAd(); // 次の3回目用を先読み
      },
      onAdFailedToShowFullScreenContent:
          (InterstitialAd ad, AdError error) {
        ad.dispose();
        debugPrint('Interstitial ad failed to show: $error');
        onFinished();
        loadAd();
      },
    );

    ad.show();
  }

  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }
}


class AnimalGame extends FlameGame with TapCallbacks, HasCollisionDetection {

  late Player player;

  late TextComponent distanceText, coinText, itemText;



  GameState state = GameState.title;

  double distance = 0;

  int coins = 0; 

  double highDistance = 0;

  int highCoins = 0; 



  bool bgmStarted = false; 



  double obstacleTimer = 0;

  double decorationTimer = 0;

  double coinTimer = 0; 

  double cloudTimer = 0;

  double itemTimer = 0;
  double nextItemSpawnTime = 10.0;

  // アイテム効果
  double speedBaseDistance = 0;
  double destroyTimer = 0;
  double magnetTimer = 0;
  double highJumpTimer = 0;
  double doubleCoinTimer = 0;
  bool shieldReady = false;

  double nextSpawnTime = 2.0;

  double gameSpeed = 1.0;

  int lastFlagDist = 0; 

  final Random random = Random();

  // 広告管理。100m以上走ったゲームオーバーを3回数えるごとに表示。
  final InterstitialAdManager interstitialAdManager = InterstitialAdManager();
  int countedGameOverCount = 0;



  @override

  Color backgroundColor() => const Color(0xFFE0F7FA);



  @override

  Future<void> onLoad() async {

    await super.onLoad(); 



    final prefs = await SharedPreferences.getInstance();

    highDistance = prefs.getDouble('highDistance') ?? 0.0;

    highCoins = prefs.getInt('highCoins') ?? 0;



    await FlameAudio.audioCache.load('bgm.mp3');



    add(CircleComponent(

      radius: 40,

      position: Vector2(size.x - 80, 50),

      paint: Paint()..color = Colors.yellow.withOpacity(0.9),

    )..priority = 0);



    for (int i = 0; i < 3; i++) {

      add(CloudDecoration(startX: random.nextDouble() * size.x)..priority = 1);

    }



    player = Player()..priority = 10;

    add(player);



    final textStyle = const TextStyle(

      fontSize: 20, 

      color: Colors.black87, 

      fontWeight: FontWeight.bold,

      fontFamily: 'sans-serif', 

    );



    distanceText = TextComponent(text: 'きょり: 0m', position: Vector2(20, 20), textRenderer: TextPaint(style: textStyle))..priority = 20;

    coinText = TextComponent(text: 'コイン: 0', position: Vector2(20, 50), textRenderer: TextPaint(style: textStyle.copyWith(color: Colors.blueAccent)))..priority = 20;

    itemText = TextComponent(
      text: '',
      position: Vector2(20, 80),
      textRenderer: TextPaint(style: textStyle.copyWith(fontSize: 16, color: Colors.deepPurple)),
    )..priority = 20;

    addAll([distanceText, coinText, itemText]);



    add(RectangleComponent(

      position: Vector2(0, 400),

      size: Vector2(size.x, max(0.0, size.y - 400)),

      paint: Paint()..color = Colors.lightGreen,

    )..priority = 0);

    // 起動時に全画面広告を1本だけ先読みしておく。
    interstitialAdManager.loadAd();

  }



  void startGame() {

    state = GameState.playing;

    overlays.remove('TitleMenu');



    FlameAudio.bgm.stop();

    FlameAudio.bgm.play('bgm.mp3', volume: 0.5);

    bgmStarted = true;

  }



  @override

  void update(double dt) {

    super.update(dt);

    if (state == GameState.gameOver) return; 



    if (state == GameState.playing) {

      // 最後にリセットした地点から速度を再加速させる。
      final distanceSinceReset = max(0.0, distance - speedBaseDistance);
      gameSpeed = 1.0 + (distanceSinceReset / 800.0);

      if (destroyTimer > 0) destroyTimer = max(0.0, destroyTimer - dt);
      if (magnetTimer > 0) magnetTimer = max(0.0, magnetTimer - dt);
      if (highJumpTimer > 0) highJumpTimer = max(0.0, highJumpTimer - dt);
      if (doubleCoinTimer > 0) doubleCoinTimer = max(0.0, doubleCoinTimer - dt);

      distance += dt * 10 * gameSpeed; 

      distanceText.text = 'きょり: ${distance.toInt()}m';

      coinText.text = 'コイン: $coins';



      double offsetMeters = (size.x - 100) / 20.0;

      int nextFlagTarget = lastFlagDist + 500;

      if (distance >= nextFlagTarget - offsetMeters) {

        add(FlagComponent(dist: nextFlagTarget)..priority = 2);

        lastFlagDist = nextFlagTarget;

      }



      obstacleTimer += dt * gameSpeed;

      if (obstacleTimer > nextSpawnTime) {

        if (distance > 1000 && random.nextDouble() < 0.25) {

          add(MoleObstacle()..priority = 5);

        } else {

          add(Obstacle()..priority = 5);

        }

        obstacleTimer = 0;

        nextSpawnTime = 1.5 + random.nextDouble() * 1.5; 

      }



      coinTimer += dt * gameSpeed;

      if (coinTimer > 1.0) {

        add(Coin()..priority = 5);

        coinTimer = 0;

      }



      // アイテム生成：出現間隔も種類も毎回ランダム。
      // 7種類はすべて同じ確率で抽選される。
      itemTimer += dt;
      if (itemTimer > nextItemSpawnTime) {
        spawnRandomItem();
        itemTimer = 0;
        nextItemSpawnTime = 9.0 + random.nextDouble() * 7.0; // 9〜16秒
      }

      final effects = <String>[];
      if (player.isInvincible) effects.add('⭐ 無敵 ${player.invincibleTimer.ceil()}秒');
      if (destroyTimer > 0) effects.add('💥 破壊 ${destroyTimer.ceil()}秒');
      if (magnetTimer > 0) effects.add('🧲 磁石 ${magnetTimer.ceil()}秒');
      if (highJumpTimer > 0) effects.add('🪽 大ジャンプ ${highJumpTimer.ceil()}秒');
      if (shieldReady) effects.add('🛡️ バリア 1回');
      if (doubleCoinTimer > 0) effects.add('💰 コイン×2 ${doubleCoinTimer.ceil()}秒');
      itemText.text = effects.join('  ');

    }



    decorationTimer += dt * gameSpeed;

    if (decorationTimer > 1.5) {

      add(TreeDecoration(startX: size.x)..priority = 1);

      decorationTimer = 0;

    }



    cloudTimer += dt * gameSpeed;

    if (cloudTimer > 3.0) {

      add(CloudDecoration(startX: size.x)..priority = 1);

      cloudTimer = 0;

    }

  }



  @override

  void onTapDown(TapDownEvent event) {

    super.onTapDown(event);

    if (state == GameState.playing) {

      player.jump();

    }

  }



  Future<void> gameOver() async {

    // 衝突判定が同じフレームで複数回来ても二重処理しない。
    if (state == GameState.gameOver) return;

    state = GameState.gameOver;

    final prefs = await SharedPreferences.getInstance();

    if (distance > highDistance) {
      highDistance = distance;
      await prefs.setDouble('highDistance', highDistance);
    }

    if (coins > highCoins) {
      highCoins = coins;
      await prefs.setInt('highCoins', highCoins);
    }

    // 短すぎるプレイで広告カウントが進むのを防ぐ。
    // 100m以上走ったゲームオーバーだけを1回として数える。
    if (distance >= 100) {
      countedGameOverCount++;
    }

    final shouldShowInterstitial =
        distance >= 100 && countedGameOverCount % 3 == 0;

    // ゲームオーバーになった時点でFlame側は停止。
    pauseEngine();

    if (shouldShowInterstitial && interstitialAdManager.isReady) {
      interstitialAdManager.showAd(
        onFinished: () {
          // 広告を閉じてからゲームオーバー画面を表示。
          if (!overlays.isActive('GameOverMenu')) {
            overlays.add('GameOverMenu');
          }
        },
      );
    } else {
      // 広告が未ロードの場合は待たせずゲームオーバー画面へ。
      if (!overlays.isActive('GameOverMenu')) {
        overlays.add('GameOverMenu');
      }

      // 3回目なのに広告がまだ無かった場合も次回用に再ロード。
      if (shouldShowInterstitial) {
        interstitialAdManager.loadAd();
      }
    }
  }

  void spawnRandomItem() {
    final itemFactories = <PositionComponent Function()>[
      () => StarItem(),
      () => SpeedResetItem(),
      () => BreakerItem(),
      () => MagnetItem(),
      () => HighJumpItem(),
      () => ShieldItem(),
      () => DoubleCoinItem(),
    ];

    final selected = itemFactories[random.nextInt(itemFactories.length)]();
    add(selected..priority = 5);
  }

  void activateSpeedReset() {
    // 距離は維持したまま、現在地点を新しい加速のスタート地点にする。
    speedBaseDistance = distance;
    gameSpeed = 1.0;
  }

  void activateMagnet() {
    magnetTimer = 7.0;
  }

  void activateHighJump() {
    highJumpTimer = 7.0;
  }

  void activateShield() {
    shieldReady = true;
  }

  bool consumeShield() {
    if (!shieldReady) return false;
    shieldReady = false;
    return true;
  }

  void activateDoubleCoin() {
    doubleCoinTimer = 8.0;
  }

  bool get isMagnetActive => magnetTimer > 0;
  bool get isHighJumpActive => highJumpTimer > 0;
  bool get isDoubleCoinActive => doubleCoinTimer > 0;

  void activateBreaker() {
    destroyTimer = 5.0;
    children.whereType<Obstacle>().toList().forEach((o) => o.removeFromParent());
    children.whereType<MoleObstacle>().toList().forEach((m) => m.removeFromParent());
  }

  bool get isBreakerActive => destroyTimer > 0;

  void resetGame() {

    state = GameState.playing;

    distance = 0; coins = 0; gameSpeed = 1.0; lastFlagDist = 0;

    obstacleTimer = 0; coinTimer = 0; cloudTimer = 0; itemTimer = 0; nextItemSpawnTime = 10.0;
    speedBaseDistance = 0; destroyTimer = 0; magnetTimer = 0; highJumpTimer = 0; doubleCoinTimer = 0; shieldReady = false; nextSpawnTime = 2.0;



    children.whereType<Obstacle>().forEach((o) => o.removeFromParent());

    children.whereType<MoleObstacle>().forEach((m) => m.removeFromParent());

    children.whereType<FlagComponent>().forEach((f) => f.removeFromParent());

    children.whereType<Coin>().forEach((c) => c.removeFromParent());

    children.whereType<StarItem>().forEach((s) => s.removeFromParent());

    children.whereType<SpeedResetItem>().forEach((s) => s.removeFromParent());

    children.whereType<BreakerItem>().forEach((s) => s.removeFromParent());
    children.whereType<MagnetItem>().forEach((s) => s.removeFromParent());
    children.whereType<HighJumpItem>().forEach((s) => s.removeFromParent());
    children.whereType<ShieldItem>().forEach((s) => s.removeFromParent());
    children.whereType<DoubleCoinItem>().forEach((s) => s.removeFromParent());



    player.reset();

    distanceText.text = 'きょり: 0m';

    coinText.text = 'コイン: 0';

    itemText.text = '';

    overlays.remove('GameOverMenu');



    FlameAudio.bgm.stop();

    FlameAudio.bgm.play('bgm.mp3', volume: 0.5);

    resumeEngine(); 

  }



  void backToTitle() {

    state = GameState.title;

    distance = 0; coins = 0; gameSpeed = 1.0; lastFlagDist = 0;

    obstacleTimer = 0; coinTimer = 0; cloudTimer = 0; itemTimer = 0; nextItemSpawnTime = 10.0;
    speedBaseDistance = 0; destroyTimer = 0; magnetTimer = 0; highJumpTimer = 0; doubleCoinTimer = 0; shieldReady = false; nextSpawnTime = 2.0;



    children.whereType<Obstacle>().forEach((o) => o.removeFromParent());

    children.whereType<MoleObstacle>().forEach((m) => m.removeFromParent());

    children.whereType<FlagComponent>().forEach((f) => f.removeFromParent());

    children.whereType<Coin>().forEach((c) => c.removeFromParent());

    children.whereType<StarItem>().forEach((s) => s.removeFromParent());

    children.whereType<SpeedResetItem>().forEach((s) => s.removeFromParent());

    children.whereType<BreakerItem>().forEach((s) => s.removeFromParent());
    children.whereType<MagnetItem>().forEach((s) => s.removeFromParent());
    children.whereType<HighJumpItem>().forEach((s) => s.removeFromParent());
    children.whereType<ShieldItem>().forEach((s) => s.removeFromParent());
    children.whereType<DoubleCoinItem>().forEach((s) => s.removeFromParent());



    player.reset();

    distanceText.text = 'きょり: 0m';

    coinText.text = 'コイン: 0';

    itemText.text = '';

    overlays.remove('GameOverMenu');

    overlays.add('TitleMenu');



    FlameAudio.bgm.stop();

    FlameAudio.bgm.play('bgm.mp3', volume: 0.5);

    resumeEngine(); 

  }

  @override
  void onRemove() {
    interstitialAdManager.dispose();
    super.onRemove();
  }

}



// --- UI ---



class TitleOverlay extends StatefulWidget {
  final AnimalGame game;

  const TitleOverlay({super.key, required this.game});

  @override
  State<TitleOverlay> createState() => _TitleOverlayState();
}

class _TitleOverlayState extends State<TitleOverlay> {
  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  String? get _bannerAdUnitId {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return null;
    }
    return 'ca-app-pub-9003840415284448/8849358073';
  }

  @override
  void initState() {
    super.initState();
    _loadBanner();
  }

  void _loadBanner() {
    final adUnitId = _bannerAdUnitId;
    if (adUnitId == null) return;

    final banner = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _isBannerLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('Banner failed to load: $error');
        },
      ),
    );

    banner.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 50),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'アニマル・ラン',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '🏆 最高きょり: ${widget.game.highDistance.toInt()}m',
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '🟡 最高コイン: ${widget.game.highCoins}',
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 15,
                    ),
                  ),
                  onPressed: widget.game.startGame,
                  child: const Text('スタート', style: TextStyle(fontSize: 24)),
                ),
              ],
            ),
          ),
        ),

        // タイトル画面の一番下にだけ表示。
        // startGame() で TitleMenu overlay が消えると、この広告も dispose されます。
        if (_isBannerLoaded && _bannerAd != null)
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            ),
          ),
      ],
    );
  }
}

class GameOverOverlay extends StatelessWidget {

  final AnimalGame game;

  const GameOverOverlay({super.key, required this.game});



  @override

  Widget build(BuildContext context) {

    return Center(

      child: Container(

        padding: const EdgeInsets.all(30),

        decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(20)),

        child: Column(

          mainAxisSize: MainAxisSize.min,

          children: [

            const Text('ドカーン！', style: TextStyle(fontSize: 36, color: Colors.redAccent, fontWeight: FontWeight.bold)),

            const SizedBox(height: 20),

            Text('きょり: ${game.distance.toInt()}m', style: const TextStyle(fontSize: 24, color: Colors.white)),

            Text('コイン: ${game.coins}', style: const TextStyle(fontSize: 24, color: Colors.yellow)),

            const SizedBox(height: 20),

            Container(

              padding: const EdgeInsets.all(10),

              decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),

              child: Column(

                children: [

                  Text('🏆 最高きょり: ${game.highDistance.toInt()}m', style: const TextStyle(fontSize: 18, color: Colors.orange, fontWeight: FontWeight.bold)),

                  Text('🟡 最高コイン: ${game.highCoins}', style: const TextStyle(fontSize: 18, color: Colors.orange, fontWeight: FontWeight.bold)),

                ],

              ),

            ),

            const SizedBox(height: 30),

            Row(

              mainAxisSize: MainAxisSize.min,

              children: [

                ElevatedButton(

                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),

                  onPressed: game.resetGame, 

                  child: const Text('再開', style: TextStyle(color: Colors.white, fontSize: 18))

                ),

                const SizedBox(width: 20),

                ElevatedButton(

                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),

                  onPressed: game.backToTitle, 

                  child: const Text('タイトルへ', style: TextStyle(color: Colors.white, fontSize: 18))

                ),

              ],

            ),

          ],

        ),

      ),

    );

  }

}



// --- アイテム・背景コンポーネント ---



// ★追加：無敵アイテム（星の代わりの二重丸）

class StarItem extends PositionComponent with CollisionCallbacks, HasGameRef<AnimalGame> {
  final Random random = Random();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    size = Vector2(36, 36);
    position = Vector2(gameRef.size.x, 145 + random.nextDouble() * 145);
    add(CircleHitbox());

    add(CircleComponent(
      radius: 18,
      paint: Paint()..color = Colors.orange.withOpacity(0.9),
    ));
    add(PolygonComponent(
      [
        Vector2(0, -12), Vector2(3.5, -4), Vector2(12, -4),
        Vector2(5.5, 2), Vector2(8, 11), Vector2(0, 6),
        Vector2(-8, 11), Vector2(-5.5, 2), Vector2(-12, -4),
        Vector2(-3.5, -4),
      ],
      position: Vector2(18, 18),
      paint: Paint()..color = Colors.yellowAccent,
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    angle += dt * 1.8;
    position.x -= 200 * gameRef.gameSpeed * dt;
    if (position.x < -size.x) removeFromParent();
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Player) {
      gameRef.player.becomeInvincible();
      removeFromParent();
    }
  }
}

class SpeedResetItem extends PositionComponent with CollisionCallbacks, HasGameRef<AnimalGame> {
  final Random random = Random();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    size = Vector2(40, 36);
    position = Vector2(gameRef.size.x, 150 + random.nextDouble() * 140);
    add(RectangleHitbox());

    // 小さなカメ。取ると現在地点を新しい速度1.0の起点にする。
    add(CircleComponent(radius: 14, position: Vector2(7, 5), paint: Paint()..color = Colors.green));
    add(CircleComponent(radius: 6, position: Vector2(29, 10), paint: Paint()..color = Colors.lightGreen));
    add(CircleComponent(radius: 3, position: Vector2(2, 28), paint: Paint()..color = Colors.green[800]!));
    add(CircleComponent(radius: 3, position: Vector2(23, 28), paint: Paint()..color = Colors.green[800]!));
    add(CircleComponent(radius: 1.5, position: Vector2(33, 13), paint: Paint()..color = Colors.black));
    add(RectangleComponent(size: Vector2(20, 3), position: Vector2(4, 18), angle: -0.45, paint: Paint()..color = Colors.lightGreenAccent));
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.x -= 200 * gameRef.gameSpeed * dt;
    if (position.x < -size.x) removeFromParent();
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Player) {
      gameRef.activateSpeedReset();
      removeFromParent();
    }
  }
}

class BreakerItem extends PositionComponent with CollisionCallbacks, HasGameRef<AnimalGame> {
  final Random random = Random();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    size = Vector2(36, 36);
    position = Vector2(gameRef.size.x, 145 + random.nextDouble() * 145);
    add(CircleHitbox());

    add(CircleComponent(radius: 18, paint: Paint()..color = Colors.redAccent));
    final p = Paint()..color = Colors.white;
    add(RectangleComponent(size: Vector2(26, 5), position: Vector2(7, 6), angle: 0.78, paint: p));
    add(RectangleComponent(size: Vector2(26, 5), position: Vector2(29, 7), angle: 2.35, paint: Paint()..color = Colors.white));
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.x -= 200 * gameRef.gameSpeed * dt;
    if (position.x < -size.x) removeFromParent();
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Player) {
      gameRef.activateBreaker();
      removeFromParent();
    }
  }
}

class MagnetItem extends PositionComponent with CollisionCallbacks, HasGameRef<AnimalGame> {
  final Random random = Random();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    size = Vector2(40, 40);
    position = Vector2(gameRef.size.x, 145 + random.nextDouble() * 145);
    add(RectangleHitbox());

    // U字の磁石
    add(RectangleComponent(size: Vector2(8, 25), position: Vector2(5, 6), paint: Paint()..color = Colors.redAccent));
    add(RectangleComponent(size: Vector2(8, 25), position: Vector2(27, 6), paint: Paint()..color = Colors.blueAccent));
    add(RectangleComponent(size: Vector2(22, 8), position: Vector2(9, 27), paint: Paint()..color = Colors.indigo));
    add(RectangleComponent(size: Vector2(8, 7), position: Vector2(5, 4), paint: Paint()..color = Colors.white));
    add(RectangleComponent(size: Vector2(8, 7), position: Vector2(27, 4), paint: Paint()..color = Colors.white));
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.x -= 200 * gameRef.gameSpeed * dt;
    if (position.x < -size.x) removeFromParent();
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Player) {
      gameRef.activateMagnet();
      removeFromParent();
    }
  }
}

class HighJumpItem extends PositionComponent with CollisionCallbacks, HasGameRef<AnimalGame> {
  final Random random = Random();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    size = Vector2(42, 36);
    position = Vector2(gameRef.size.x, 145 + random.nextDouble() * 145);
    add(RectangleHitbox());

    add(CircleComponent(radius: 13, position: Vector2(8, 5), paint: Paint()..color = Colors.cyan));
    // 左右の翼
    for (int i = 0; i < 3; i++) {
      add(RectangleComponent(
        size: Vector2(14 - i * 2.0, 5),
        position: Vector2(2, 7 + i * 7.0),
        angle: -0.25,
        paint: Paint()..color = Colors.white,
      ));
      add(RectangleComponent(
        size: Vector2(14 - i * 2.0, 5),
        position: Vector2(28, 7 + i * 7.0),
        angle: 0.25,
        paint: Paint()..color = Colors.white,
      ));
    }
    add(TextComponent(
      text: '↑',
      position: Vector2(21, 18),
      anchor: Anchor.center,
      textRenderer: TextPaint(style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold)),
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.x -= 200 * gameRef.gameSpeed * dt;
    if (position.x < -size.x) removeFromParent();
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Player) {
      gameRef.activateHighJump();
      removeFromParent();
    }
  }
}

class ShieldItem extends PositionComponent with CollisionCallbacks, HasGameRef<AnimalGame> {
  final Random random = Random();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    size = Vector2(38, 38);
    position = Vector2(gameRef.size.x, 145 + random.nextDouble() * 145);
    add(CircleHitbox());

    add(CircleComponent(radius: 19, paint: Paint()..color = Colors.blue.withOpacity(0.25)));
    add(CircleComponent(
      radius: 16,
      position: Vector2(3, 3),
      paint: Paint()
        ..color = Colors.lightBlueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    ));
    add(TextComponent(
      text: '1',
      position: Vector2(19, 18),
      anchor: Anchor.center,
      textRenderer: TextPaint(style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.x -= 200 * gameRef.gameSpeed * dt;
    if (position.x < -size.x) removeFromParent();
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Player) {
      gameRef.activateShield();
      removeFromParent();
    }
  }
}

class DoubleCoinItem extends PositionComponent with CollisionCallbacks, HasGameRef<AnimalGame> {
  final Random random = Random();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    size = Vector2(42, 38);
    position = Vector2(gameRef.size.x, 145 + random.nextDouble() * 145);
    add(RectangleHitbox());

    add(CircleComponent(radius: 14, position: Vector2(2, 7), paint: Paint()..color = Colors.amber));
    add(CircleComponent(radius: 14, position: Vector2(14, 2), paint: Paint()..color = Colors.yellow));
    add(TextComponent(
      text: '×2',
      position: Vector2(22, 20),
      anchor: Anchor.center,
      textRenderer: TextPaint(style: const TextStyle(fontSize: 15, color: Colors.brown, fontWeight: FontWeight.bold)),
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.x -= 200 * gameRef.gameSpeed * dt;
    if (position.x < -size.x) removeFromParent();
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Player) {
      gameRef.activateDoubleCoin();
      removeFromParent();
    }
  }
}

class FlagComponent extends PositionComponent with HasGameRef<AnimalGame> {

  final int dist;

  FlagComponent({required this.dist});



  @override

  Future<void> onLoad() async {

    size = Vector2(40, 100);

    position = Vector2(gameRef.size.x, 300);

    add(RectangleComponent(size: Vector2(4, 100), position: Vector2(0,0), paint: Paint()..color = Colors.brown));

    add(RectangleComponent(size: Vector2(40, 25), position: Vector2(4,0), paint: Paint()..color = Colors.blueAccent));

    add(TextComponent(

      text: '${dist}m',

      textRenderer: TextPaint(style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'sans-serif')),

      position: Vector2(24, 12),

      anchor: Anchor.center,

    ));

  }



  @override

  void update(double dt) {

    super.update(dt);

    position.x -= 200 * gameRef.gameSpeed * dt;

    if (position.x < -size.x) removeFromParent();

  }

}



class CloudDecoration extends PositionComponent with HasGameRef<AnimalGame> {

  final Random random = Random();

  double speed = 40; 



  CloudDecoration({required double startX}) : super(position: Vector2(startX, 0));



  @override

  Future<void> onLoad() async {

    await super.onLoad();

    double baseSize = 20 + random.nextDouble() * 20;

    position.y = 20 + random.nextDouble() * 100; 



    add(CircleComponent(radius: baseSize, position: Vector2(0, 0), paint: Paint()..color = Colors.white));

    add(CircleComponent(radius: baseSize * 0.8, position: Vector2(baseSize * 0.8, baseSize * 0.3), paint: Paint()..color = Colors.white));

    add(CircleComponent(radius: baseSize * 0.9, position: Vector2(-baseSize * 0.7, baseSize * 0.2), paint: Paint()..color = Colors.white));

  }



  @override

  void update(double dt) {

    super.update(dt);

    position.x -= speed * gameRef.gameSpeed * dt;

    if (position.x < -150) removeFromParent();

  }

}



class Coin extends PositionComponent with CollisionCallbacks, HasGameRef<AnimalGame> {

  final Random random = Random();



  @override

  Future<void> onLoad() async {

    await super.onLoad(); 

    size = Vector2(24, 24);

    position.x = gameRef.size.x;

    position.y = 220 + random.nextDouble() * 100;

    add(CircleHitbox());

    add(CircleComponent(radius: 12, paint: Paint()..color = Colors.yellow));

  }



  @override

  void update(double dt) {

    super.update(dt);

    position.x -= 200 * gameRef.gameSpeed * dt;

    if (gameRef.isMagnetActive) {
      final targetX = gameRef.player.position.x + gameRef.player.size.x / 2;
      final targetY = gameRef.player.position.y + gameRef.player.size.y / 2;
      final follow = min(1.0, dt * 6.0);
      position.x += (targetX - position.x) * follow;
      position.y += (targetY - position.y) * follow;
    }

    if (position.x < -size.x) removeFromParent();

  }



  @override

  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {

    super.onCollisionStart(intersectionPoints, other);

    if (other is Player) {

      gameRef.coins += gameRef.isDoubleCoinActive ? 2 : 1;

      removeFromParent();

    }

  }

}



class TreeDecoration extends PositionComponent with HasGameRef<AnimalGame> {

  final Random random = Random();

  TreeDecoration({required double startX}) : super(position: Vector2(startX, 0));



  @override

  Future<void> onLoad() async {

    await super.onLoad();

    double h = 40 + random.nextDouble() * 40;

    double w = 20 + random.nextDouble() * 20;

    position.y = 400 - h;

    add(RectangleComponent(size: Vector2(w * 0.4, h * 0.5), position: Vector2(w * 0.3, h * 0.5), paint: Paint()..color = Colors.brown[300]!));

    add(CircleComponent(radius: w / 2, paint: Paint()..color = Colors.green[600]!));

  }



  @override

  void update(double dt) {

    super.update(dt);

    position.x -= 80 * gameRef.gameSpeed * dt;

    if (position.x < -100) removeFromParent();

  }

}



// --- プレイヤーと障害物 ---



class Player extends PositionComponent with CollisionCallbacks, HasGameRef<AnimalGame> {

  double velocityY = 0;

  final double gravity = 900; 

  final double jumpForce = -450; 

  bool isGrounded = true;

  int jumpCount = 0; 

  double runningTime = 0;



  // ★追加：無敵管理用の変数

  bool isInvincible = false;

  double invincibleTimer = 0;



  late RectangleComponent head, torso, leftLeg, rightLeg, leftArm, rightArm;
  late RectangleComponent shieldAura;

  late Paint skinPaint, torsoPaint, legPaint, legAccentPaint, armPaint, armAccentPaint;



  Player() : super(position: Vector2(100, 320), size: Vector2(40, 80)) {

    add(RectangleHitbox());

  }



  @override

  Future<void> onLoad() async {

    await super.onLoad();



    // パーツの色を個別に管理できるように分離

    skinPaint = Paint()..color = Colors.orange[200]!;

    torsoPaint = Paint()..color = Colors.red;

    legPaint = Paint()..color = Colors.blue;

    legAccentPaint = Paint()..color = Colors.blueAccent;

    armPaint = Paint()..color = Colors.pink;

    armAccentPaint = Paint()..color = Colors.pinkAccent;



    head = RectangleComponent(size: Vector2(24, 24), position: Vector2(8, 0), paint: skinPaint);

    head.addAll([

      CircleComponent(radius: 2, position: Vector2(14, 8), paint: Paint()..color = Colors.black),

      CircleComponent(radius: 2, position: Vector2(20, 8), paint: Paint()..color = Colors.black),

      CircleComponent(radius: 2, position: Vector2(17, 14), paint: Paint()..color = Colors.black),

    ]);



    torso = RectangleComponent(size: Vector2(30, 36), position: Vector2(5, 24), paint: torsoPaint);

    leftLeg = RectangleComponent(size: Vector2(10, 24), position: Vector2(12, 60), anchor: Anchor.topCenter, paint: legPaint);

    rightLeg = RectangleComponent(size: Vector2(10, 24), position: Vector2(28, 60), anchor: Anchor.topCenter, paint: legAccentPaint);

    leftArm = RectangleComponent(size: Vector2(8, 24), position: Vector2(10, 26), anchor: Anchor.topCenter, paint: armPaint);

    rightArm = RectangleComponent(size: Vector2(8, 24), position: Vector2(22, 26), anchor: Anchor.topCenter, paint: armAccentPaint);



    shieldAura = RectangleComponent(
      size: Vector2(54, 94),
      position: Vector2(-7, -7),
      paint: Paint()
        ..color = Colors.transparent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    )..priority = -1;

    addAll([shieldAura, rightArm, rightLeg, torso, leftLeg, leftArm, head]);

  }



  @override

  void update(double dt) {

    super.update(dt);

    if (!isGrounded) {

      velocityY += gravity * dt;

      position.y += velocityY * dt;

      leftLeg.angle = -0.4; rightLeg.angle = 0.4;

      leftArm.angle = 2.0; rightArm.angle = -2.0;

    } else {

      runningTime += dt * 20 * gameRef.gameSpeed; 

      leftLeg.angle = sin(runningTime) * 0.7; rightLeg.angle = -sin(runningTime) * 0.7;

      leftArm.angle = -sin(runningTime) * 0.8; rightArm.angle = sin(runningTime) * 0.8;

      position.y = 320 + sin(runningTime * 2) * 2; 

    }

    if (position.y >= 320) {

      position.y = 320; velocityY = 0; isGrounded = true; jumpCount = 0; 

    }



    // バリア所持中はプレイヤーの周囲を青く表示。
    shieldAura.paint.color = gameRef.shieldReady
        ? Colors.lightBlueAccent.withOpacity(0.85)
        : Colors.transparent;

    // ★追加：無敵状態のチカチカ点滅アニメーション

    if (isInvincible) {

      invincibleTimer -= dt;

      if (invincibleTimer <= 0) {

        isInvincible = false;

        _setOpacity(1.0); // 元に戻す

      } else {

        // 残り時間を使って0.3と1.0を交互に切り替え

        _setOpacity((invincibleTimer * 10).toInt() % 2 == 0 ? 1.0 : 0.3);

      }

    }

  }



  // 透明度を一括変更する便利メソッド

  void _setOpacity(double opacity) {

    head.paint.color = skinPaint.color.withOpacity(opacity);

    torso.paint.color = torsoPaint.color.withOpacity(opacity);

    leftLeg.paint.color = legPaint.color.withOpacity(opacity);

    rightLeg.paint.color = legAccentPaint.color.withOpacity(opacity);

    leftArm.paint.color = armPaint.color.withOpacity(opacity);

    rightArm.paint.color = armAccentPaint.color.withOpacity(opacity);

  }



  // 無敵発動！

  void becomeInvincible() {

    isInvincible = true;

    invincibleTimer = 5.0; // 5秒間

  }



  void jump() {

    if (jumpCount < 2) {

      velocityY = gameRef.isHighJumpActive ? -620 : jumpForce;
      jumpCount++;
      isGrounded = false;

    }

  }



  void reset() {

    position.y = 320; velocityY = 0; isGrounded = true; jumpCount = 0; runningTime = 0;

    leftLeg.angle = 0; rightLeg.angle = 0; leftArm.angle = 0; rightArm.angle = 0;

    isInvincible = false;

    invincibleTimer = 0;

    _setOpacity(1.0);
    shieldAura.paint.color = Colors.transparent;

  }

}



class MoleObstacle extends PositionComponent with CollisionCallbacks, HasGameRef<AnimalGame> {

  @override

  Future<void> onLoad() async {

    size = Vector2(40, 40);

    position = Vector2(gameRef.size.x, 360); 

    add(RectangleHitbox());

    add(RectangleComponent(size: Vector2(30, 30), position: Vector2(5, 10), paint: Paint()..color = Colors.brown[700]!));

    add(CircleComponent(radius: 3, position: Vector2(20, 15), paint: Paint()..color = Colors.black));

  }



  @override

  void update(double dt) {

    super.update(dt);

    position.x -= 250 * gameRef.gameSpeed * dt;

    if (position.x < -size.x) removeFromParent();

  }



  @override

  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {

    if (other is Player) {
      if (gameRef.isBreakerActive) {
        removeFromParent();
      } else if (gameRef.player.isInvincible) {
        // 無敵中はそのまま通過
      } else if (gameRef.consumeShield()) {
        removeFromParent();
      } else {
        gameRef.gameOver();
      }
    }

    super.onCollisionStart(intersectionPoints, other);

  }

}



enum ObstacleType {
  box,
  clone,
  animalDog,
  animalRabbit,
  animalDachshund,
  animalCat,
  animalFox,
  animalSheep,
  animalBird,
  animalFrog,
  animalBoar,
}



class Obstacle extends PositionComponent with CollisionCallbacks, HasGameRef<AnimalGame> {

  late ObstacleType type;

  double baseSpeed = 250;

  double runTime = 0;

  final Random random = Random();



  RectangleComponent? leg1, leg2, arm1, arm2, head, tail;



  @override

  Future<void> onLoad() async {

    await super.onLoad();

    type = ObstacleType.values[random.nextInt(ObstacleType.values.length)];

    baseSpeed = 220 + random.nextDouble() * 100;

    position.x = gameRef.size.x;



    if (type == ObstacleType.clone) {

      // 人型障害物：進行方向（左）を向いた横顔。
      size = Vector2(42, 70);

      position.y = 400 - 70;

      final skin = Paint()..color = Colors.orange[200]!;

      // 頭は少し左寄り。鼻を左へ飛び出させ、横向きだと分かる形にする。
      head = RectangleComponent(
        size: Vector2(22, 24),
        position: Vector2(7, 0),
        paint: skin,
      );

      head!.addAll([
        // 左向きの鼻
        RectangleComponent(
          size: Vector2(7, 6),
          position: Vector2(-5, 10),
          paint: skin,
        ),
        // 横顔なので目は1つだけ見える
        CircleComponent(
          radius: 2,
          position: Vector2(3, 7),
          paint: Paint()..color = Colors.black,
        ),
        // 口
        RectangleComponent(
          size: Vector2(5, 2),
          position: Vector2(-1, 17),
          paint: Paint()..color = Colors.deepOrange,
        ),
        // 後頭部側の髪
        RectangleComponent(
          size: Vector2(5, 18),
          position: Vector2(18, 1),
          paint: Paint()..color = Colors.brown[800]!,
        ),
      ]);

      final torso = RectangleComponent(
        size: Vector2(30, 30),
        position: Vector2(6, 24),
        paint: Paint()..color = Colors.purple,
      );

      leg1 = RectangleComponent(
        size: Vector2(10, 20),
        position: Vector2(13, 50),
        anchor: Anchor.topCenter,
        paint: Paint()..color = Colors.deepPurple,
      );

      leg2 = RectangleComponent(
        size: Vector2(10, 20),
        position: Vector2(29, 50),
        anchor: Anchor.topCenter,
        paint: Paint()..color = Colors.deepPurpleAccent,
      );

      // 腕も左方向へ振って「こちらへ走る」印象を強める。
      arm1 = RectangleComponent(
        size: Vector2(8, 20),
        position: Vector2(9, 27),
        anchor: Anchor.topCenter,
        paint: Paint()..color = Colors.purple[300]!,
      );

      arm2 = RectangleComponent(
        size: Vector2(8, 20),
        position: Vector2(23, 27),
        anchor: Anchor.topCenter,
        paint: Paint()..color = Colors.purpleAccent,
      );

      addAll([arm2!, leg2!, torso, leg1!, arm1!, head!]);



    } else if (type == ObstacleType.animalDog) {

      size = Vector2(50, 36);
      position.y = 400 - 36;
      final fur = Paint()..color = Colors.brown;
      final body = RectangleComponent(size: Vector2(40, 20), position: Vector2(10, 8), paint: fur);
      head = RectangleComponent(size: Vector2(18, 18), position: Vector2(0, 0), paint: fur);
      head!.add(CircleComponent(radius: 2, position: Vector2(4, 6), paint: Paint()..color = Colors.black));
      leg1 = RectangleComponent(size: Vector2(6, 14), position: Vector2(14, 26), anchor: Anchor.topCenter, paint: fur);
      leg2 = RectangleComponent(size: Vector2(6, 14), position: Vector2(44, 26), anchor: Anchor.topCenter, paint: fur);
      tail = RectangleComponent(size: Vector2(12, 4), position: Vector2(50, 12), anchor: Anchor.centerLeft, paint: fur);
      addAll([body, leg1!, leg2!, head!, tail!]);



    } else if (type == ObstacleType.animalRabbit) {

      size = Vector2(30, 50);
      position.y = 400 - 50;
      final fur = Paint()..color = Colors.white;
      final body = RectangleComponent(size: Vector2(20, 20), position: Vector2(5, 20), paint: fur);
      head = RectangleComponent(size: Vector2(16, 16), position: Vector2(0, 4), paint: fur);
      head!.add(RectangleComponent(size: Vector2(4, 16), position: Vector2(2, -14), paint: fur));
      head!.add(RectangleComponent(size: Vector2(4, 16), position: Vector2(10, -14), paint: fur));
      head!.add(CircleComponent(radius: 2, position: Vector2(4, 6), paint: Paint()..color = Colors.red));
      leg1 = RectangleComponent(size: Vector2(6, 14), position: Vector2(8, 40), anchor: Anchor.topCenter, paint: fur);
      leg2 = RectangleComponent(size: Vector2(6, 14), position: Vector2(16, 40), anchor: Anchor.topCenter, paint: fur);
      tail = RectangleComponent(size: Vector2(6, 6), position: Vector2(22, 30), anchor: Anchor.center, paint: fur);
      addAll([body, leg2!, leg1!, head!, tail!]);



    } else if (type == ObstacleType.animalDachshund) {

      size = Vector2(70, 25);
      position.y = 400 - 25;
      final fur = Paint()..color = Colors.brown[800]!;
      final body = RectangleComponent(size: Vector2(60, 12), position: Vector2(10, 8), paint: fur);
      head = RectangleComponent(size: Vector2(16, 16), position: Vector2(0, 0), paint: fur);
      head!.add(CircleComponent(radius: 2, position: Vector2(4, 6), paint: Paint()..color = Colors.black));
      leg1 = RectangleComponent(size: Vector2(4, 8), position: Vector2(16, 20), anchor: Anchor.topCenter, paint: fur);
      leg2 = RectangleComponent(size: Vector2(4, 8), position: Vector2(64, 20), anchor: Anchor.topCenter, paint: fur);
      tail = RectangleComponent(size: Vector2(12, 4), position: Vector2(70, 10), anchor: Anchor.centerLeft, paint: fur);
      addAll([body, leg1!, leg2!, head!, tail!]);



    } else if (type == ObstacleType.animalCat) {

      // 猫：グレー。左側が顔、右側がしっぽ。
      size = Vector2(52, 34);
      position.y = 400 - 34;
      final fur = Paint()..color = Colors.blueGrey[500]!;
      final body = RectangleComponent(size: Vector2(35, 18), position: Vector2(12, 10), paint: fur);
      head = RectangleComponent(size: Vector2(18, 18), position: Vector2(0, 4), paint: fur);
      head!.addAll([
        // 耳
        RectangleComponent(size: Vector2(6, 7), position: Vector2(1, -5), paint: fur)..angle = -0.35,
        RectangleComponent(size: Vector2(6, 7), position: Vector2(10, -5), paint: fur)..angle = 0.35,
        CircleComponent(radius: 2, position: Vector2(4, 6), paint: Paint()..color = Colors.yellowAccent),
        RectangleComponent(size: Vector2(5, 2), position: Vector2(-3, 11), paint: Paint()..color = Colors.pinkAccent),
      ]);
      leg1 = RectangleComponent(size: Vector2(5, 10), position: Vector2(16, 27), anchor: Anchor.topCenter, paint: fur);
      leg2 = RectangleComponent(size: Vector2(5, 10), position: Vector2(42, 27), anchor: Anchor.topCenter, paint: fur);
      tail = RectangleComponent(size: Vector2(18, 4), position: Vector2(47, 12), anchor: Anchor.centerLeft, paint: fur);
      addAll([body, leg1!, leg2!, head!, tail!]);



    } else if (type == ObstacleType.animalFox) {

      // キツネ：オレンジ。長い鼻と大きなしっぽで判別しやすくする。
      size = Vector2(58, 38);
      position.y = 400 - 38;
      final fur = Paint()..color = Colors.deepOrange[400]!;
      final white = Paint()..color = Colors.white;
      final body = RectangleComponent(size: Vector2(36, 18), position: Vector2(14, 11), paint: fur);
      head = RectangleComponent(size: Vector2(18, 18), position: Vector2(2, 3), paint: fur);
      head!.addAll([
        RectangleComponent(size: Vector2(9, 7), position: Vector2(-7, 9), paint: fur),
        RectangleComponent(size: Vector2(5, 8), position: Vector2(1, -6), paint: fur)..angle = -0.25,
        RectangleComponent(size: Vector2(5, 8), position: Vector2(11, -6), paint: fur)..angle = 0.25,
        CircleComponent(radius: 2, position: Vector2(4, 6), paint: Paint()..color = Colors.black),
        CircleComponent(radius: 2, position: Vector2(-6, 11), paint: Paint()..color = Colors.black),
        RectangleComponent(size: Vector2(8, 4), position: Vector2(2, 14), paint: white),
      ]);
      leg1 = RectangleComponent(size: Vector2(5, 11), position: Vector2(18, 28), anchor: Anchor.topCenter, paint: fur);
      leg2 = RectangleComponent(size: Vector2(5, 11), position: Vector2(45, 28), anchor: Anchor.topCenter, paint: fur);
      tail = RectangleComponent(size: Vector2(24, 8), position: Vector2(49, 12), anchor: Anchor.centerLeft, paint: fur);
      tail!.add(RectangleComponent(size: Vector2(7, 8), position: Vector2(17, 0), paint: white));
      addAll([body, leg1!, leg2!, head!, tail!]);



    } else if (type == ObstacleType.animalSheep) {

      // ひつじ：丸い毛を複数重ねてモコモコ感を出す。
      size = Vector2(56, 40);
      position.y = 400 - 40;
      final wool = Paint()..color = Colors.white;
      final face = Paint()..color = Colors.grey[700]!;
      final body = PositionComponent(position: Vector2(13, 7), size: Vector2(36, 24));
      body.addAll([
        CircleComponent(radius: 10, position: Vector2(0, 4), paint: wool),
        CircleComponent(radius: 11, position: Vector2(9, 0), paint: wool),
        CircleComponent(radius: 11, position: Vector2(20, 1), paint: wool),
        CircleComponent(radius: 10, position: Vector2(28, 5), paint: wool),
        CircleComponent(radius: 10, position: Vector2(10, 10), paint: wool),
        CircleComponent(radius: 10, position: Vector2(22, 10), paint: wool),
      ]);
      head = RectangleComponent(size: Vector2(15, 17), position: Vector2(0, 9), paint: face);
      head!.addAll([
        CircleComponent(radius: 2, position: Vector2(3, 5), paint: Paint()..color = Colors.black),
        RectangleComponent(size: Vector2(5, 3), position: Vector2(-4, 11), paint: face),
      ]);
      leg1 = RectangleComponent(size: Vector2(5, 11), position: Vector2(18, 29), anchor: Anchor.topCenter, paint: face);
      leg2 = RectangleComponent(size: Vector2(5, 11), position: Vector2(43, 29), anchor: Anchor.topCenter, paint: face);
      tail = RectangleComponent(size: Vector2(7, 6), position: Vector2(49, 14), anchor: Anchor.centerLeft, paint: wool);
      addAll([body, leg1!, leg2!, head!, tail!]);



    } else if (type == ObstacleType.animalBird) {

      // 鳥：空中を飛ぶ障害物。高度をランダムにしてジャンプ中にも注意が必要。
      size = Vector2(48, 28);
      position.y = 235 + random.nextDouble() * 70;
      baseSpeed = 245 + random.nextDouble() * 75;

      final feather = Paint()..color = Colors.lightBlue[400]!;
      final beak = Paint()..color = Colors.orangeAccent;
      final body = RectangleComponent(
        size: Vector2(26, 14),
        position: Vector2(13, 8),
        paint: feather,
      );
      head = RectangleComponent(
        size: Vector2(14, 14),
        position: Vector2(0, 6),
        paint: feather,
      );
      head!.addAll([
        CircleComponent(radius: 2, position: Vector2(3, 4), paint: Paint()..color = Colors.black),
        RectangleComponent(size: Vector2(8, 5), position: Vector2(-7, 8), paint: beak),
      ]);
      arm1 = RectangleComponent(
        size: Vector2(18, 6),
        position: Vector2(19, 9),
        anchor: Anchor.centerLeft,
        paint: Paint()..color = Colors.blue[300]!,
      );
      arm2 = RectangleComponent(
        size: Vector2(16, 6),
        position: Vector2(18, 13),
        anchor: Anchor.centerLeft,
        paint: Paint()..color = Colors.blue[200]!,
      );
      tail = RectangleComponent(
        size: Vector2(10, 5),
        position: Vector2(38, 12),
        anchor: Anchor.centerLeft,
        paint: feather,
      );
      addAll([body, arm2!, arm1!, head!, tail!]);


    } else if (type == ObstacleType.animalFrog) {

      // カエル：地面付近をピョンピョン跳ねる。
      size = Vector2(38, 30);
      position.y = 400 - 30;
      baseSpeed = 205 + random.nextDouble() * 55;

      final green = Paint()..color = Colors.green[500]!;
      final darkGreen = Paint()..color = Colors.green[700]!;
      final body = RectangleComponent(size: Vector2(28, 16), position: Vector2(8, 12), paint: green);
      head = RectangleComponent(size: Vector2(22, 14), position: Vector2(0, 5), paint: green);
      head!.addAll([
        CircleComponent(radius: 4, position: Vector2(3, 0), paint: darkGreen),
        CircleComponent(radius: 4, position: Vector2(15, 0), paint: darkGreen),
        CircleComponent(radius: 1.5, position: Vector2(4.5, 1.5), paint: Paint()..color = Colors.black),
        CircleComponent(radius: 1.5, position: Vector2(16.5, 1.5), paint: Paint()..color = Colors.black),
      ]);
      leg1 = RectangleComponent(size: Vector2(13, 6), position: Vector2(12, 25), anchor: Anchor.center, paint: darkGreen);
      leg2 = RectangleComponent(size: Vector2(13, 6), position: Vector2(30, 25), anchor: Anchor.center, paint: darkGreen);
      addAll([body, leg1!, leg2!, head!]);


    } else if (type == ObstacleType.animalBoar) {

      // イノシシ：低い姿勢で他の動物より速く突進する。
      size = Vector2(62, 36);
      position.y = 400 - 36;
      baseSpeed = 300 + random.nextDouble() * 90;

      final fur = Paint()..color = Colors.brown[700]!;
      final dark = Paint()..color = Colors.brown[900]!;
      final ivory = Paint()..color = Colors.yellow[100]!;
      final body = RectangleComponent(size: Vector2(42, 22), position: Vector2(15, 8), paint: fur);
      head = RectangleComponent(size: Vector2(20, 20), position: Vector2(0, 7), paint: dark);
      head!.addAll([
        CircleComponent(radius: 2, position: Vector2(4, 5), paint: Paint()..color = Colors.black),
        RectangleComponent(size: Vector2(8, 7), position: Vector2(-6, 9), paint: dark),
        RectangleComponent(size: Vector2(4, 7), position: Vector2(-2, 16), paint: ivory)..angle = 0.35,
      ]);
      leg1 = RectangleComponent(size: Vector2(6, 10), position: Vector2(20, 28), anchor: Anchor.topCenter, paint: dark);
      leg2 = RectangleComponent(size: Vector2(6, 10), position: Vector2(50, 28), anchor: Anchor.topCenter, paint: dark);
      tail = RectangleComponent(size: Vector2(8, 3), position: Vector2(57, 12), anchor: Anchor.centerLeft, paint: dark);
      addAll([body, leg1!, leg2!, head!, tail!]);



    } else {

      double w = 30 + random.nextDouble() * 30;
      double h = 30 + random.nextDouble() * 30;
      size = Vector2(w, h);
      position.y = 400 - h;
      add(RectangleComponent(size: size, paint: Paint()..color = Colors.grey));
    }



    add(RectangleHitbox());
  }



  @override

  void update(double dt) {

    super.update(dt);



    position.x -= baseSpeed * gameRef.gameSpeed * dt;

    runTime += dt * 20 * gameRef.gameSpeed;



    if (type == ObstacleType.clone) {

      // 左向きで走る人。手足を前後に大きく振る。
      leg1?.angle = -sin(runTime) * 0.7;
      leg2?.angle = sin(runTime) * 0.7;
      arm1?.angle = sin(runTime) * 0.9;
      arm2?.angle = -sin(runTime) * 0.9;

    } else if (
        type == ObstacleType.animalDog ||
        type == ObstacleType.animalDachshund ||
        type == ObstacleType.animalCat ||
        type == ObstacleType.animalFox) {

      leg1?.angle = sin(runTime) * 0.6;
      leg2?.angle = -sin(runTime) * 0.6;
      tail?.angle = sin(runTime * 2.5) * 0.5;

    } else if (type == ObstacleType.animalRabbit) {

      leg1?.angle = sin(runTime * 1.5) * 0.6;
      leg2?.angle = -sin(runTime * 1.5) * 0.6;
      head?.position.y = 4 + sin(runTime * 1.5) * 2;
      tail?.position.y = 30 + sin(runTime * 1.5) * 2;

    } else if (type == ObstacleType.animalSheep) {

      leg1?.angle = sin(runTime) * 0.45;
      leg2?.angle = -sin(runTime) * 0.45;
      head?.position.y = 9 + sin(runTime * 1.2) * 1.5;
      tail?.angle = sin(runTime * 2.0) * 0.25;

    } else if (type == ObstacleType.animalBird) {

      // 羽ばたきながら少し上下する。
      arm1?.angle = sin(runTime * 1.8) * 0.9;
      arm2?.angle = -sin(runTime * 1.8) * 0.9;
      position.y += sin(runTime * 0.22) * 0.9;
      tail?.angle = sin(runTime) * 0.2;

    } else if (type == ObstacleType.animalFrog) {

      // カエルは地面から小さく連続ジャンプ。
      final hop = max(0.0, sin(runTime * 0.55)) * 52.0;
      position.y = (400 - size.y) - hop;
      leg1?.angle = -0.25 - sin(runTime * 0.55) * 0.45;
      leg2?.angle = 0.25 + sin(runTime * 0.55) * 0.45;

    } else if (type == ObstacleType.animalBoar) {

      leg1?.angle = sin(runTime * 1.3) * 0.55;
      leg2?.angle = -sin(runTime * 1.3) * 0.55;
      head?.position.y = 7 + sin(runTime * 2.0) * 1.2;
      tail?.angle = sin(runTime * 2.6) * 0.35;
    }



    if (position.x < -size.x) {
      removeFromParent();
    }
  }



  @override

  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {

    if (other is Player) {
      if (gameRef.isBreakerActive) {
        removeFromParent();
      } else if (gameRef.player.isInvincible) {
        // 無敵中はそのまま通過
      } else if (gameRef.consumeShield()) {
        removeFromParent();
      } else {
        gameRef.gameOver();
      }
    }

    super.onCollisionStart(intersectionPoints, other);
  }
}
