import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @ObservedObject var purchases: Purchases

    private var price: String? {
        if let price = purchases.pro?.displayPrice { return price }
        if Launch.isolated { return L.t("$3.99") }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeader(title: L.t("鼾声记录买断版"), subtitle: L.t("一次购买，无订阅"))
                        .accessibilityIdentifier("paywallPage")
                    VStack(alignment: .leading, spacing: 14) {
                        perk("waveform", L.t("整晚回放和梦话片段"))
                        perk("chart.xyaxis.line", L.t("因素对比和 7／30／90 天趋势"))
                        perk("square.grid.2x2", L.t("主屏幕小组件"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nightCard(17)

                    Text(L.t("记录、已保存的音频、历史和导出始终可用。")).font(.footnote).foregroundStyle(Palette.secondary)

                    if model.data.entitlement.purchasedPro {
                        Label(L.t("已买断"), systemImage: "checkmark.circle").foregroundStyle(Palette.accent)
                    } else {
                        actions
                    }
                    Button(L.t("恢复购买")) { Task { await purchases.restore() } }
                        .accessibilityIdentifier("restorePurchases")
                        .disabled(purchases.busy)
                    if purchases.busy { ProgressView() }
                    if let note = purchases.message { Text(note).font(.footnote).foregroundStyle(Palette.secondary) }
                }
                .padding(23)
            }
            .background(Palette.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.t("关闭")) { dismiss() }
                }
            }
        }
        .task { await purchases.loadProducts() }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.hasPro && model.remainingDays > 0 {
                Text(L.f("30 天免费体验 · 还剩 %@ 天", String(model.remainingDays)))
                    .font(.subheadline.weight(.semibold))
                Text(L.t("体验结束后，整晚录音、梦话分类、趋势、因素对比和小组件需买断。不会自动扣费。"))
                    .font(.footnote).foregroundStyle(Palette.secondary)
                if model.data.entitlement.trialClaimedAt == nil,
                   Launch.isolated || (purchases.trial != nil && price != nil) {
                    Button(L.t("领取 30 天试用凭证")) { Task { await purchases.buy(purchases.trial) } }
                        .accessibilityIdentifier("trialPurchase")
                        .disabled(purchases.busy)
                }
            }
            Button(price.map { L.f("%@ 一次买断", $0) } ?? L.t("查看买断价格")) {
                Task { await purchases.buy(purchases.pro) }
            }
            .buttonStyle(PrimaryAction())
            .disabled(purchases.busy)
            .accessibilityIdentifier("proPurchase")
        }
    }

    private func perk(_ icon: String, _ title: String) -> some View {
        Label(title, systemImage: icon).foregroundStyle(Palette.ink).font(.subheadline)
    }
}
