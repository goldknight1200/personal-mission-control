import MissionControlCore
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case goals
    case lists
    case plan

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .home: "house"
        case .goals: "scope"
        case .lists: "checklist"
        case .plan: "calendar"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: "house.fill"
        case .goals: "scope"
        case .lists: "checklist"
        case .plan: "calendar.circle.fill"
        }
    }
}

enum MenuDestination: String, CaseIterable, Identifiable {
    case profile
    case nutrition
    case training
    case history
    case calendar
    case health
    case notifications
    case aiBehavior
    case appearance
    case appSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: "Profile"
        case .nutrition: "Nutrition setup"
        case .training: "Training programs"
        case .history: "History & statistics"
        case .calendar: "Calendar integrations"
        case .health: "Health integration"
        case .notifications: "Notification settings"
        case .aiBehavior: "AI behavior"
        case .appearance: "Appearance"
        case .appSettings: "App settings"
        }
    }

    var icon: String {
        switch self {
        case .profile: "person.crop.circle"
        case .nutrition: "fork.knife"
        case .training: "figure.strengthtraining.traditional"
        case .history: "chart.line.uptrend.xyaxis"
        case .calendar: "calendar.badge.plus"
        case .health: "heart"
        case .notifications: "bell"
        case .aiBehavior: "sparkles"
        case .appearance: "paintpalette"
        case .appSettings: "gearshape"
        }
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel

    @State private var selectedTab: AppTab = .home
    @State private var isMenuOpen = false
    @State private var menuDestination: MenuDestination?
    @State private var isVoicePlaceholderPresented = false

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                selectedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                MissionControlTabBar(
                    selection: $selectedTab,
                    microphoneAction: { isVoicePlaceholderPresented = true }
                )
            }

            if isMenuOpen {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture { closeMenu() }
                    .transition(.opacity)

                SideMenu(
                    profile: model.snapshot.profile,
                    selection: { destination in
                        closeMenu()
                        menuDestination = destination
                    },
                    close: closeMenu
                )
                .frame(maxWidth: 340)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isMenuOpen)
        .sheet(isPresented: $isVoicePlaceholderPresented) {
            VoicePlaceholderView()
                .presentationDetents([.medium])
        }
        .sheet(item: $menuDestination) { destination in
            menuSheet(for: destination)
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .home:
            HomeView(model: model, openMenu: openMenu)
        case .goals:
            GoalsView(model: model, openMenu: openMenu)
        case .lists:
            ListsView(model: model, openMenu: openMenu)
        case .plan:
            PlanView(model: model, openMenu: openMenu)
        }
    }

    @ViewBuilder
    private func menuSheet(for destination: MenuDestination) -> some View {
        NavigationStack {
            Group {
                switch destination {
                case .profile:
                    ProfileSettingsView(profile: model.snapshot.profile, onSave: model.updateProfile)
                case .appearance:
                    AppearanceSettingsView(profile: model.snapshot.profile, onSave: model.updateProfile)
                default:
                    MenuPlaceholderView(destination: destination)
                }
            }
            .navigationTitle(destination.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { menuDestination = nil }
                }
            }
        }
    }

    private func openMenu() {
        isMenuOpen = true
    }

    private func closeMenu() {
        isMenuOpen = false
    }
}
