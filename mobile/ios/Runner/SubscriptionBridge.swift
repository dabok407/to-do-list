import Flutter
import StoreKit
import UIKit

@MainActor
final class SubscriptionBridge {
    static let productID = "hangeoreum_pro_yearly"
    private let channel: FlutterMethodChannel
    private var updates: Task<Void, Never>?
    private var purchasing = false

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "com.dabok407.hangeoreum/billing", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(nil); return }
            Task { @MainActor in
                do {
                    switch call.method {
                    case "status": result(try await self.status())
                    case "restore":
                        try await AppStore.sync()
                        result(try await self.status())
                    case "purchase":
                        guard !self.purchasing else { result(FlutterError(code: "busy", message: "결제가 진행 중이에요.", details: nil)); return }
                        self.purchasing = true
                        defer { self.purchasing = false }
                        guard let product = try await self.product() else { result(try await self.status()); return }
                        var message: String?
                        var pending = false
                        switch try await product.purchase() {
                        case .success(let verification):
                            guard case .verified(let transaction) = verification else {
                                throw NSError(domain: "StoreKitVerification", code: 1)
                            }
                            // Entitlement is derived from verified StoreKit transactions,
                            // never from a local success flag or the device purchase date.
                            await transaction.finish()
                        case .pending: pending = true; message = "결제 승인을 기다리고 있어요. 승인되면 자동으로 반영됩니다."
                        case .userCancelled: message = "결제를 취소했어요."
                        @unknown default: message = "스토어에서 결제 상태를 확인해주세요."
                        }
                        var state = try await self.status()
                        state["pending"] = pending
                        if let message { state["message"] = message }
                        result(state)
                    case "manage":
                        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) else { result(nil); return }
                        try await AppStore.showManageSubscriptions(in: scene)
                        result(try await self.status())
                    default: result(FlutterMethodNotImplemented)
                    }
                } catch {
                    result(FlutterError(code: "store", message: "스토어 연결과 구독 상태를 다시 확인해주세요.", details: nil))
                }
            }
        }
        updates = Task { [weak self] in
            for await verification in Transaction.updates {
                guard !Task.isCancelled else { break }
                guard case .verified(let transaction) = verification,
                      transaction.productID == Self.productID else { continue }
                await transaction.finish()
                self?.channel.invokeMethod("changed", arguments: nil)
            }
        }
    }

    private func product() async throws -> Product? {
        try await Product.products(for: [Self.productID]).first { product in
            product.type == .autoRenewable && product.subscription?.subscriptionPeriod.unit == .year && product.subscription?.subscriptionPeriod.value == 1
        }
    }

    func status() async throws -> [String: Any] {
        var state: [String: Any] = ["active": false, "pending": false, "available": false]
        // Verified current entitlements remain usable offline, including Apple's
        // billing grace period. Revoked/upgraded transactions cannot unlock Pro.
        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification,
                  transaction.productID == Self.productID,
                  transaction.revocationDate == nil, !transaction.isUpgraded else { continue }
            state["active"] = true
            if let expiration = transaction.expirationDate { state["expires"] = Int64(expiration.timeIntervalSince1970 * 1000) }
        }
        do {
            if let product = try await product() {
                state["available"] = true
                state["price"] = product.displayPrice
                if let statuses = try? await product.subscription?.status {
                    for status in statuses {
                        guard case .verified(let transaction) = status.transaction,
                              transaction.productID == Self.productID,
                              case .verified(let renewal) = status.renewalInfo else { continue }
                        if status.state == .subscribed || status.state == .inGracePeriod {
                            state["autoRenewing"] = renewal.willAutoRenew
                            if status.state == .inGracePeriod, let grace = renewal.gracePeriodExpirationDate {
                                state["expires"] = Int64(grace.timeIntervalSince1970 * 1000)
                                state["message"] = "결제 수단을 확인해주세요. 스토어의 유예 기간 동안 Pro를 사용할 수 있어요."
                            }
                        }
                    }
                }
            } else { state["message"] = "스토어 상품 등록 후 구독을 시작할 수 있어요." }
        } catch { state["message"] = "가격을 불러오지 못했어요. 연결 후 다시 확인해주세요." }
        return state
    }

    deinit { updates?.cancel() }
}
