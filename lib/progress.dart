import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Supply {
  shield('バリア', '🛡', 15, '1回の衝突を防ぐ。重ねて使用できます'),
  magnet('磁石', '🧲', 12, '7秒間コインを引き寄せます'),
  star('無敵', '⭐', 25, '5秒間、障害物を通り抜けます'),
  breaker('障害物クリア', '💥', 20, '5秒間、障害物を取り除きます'),
  highJump('ハイジャンプ', '🪽', 12, '7秒間、高くジャンプできます'),
  doubleCoin('コイン2倍', '💰', 18, '8秒間、取ったコインが2倍になります'),
  speedReset('スピードリセット', '🐢', 10, '走る速度をスタート時に戻します');

  const Supply(this.label, this.icon, this.cost, this.description);
  final String label;
  final String icon;
  final int cost;
  final String description;
}

enum RunnerKind {
  human('ランナー', '🏃', 0),
  rabbit('うさぎ', '🐰', 60),
  cat('ねこ', '🐱', 80);

  const RunnerKind(this.label, this.icon, this.cost);
  final String label;
  final String icon;
  final int cost;
}

enum Outfit {
  red('レッド', 0),
  blue('ブルー', 25),
  green('グリーン', 25),
  gold('ゴールド', 100);

  const Outfit(this.label, this.cost);
  final String label;
  final int cost;
}

enum MusicTrack {
  original('オリジナル（SUNO）', 'bgm.mp3'),
  sunny('ひだまりダッシュ', 'sunny_dash.wav'),
  blossom('さくらステップ', 'sakura_step.wav'),
  night('星空ランウェイ', 'starry_run.wav');

  const MusicTrack(this.label, this.file);
  final String label;
  final String file;
}

/// All earned currency and unlocks live in one snapshot so a purchase cannot
/// persist a debit without also persisting the item. No real-money currency.
class GameProgress extends ChangeNotifier {
  static const storageKey = 'animalDash.progress.v1';
  SharedPreferences? _prefs;
  bool ready = false;
  int wallet = 0;
  RunnerKind runner = RunnerKind.human;
  Outfit outfit = Outfit.red;
  MusicTrack music = MusicTrack.original;
  double musicVolume = 0.65;
  final Map<Supply, int> _inventory = {};
  final Set<RunnerKind> _runners = {RunnerKind.human};
  final Set<Outfit> _outfits = {Outfit.red};
  Future<void> _writes = Future<void>.value();
  String? saveError;

  int count(Supply item) => _inventory[item] ?? 0;
  bool ownsRunner(RunnerKind value) => _runners.contains(value);
  bool ownsOutfit(Outfit value) => _outfits.contains(value);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(storageKey);
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        wallet = ((data['wallet'] as num?)?.toInt() ?? 0).clamp(0, 1000000000);
        for (final item in Supply.values) {
          final value = (data['items'] as Map?)?[item.name];
          _inventory[item] = value is num ? value.toInt().clamp(0, 1000000) : 0;
        }
        for (final value in RunnerKind.values) {
          if ((data['runners'] as List?)?.contains(value.name) ?? false) {
            _runners.add(value);
          }
          if (data['runner'] == value.name && _runners.contains(value)) {
            runner = value;
          }
        }
        for (final value in Outfit.values) {
          if ((data['outfits'] as List?)?.contains(value.name) ?? false) {
            _outfits.add(value);
          }
          if (data['outfit'] == value.name && _outfits.contains(value)) {
            outfit = value;
          }
        }
        for (final value in MusicTrack.values) {
          if (data['music'] == value.name) music = value;
        }
        musicVolume = ((data['volume'] as num?)?.toDouble() ?? 0.65).clamp(
          0.0,
          1.0,
        );
      } catch (_) {
        // Preserve the original snapshot instead of silently overwriting it.
        saveError = '保存データを読み込めません。アプリを再起動してください。';
        notifyListeners();
        return;
      }
    }
    // Old highCoins is a record, not a spendable lifetime balance: do not mint it.
    ready = true;
    notifyListeners();
  }

  Future<void> _changed() {
    final snapshot = jsonEncode({
      'wallet': wallet,
      'items': {for (final item in Supply.values) item.name: count(item)},
      'runners': _runners.map((v) => v.name).toList(),
      'outfits': _outfits.map((v) => v.name).toList(),
      'runner': runner.name,
      'outfit': outfit.name,
      'music': music.name,
      'volume': musicVolume,
    });
    notifyListeners();
    return _writes = _writes.then((_) async {
      try {
        if (!await _prefs!.setString(storageKey, snapshot)) {
          throw StateError('save');
        }
        saveError = null;
      } catch (_) {
        saveError = '保存できませんでした。空き容量を確認してください。';
      }
      notifyListeners();
    });
  }

  Future<void> collect(int amount) async {
    if (!ready || amount <= 0) return;
    wallet += amount;
    await _changed();
  }

  bool exchange(Supply item) {
    if (!ready || wallet < item.cost || count(item) >= 1000000) return false;
    wallet -= item.cost;
    _inventory[item] = count(item) + 1;
    unawaited(_changed());
    return true;
  }

  bool use(Supply item) {
    if (!ready || count(item) < 1) return false;
    _inventory[item] = count(item) - 1;
    unawaited(_changed());
    return true;
  }

  bool selectRunner(RunnerKind value) {
    if (!ready || (!_runners.contains(value) && wallet < value.cost)) {
      return false;
    }
    if (_runners.add(value)) wallet -= value.cost;
    runner = value;
    unawaited(_changed());
    return true;
  }

  bool selectOutfit(Outfit value) {
    if (!ready || (!_outfits.contains(value) && wallet < value.cost)) {
      return false;
    }
    if (_outfits.add(value)) wallet -= value.cost;
    outfit = value;
    unawaited(_changed());
    return true;
  }

  void setMusic(MusicTrack value) {
    if (!ready) return;
    music = value;
    unawaited(_changed());
  }

  void setVolume(double value) {
    if (!ready) return;
    musicVolume = value.clamp(0.0, 1.0);
    unawaited(_changed());
  }

  Future<void> flush() => _writes;
}
