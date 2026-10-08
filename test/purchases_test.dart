import 'dart:async';

import 'package:animal_dash/ads.dart';
import 'package:animal_dash/purchases.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('animal_dash/ad_free_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late AdFreePurchase store;
  bool entitlement = false;
  Object? purchaseResult;

  setUp(() {
    entitlement = false;
    purchaseResult = {'status': 'purchased', 'owned': true};
    store = AdFreePurchase(channel: channel);
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'entitlement':
          return entitlement;
        case 'product':
          return {'available': true, 'price': '¥100'};
        case 'purchase':
          return purchaseResult;
        case 'restore':
          return {'status': 'restored', 'owned': entitlement};
      }
      return null;
    });
  });
  tearDown(() {
    store.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> event(bool owned) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('entitlementChanged', owned),
      ),
      (_) {},
    );
  }

  test(
    'purchase, restore and revocation follow verified native ownership',
    () async {
      await store.initialize();
      await store.loadProduct();
      expect(store.ready, isTrue);
      expect(store.owned, isFalse);
      expect(store.price, '¥100');
      await store.purchase();
      expect(store.owned, isTrue);
      entitlement = true;
      await store.restore();
      expect(store.message, '購入を復元しました。');
      await event(false);
      expect(store.owned, isFalse);
    },
  );

  test(
    'pending purchase unlocks only when the transaction update arrives',
    () async {
      purchaseResult = {'status': 'pending'};
      await store.initialize();
      await store.loadProduct();
      await store.purchase();
      expect(store.owned, isFalse);
      expect(store.message, contains('承認待ち'));
      await event(true);
      expect(store.owned, isTrue);
    },
  );

  test(
    'cancelled purchase cannot overwrite a concurrent entitlement update',
    () async {
      await store.initialize();
      await store.loadProduct();
      final response = Completer<Object?>();
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => response.future,
      );
      final purchase = store.purchase();
      await event(true);
      response.complete({'status': 'cancelled', 'owned': false});
      await purchase;
      expect(store.owned, isTrue);
    },
  );

  test(
    'failed ownership lookup stays unknown and cannot grant a purchase',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'UNAVAILABLE'),
      );
      await store.initialize();
      expect(store.ready, isFalse);
      expect(store.owned, isFalse);
      expect(store.message, contains('確認できません'));
    },
  );

  testWidgets(
    'unknown or purchased ownership suppresses banner and interstitial',
    (tester) async {
      final shared = AdFreePurchase.instance;
      shared.ready = false;
      shared.owned = false;
      expect(AdConfig.enabled, isFalse);
      shared.ready = true;
      shared.owned = true;
      addTearDown(() {
        shared.ready = false;
        shared.owned = false;
      });
      expect(AdConfig.enabled, isFalse);
      final manager = InterstitialAdManager();
      var continued = false;
      var shown = false;
      manager.loadAd();
      manager.showAd(
        onFinished: () => continued = true,
        onShown: () => shown = true,
      );
      expect(continued, isTrue);
      expect(shown, isFalse);
      expect(manager.isReady, isFalse);
      manager.dispose();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BannerAdFooter())),
      );
      expect(find.text('プライバシー'), findsOneWidget);
      expect(tester.getSize(find.byType(BannerAdFooter)).height, 36);
      expect(tester.takeException(), isNull);
      shared.owned = false;
      expect(AdConfig.enabled, isTrue);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
}
