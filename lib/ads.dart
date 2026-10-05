import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdConfig {
  static const useTestAds = bool.fromEnvironment('USE_TEST_ADS');
  static bool get enabled =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static String get bannerId => useTestAds
      ? 'ca-app-pub-3940256099942544/2934735716'
      : 'ca-app-pub-9003840415284448/8849358073';
  static String get interstitialId => useTestAds
      ? 'ca-app-pub-3940256099942544/4411468910'
      : 'ca-app-pub-9003840415284448/7344704711';
}

/// Keep a due ad pending if a request failed, rather than waiting three more games.
class InterstitialSchedule {
  int _completedGames = 0;
  bool get isDue => _completedGames >= 3;
  void completeGame() => _completedGames++;
  void didShowAd() => _completedGames = 0;
}

class InterstitialAdManager {
  InterstitialAd? _ad;
  Timer? _retry;
  bool _loading = false;
  bool _disposed = false;
  bool get isReady => _ad != null;

  void loadAd() {
    if (!AdConfig.enabled || _loading || _ad != null || _disposed) return;
    _retry?.cancel();
    _loading = true;
    InterstitialAd.load(
      adUnitId: AdConfig.interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          if (_disposed) {
            ad.dispose();
            return;
          }
          _ad = ad;
        },
        onAdFailedToLoad: (error) {
          _loading = false;
          debugPrint('Interstitial load failed: $error');
          if (!_disposed) _retry = Timer(const Duration(seconds: 20), loadAd);
        },
      ),
    );
  }

  void showAd({required VoidCallback onFinished, required VoidCallback onShown}) {
    final ad = _ad;
    if (ad == null || _disposed) {
      loadAd();
      onFinished();
      return;
    }
    _ad = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => onShown(),
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!_disposed) {
          onFinished();
          loadAd();
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        debugPrint('Interstitial show failed: $error');
        if (!_disposed) {
          onFinished();
          loadAd();
        }
      },
    );
    ad.show();
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _ad?.dispose();
    _ad = null;
  }
}

/// A separate footer keeps ads from covering the ground or jump controls.
class BannerAdFooter extends StatefulWidget {
  const BannerAdFooter({super.key});
  @override
  State<BannerAdFooter> createState() => _BannerAdFooterState();
}

class _BannerAdFooterState extends State<BannerAdFooter> {
  BannerAd? _ad;
  Timer? _retry;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (AdConfig.enabled) _load();
  }

  void _load() {
    if (!mounted) return;
    _retry?.cancel();
    final ad = BannerAd(
      adUnitId: AdConfig.bannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _ad = null;
            _loaded = false;
          });
          debugPrint('Banner load failed: $error');
          _retry = Timer(const Duration(seconds: 20), _load);
        },
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdConfig.enabled) return const SizedBox.shrink();
    return SizedBox(
      height: AdSize.banner.height.toDouble(),
      child: Center(
        child: _loaded && _ad != null
            ? SizedBox(
                width: _ad!.size.width.toDouble(),
                height: _ad!.size.height.toDouble(),
                child: AdWidget(ad: _ad!),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  @override
  void dispose() {
    _retry?.cancel();
    _ad?.dispose();
    super.dispose();
  }
}
