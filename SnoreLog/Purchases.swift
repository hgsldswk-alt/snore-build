import Combine
import Foundation
import Security
import StoreKit

enum TrialAnchor {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.hgsldswk.snore",
        kSecAttrAccount as String: "pro-started-at"
    ]

    static func earliest(_ date: Date) -> Date {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data,
           let value = String(data: data, encoding: .utf8).flatMap(Double.init), value.isFinite {
            let saved = Date(timeIntervalSince1970: value)
            guard date < saved else { return saved }
            let bytes = Data(String(date.timeIntervalSince1970).utf8)
            let attributes: [String: Any] = [kSecValueData as String: bytes]
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(String(date.timeIntervalSince1970).utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
        return date
    }
}

@MainActor
final class Purchases: ObservableObject {
    @Published private(set) var pro: Product?
    @Published private(set) var trial: Product?
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private var listener: Task<Void, Never>?
    private var refreshVersion = 0
    private var onChange: ((Date?, Bool) -> Void)?
    private let proID = Bundle.main.object(forInfoDictionaryKey: "SnoreLogProProductID") as? String ?? "com.hgsldswk.snore.pro"
    private let trialID = Bundle.main.object(forInfoDictionaryKey: "SnoreLogTrialProductID") as? String ?? "com.hgsldswk.snore.trial"

    func start(onChange: @escaping (Date?, Bool) -> Void) {
        guard listener == nil, !Launch.isFree, !Launch.isolated else { return }
        self.onChange = onChange
        listener = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard case .verified(let transaction) = result,
                      [self.proID, self.trialID].contains(transaction.productID) else { continue }
                await self.refresh()
                await transaction.finish()
            }
        }
    }

    func loadProducts() async {
        guard !Launch.isolated else { return }
        do {
            let products = try await Product.products(for: [proID, trialID])
            pro = products.first { $0.id == proID }
            trial = products.first { $0.id == trialID }
            if pro == nil { message = L.t("暂时取不到 App Store 价格") }
        } catch {
            message = L.t("暂时取不到 App Store 价格")
        }
    }

    func refresh() async {
        guard !Launch.isFree, !Launch.isolated else { return }
        refreshVersion += 1
        let version = refreshVersion
        var trialDate: Date?
        var foundPro = false
        var unverifiedPro = false
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard transaction.revocationDate == nil else { continue }
                if transaction.productID == proID { foundPro = true }
                if transaction.productID == trialID {
                    let original = transaction.originalPurchaseDate
                    trialDate = min(trialDate ?? original, original)
                }
            case .unverified(let transaction, _):
                if transaction.productID == proID { unverifiedPro = true }
            }
        }
        guard version == refreshVersion else { return }
        if !unverifiedPro || foundPro {
            onChange?(trialDate, foundPro)
        }
    }

    func buy(_ product: Product?) async {
        guard !busy else { return }
        guard let product else {
            await loadProducts()
            return
        }
        busy = true
        message = nil
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await refresh()
                await transaction.finish()
            case .pending:
                message = L.t("购买正在等待确认")
            case .userCancelled:
                break
            case .success(.unverified(_, _)):
                message = L.t("暂时无法验证购买")
            @unknown default:
                break
            }
        } catch {
            message = L.t("暂时无法完成购买")
        }
    }

    func restore() async {
        guard !busy, !Launch.isolated else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refresh()
            message = L.t("已检查 App Store 购买记录")
        } catch {
            message = L.t("暂时无法恢复购买")
        }
    }
}
