import Flutter
import UIKit
import StoreKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var adFreeStore: AdFreeStore?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "animal_dash/ad_free",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    adFreeStore = AdFreeStore(channel: channel)
  }
}

// StoreKit verifies purchases on the device. No preference flag grants access.
@MainActor
private final class AdFreeStore {
  private static let productID = "com.example.animalDash.remove_ads"
  private let channel: FlutterMethodChannel
  private var updates: Task<Void, Never>?
  private var operationInProgress = false

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      Task { @MainActor in await self.handle(call, result: result) }
    }
    updates = Task { [weak self] in
      for await verification in Transaction.updates {
        guard let self = self else { return }
        guard case .verified(let transaction) = verification,
              transaction.productID == Self.productID else { continue }
        let owned = await self.isOwned()
        self.channel.invokeMethod("entitlementChanged", arguments: owned)
        await transaction.finish()
      }
    }
  }

  deinit { updates?.cancel() }

  private func isOwned() async -> Bool {
    for await verification in Transaction.currentEntitlements {
      if case .verified(let transaction) = verification,
         transaction.productID == Self.productID,
         transaction.productType == .nonConsumable,
         transaction.revocationDate == nil {
        return true
      }
    }
    return false
  }

  private func product() async throws -> Product? {
    try await Product.products(for: [Self.productID]).first
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) async {
    switch call.method {
    case "entitlement":
      result(await isOwned())
    case "product":
      do {
        guard let product = try await product() else {
          result(["available": false])
          return
        }
        result(["available": AppStore.canMakePayments, "price": product.displayPrice])
      } catch {
        result(FlutterError(code: "STORE_UNAVAILABLE", message: "商品情報を取得できません。", details: nil))
      }
    case "purchase", "restore":
      guard !operationInProgress else {
        result(FlutterError(code: "BUSY", message: "購入処理中です。", details: nil))
        return
      }
      operationInProgress = true
      defer { operationInProgress = false }
      do {
        if call.method == "restore" {
          try await AppStore.sync()
          result(["status": "restored", "owned": await isOwned()])
          return
        }
        if await isOwned() {
          result(["status": "purchased", "owned": true])
          return
        }
        guard let product = try await product() else {
          result(FlutterError(code: "STORE_UNAVAILABLE", message: "現在購入できません。", details: nil))
          return
        }
        switch try await product.purchase() {
        case .success(let verification):
          guard case .verified(let transaction) = verification,
                transaction.productID == Self.productID,
                transaction.productType == .nonConsumable,
                transaction.revocationDate == nil else {
            result(FlutterError(code: "UNVERIFIED", message: "購入を確認できませんでした。", details: nil))
            return
          }
          let owned = await isOwned()
          channel.invokeMethod("entitlementChanged", arguments: owned)
          await transaction.finish()
          result(["status": "purchased", "owned": owned])
        case .pending:
          result(["status": "pending"])
        case .userCancelled:
          result(["status": "cancelled"])
        @unknown default:
          result(["status": "cancelled"])
        }
      } catch {
        result(FlutterError(code: "PURCHASE_FAILED", message: "処理が完了しませんでした。時間をおいてお試しください。", details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
