import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AdFreePurchase extends ChangeNotifier with WidgetsBindingObserver {
  AdFreePurchase({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('animal_dash/ad_free');

  static final instance = AdFreePurchase();
  final MethodChannel _channel;
  bool ready = false;
  bool owned = false;
  bool available = false;
  bool busy = false;
  String? price;
  String? message;
  Future<void>? _initialization;
  bool _disposed = false;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> initialize() => _initialization ??= _initialize();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _initialize() async {
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'entitlementChanged' && call.arguments is bool) {
        owned = call.arguments as bool;
        ready = true;
        message = owned ? '広告を削除しました。' : null;
        _notify();
      }
    });
    await refreshEntitlement();
    unawaited(loadProduct());
  }

  Future<void> refreshEntitlement() async {
    try {
      owned = await _channel.invokeMethod<bool>('entitlement') ?? false;
      ready = true;
    } catch (_) {
      // Keep ads suppressed if ownership could not be checked.
      message = '購入状態を確認できません。時間をおいてお試しください。';
    }
    _notify();
  }

  Future<void> loadProduct() async {
    try {
      final product = await _channel.invokeMapMethod<String, dynamic>(
        'product',
      );
      price = product?['price'] as String?;
      available = product?['available'] == true && price != null;
    } catch (_) {
      available = false;
    }
    _notify();
  }

  Future<void> purchase() async {
    if (busy || owned || !available) return;
    await _perform('purchase');
  }

  Future<void> restore() async {
    if (busy) return;
    await _perform('restore');
  }

  Future<void> _perform(String method) async {
    busy = true;
    message = null;
    _notify();
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(method);
      if (result?['status'] == 'purchased' || result?['status'] == 'restored') {
        // Only an authoritative entitlement response can change ownership.
        if (result?['owned'] is bool) {
          owned = result!['owned'] as bool;
          ready = true;
        }
      }
      switch (result?['status']) {
        case 'pending':
          message = '購入の承認待ちです。承認後に広告が削除されます。';
        case 'cancelled':
          message = null;
        case 'restored':
          message = owned ? '購入を復元しました。' : '復元できる購入はありませんでした。';
        case 'purchased':
          message = owned ? '広告を削除しました。' : '購入状態を確認できませんでした。';
      }
    } on PlatformException catch (error) {
      message = error.message ?? '処理が完了しませんでした。もう一度お試しください。';
    } catch (_) {
      message = '処理が完了しませんでした。もう一度お試しください。';
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refreshEntitlement());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}

Future<void> showAdFreePurchase(BuildContext context) async {
  final store = AdFreePurchase.instance;
  unawaited(store.loadProduct());
  await showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) => AlertDialog(
        title: const Text('広告を削除'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('バナー広告と全画面広告を非表示にします。\n買い切り・月額料金なし。'),
              const SizedBox(height: 12),
              Text(
                store.owned
                    ? '購入済み：広告なしで遊べます。'
                    : store.available
                    ? '価格：${store.price}'
                    : '現在、商品情報を取得できません。',
              ),
              const SizedBox(height: 8),
              const Text('再インストールや機種変更後は、同じApple Accountで「購入を復元」を選んでください。'),
              if (store.busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (store.message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(store.message!),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: store.busy ? null : store.restore,
            child: const Text('購入を復元'),
          ),
          if (!store.owned)
            FilledButton(
              onPressed: store.busy || !store.available ? null : store.purchase,
              child: Text(
                store.price == null ? '広告を削除' : '${store.price}で広告を削除',
              ),
            ),
          TextButton(
            onPressed: store.busy ? null : () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    ),
  );
}
