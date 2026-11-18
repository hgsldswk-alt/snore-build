import SwiftUI
import UIKit

struct FactorsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    PageHeader(title: L.t("因素"))
                    NavigationLink(L.t("编辑")) { FactorEditor() }.font(.subheadline)
                }
                Text(L.t("每组至少 3 晚才显示平均分差")).font(.subheadline).foregroundStyle(Palette.secondary)
                if model.hasPro {
                    ForEach(model.data.customFactors, id: \.self) { factor in
                        comparison(factor)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.t("查看有无某个因素时的平均分差"))
                            .foregroundStyle(Palette.secondary)
                        Button(L.t("解锁因素对比")) { model.paywall = true }.buttonStyle(PrimaryAction())
                    }
                    .nightCard()
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .background(Palette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("factorsPage")
    }

    private func comparison(_ factor: String) -> some View {
        let result = FactorStats.comparison(factor, nights: model.nights)
        let scored = model.nights.filter { $0.score != nil }
        let count = scored.filter { $0.factors.contains(factor) }.count
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.t(factor)).font(.headline)
                Spacer(minLength: 8)
                if let result {
                    Text(NightInsights.comparisonLabel(result.difference))
                        .foregroundStyle(result.difference < 0 ? Palette.accent : Palette.secondary)
                } else {
                    Text(L.t("再记几晚")).foregroundStyle(Palette.secondary)
                }
            }
            if let result {
                HStack(alignment: .top) {
                    Text(groupLabel(true, count: result.withCount, average: result.withAverage))
                    Spacer()
                    Text(groupLabel(false, count: result.withoutCount, average: result.withoutAverage))
                }
                .font(.footnote)
                .foregroundStyle(Palette.secondary)
            } else {
                Text(L.f("有 %@ 晚 · 无 %@ 晚", String(count), String(scored.count - count)))
                    .font(.footnote).foregroundStyle(Palette.secondary)
            }
        }
        .nightCard()
    }

    private func groupLabel(_ hasFactor: Bool, count: Int, average: Double) -> String {
        L.f(hasFactor ? "有 · %@ 晚 · 均分 %@" : "无 · %@ 晚 · 均分 %@",
            String(count), String(format: "%.1f", locale: .current, average))
    }
}

struct FactorEditor: View {
    @EnvironmentObject private var model: AppModel
    @State private var text = ""
    @State private var copied = false

    var body: some View {
        List {
            Section(L.t("我的因素")) {
                ForEach(model.data.customFactors, id: \.self) { factor in
                    Text(L.t(factor))
                }
                .onDelete { indices in
                    var factors = model.data.customFactors
                    factors.remove(atOffsets: indices)
                    model.setFactors(factors)
                }
                HStack {
                    TextField(L.t("新因素"), text: $text).submitLabel(.done).onSubmit(add)
                    Button(L.t("添加"), action: add).buttonStyle(.borderless)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Section {
                Button(L.t(copied ? "已复制因素清单" : "复制因素清单")) {
                    if let encoded = try? FactorList.encode(model.data.customFactors) {
                        UIPasteboard.general.string = encoded
                        copied = true
                    }
                }
                .disabled(model.data.customFactors.isEmpty)
                PasteButton(payloadType: String.self) { items in
                    guard let first = items.first, let factors = try? FactorList.decode(first) else {
                        model.error = L.t("这段文字里没有可导入的因素清单")
                        return
                    }
                    model.setFactors(model.data.customFactors + factors)
                }
                Button(L.t("恢复默认因素")) { model.setFactors(FactorList.defaults) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(L.t("编辑因素"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { EditButton() }
    }

    private func add() {
        model.setFactors(model.data.customFactors + [text])
        text = ""
    }
}
