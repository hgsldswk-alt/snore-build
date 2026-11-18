import SwiftUI

@main
struct SnoreLogApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task { await model.becameActive() }
                .onChange(of: scenePhase) { _, stage in
                    if stage == .active { Task { await model.becameActive() } }
                    if stage == .background { model.wentIntoBackground() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.tab) {
            NavigationStack(path: $model.path) {
                TonightView()
                    .navigationDestination(for: UUID.self) { id in
                        NightView(nightID: id)
                    }
            }
            .tabItem { tabLabel(.tonight) }.tag(AppTab.tonight)

            NavigationStack {
                HistoryView()
                    .navigationDestination(for: UUID.self) { NightView(nightID: $0) }
            }
            .tabItem { tabLabel(.history) }.tag(AppTab.history)

            NavigationStack { FactorsView() }
                .tabItem { tabLabel(.factors) }.tag(AppTab.factors)

            NavigationStack { SettingsView() }
                .tabItem { tabLabel(.settings) }.tag(AppTab.settings)
        }
        .tint(Palette.accent)
        .onOpenURL(perform: model.openURL)
        .fullScreenCover(isPresented: Binding(get: { model.recordingStart != nil }, set: { _ in })) {
            if let startedAt = model.recordingStart {
                RecordingView(startedAt: startedAt)
            }
        }
        .sheet(isPresented: $model.paywall) { PaywallView(purchases: model.purchases) }
        .sheet(isPresented: Binding(get: { model.shareNightID != nil }, set: { if !$0 { model.shareNightID = nil } })) {
            if let id = model.shareNightID { ShareCardView(nightID: id) }
        }
        .sheet(item: $model.shareFiles) { ActivitySheet(files: $0) }
        .alert(L.t("鼾声记录"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(L.t("好"), role: .cancel) {}
        } message: { Text(model.error ?? "") }
        .preferredColorScheme(Launch.isolated && !Launch.has("-light") ? .dark : nil)
    }

    private func tabLabel(_ tab: AppTab) -> some View {
        Label(tab.title, systemImage: tab.icon).accessibilityIdentifier(tab.rawValue + "Tab")
    }
}
