import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'purchases.dart';

class AdConfig {
  static const useTestAds = bool.fromEnvironment('USE_TEST_ADS');
  static const captureScreenshots = bool.fromEnvironment('CAPTURE_SCREENSHOTS');
  static bool get enabled =>
      AdFreePurchase.supported &&
      AdFreePurchase.instance.ready &&
      !AdFreePurchase.instance.owned;
  static String get bannerId => useTestAds
      ? 'ca-app-pub-3940256099942544/2934735716'
      : 'ca-app-pub-9003840415284448/8849358073';
  static String get interstitialId => useTestAds
      ? 'ca-app-pub-3940256099942544/4411468910'
      : 'ca-app-pub-9003840415284448/7344704711';
}

class AdPrivacy {
  static Future<bool>? _initialization;
  static final allowed = ValueNotifier<bool>(false);
  static bool optionsRequired = false;

  static Future<bool> initialize() {
    if (!AdConfig.enabled || AdConfig.captureScreenshots) {
      return Future.value(false);
    }
    return _initialization ??= _prepare().then((canServe) {
      if (!AdConfig.enabled) _initialization = null;
      return canServe;
    });
  }

  static Future<bool> _prepare() async {
    if (!AdConfig.enabled || AdConfig.captureScreenshots) return false;
    final consent = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => ConsentForm.loadAndShowConsentFormIfRequired((error) {
        if (error != null) debugPrint('Consent form: $error');
        if (!consent.isCompleted) consent.complete();
      }),
      (error) {
        debugPrint('Consent update: $error');
        if (!consent.isCompleted) consent.complete();
      },
    );
    await consent.future;
    try {
      optionsRequired =
          await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
      final canServe = await ConsentInformation.instance.canRequestAds();
      if (!AdConfig.enabled) return false;
      if (canServe) await MobileAds.instance.initialize();
      if (!AdConfig.enabled) return false;
      allowed.value = canServe;
      return canServe;
    } catch (error) {
      debugPrint('Ads unavailable: $error');
      return false;
    }
  }

  static Future<void> refresh() async {
    allowed.value = false;
    if (!AdConfig.enabled) return;
    final canServe = await ConsentInformation.instance.canRequestAds();
    if (canServe) await MobileAds.instance.initialize();
    _initialization = Future<bool>.value(canServe);
    allowed.value = canServe && AdConfig.enabled;
  }
}

/// Keep a due ad pending if a request failed, rather than waiting three more games.
class InterstitialSchedule {
  int _completedGames = 0;
  bool get isDue => _completedGames >= 3;
  void completeGame() => _completedGames++;
  void didShowAd() => _completedGames = 0;
}

class InterstitialAdManager {
  InterstitialAdManager() {
    AdPrivacy.allowed.addListener(_privacyChanged);
    AdFreePurchase.instance.addListener(_privacyChanged);
  }
  InterstitialAd? _ad;
  Timer? _retry;
  bool _loading = false;
  bool _disposed = false;
  bool get isReady =>
      AdConfig.enabled && AdPrivacy.allowed.value && _ad != null;

  void _privacyChanged() {
    if (AdConfig.enabled && AdPrivacy.allowed.value) {
      loadAd();
    } else {
      _retry?.cancel();
      _ad?.dispose();
      _ad = null;
      if (AdConfig.enabled) loadAd();
    }
  }

  void loadAd() {
    if (!AdConfig.enabled || _loading || _ad != null || _disposed) return;
    _retry?.cancel();
    _loading = true;
    unawaited(_loadAfterConsent());
  }

  Future<void> _loadAfterConsent() async {
    final canServe = await AdPrivacy.initialize();
    if (!canServe ||
        _disposed ||
        !AdPrivacy.allowed.value ||
        !AdConfig.enabled) {
      _loading = false;
      return;
    }
    InterstitialAd.load(
      adUnitId: AdConfig.interstitialId,
      request: const AdRequest(nonPersonalizedAds: true),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          if (_disposed || !AdPrivacy.allowed.value || !AdConfig.enabled) {
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

  void showAd({
    required VoidCallback onFinished,
    required VoidCallback onShown,
  }) {
    final ad = _ad;
    if (ad == null || _disposed || !isReady) {
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
    AdPrivacy.allowed.removeListener(_privacyChanged);
    AdFreePurchase.instance.removeListener(_privacyChanged);
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
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    AdPrivacy.allowed.addListener(_privacyChanged);
    AdFreePurchase.instance.addListener(_privacyChanged);
    if (AdConfig.enabled) _load();
  }

  void _privacyChanged() {
    if (!mounted) return;
    if (AdConfig.enabled && AdPrivacy.allowed.value) {
      setState(() {});
      _load();
    } else {
      _retry?.cancel();
      _ad?.dispose();
      setState(() {
        _ad = null;
        _loaded = false;
      });
      if (AdConfig.enabled) _load();
    }
  }

  Future<void> _load() async {
    if (!mounted || !AdConfig.enabled || _pending || _ad != null) return;
    _pending = true;
    _retry?.cancel();
    final canServe = await AdPrivacy.initialize();
    _pending = false;
    if (!mounted) return;
    setState(() {});
    if (!canServe || !AdPrivacy.allowed.value || !AdConfig.enabled) return;
    final ad = BannerAd(
      adUnitId: AdConfig.bannerId,
      size: AdSize.banner,
      request: const AdRequest(nonPersonalizedAds: true),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted ||
              !AdPrivacy.allowed.value ||
              !AdConfig.enabled ||
              !identical(_ad, ad)) {
            ad.dispose();
            return;
          }
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted || !identical(_ad, ad)) return;
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
    AdPrivacy.allowed.removeListener(_privacyChanged);
    AdFreePurchase.instance.removeListener(_privacyChanged);
    _ad?.dispose();
    super.dispose();
  }
}
