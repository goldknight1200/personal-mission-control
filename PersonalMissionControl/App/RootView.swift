import Combine
import Foundation
import MissionControlCore
import SwiftUI
import UIKit

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

@MainActor
struct RootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: AppModel
    @StateObject private var voiceCapture: VoiceCaptureViewModel

    @State private var selectedTab: AppTab = .home
    @State private var isMenuOpen = false
    @State private var menuDestination: MenuDestination?

    init(model: AppModel) {
        self.model = model
        _voiceCapture = StateObject(
            wrappedValue: VoiceCaptureViewModel(
                service: AppleSpeechTranscriptionService()
            )
        )
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                selectedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let statusMessage = voiceCapture.statusMessage {
                    Label(
                        statusMessage,
                        systemImage: voiceCapture.isRecording ? "waveform" : "mic"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(voiceCapture.isRecording ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .accessibilityLabel(Text(statusMessage))
                }

                MissionControlTabBar(
                    selection: $selectedTab,
                    isRecording: voiceCapture.isRecording,
                    microphonePressed: {
                        voiceCapture.pressBegan(
                            localeIdentifier: Locale.autoupdatingCurrent.identifier
                        )
                    },
                    microphoneReleased: voiceCapture.pressEnded,
                    microphoneFallback: voiceCapture.presentTextEntry
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
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.22),
            value: isMenuOpen
        )
        .sheet(
            isPresented: $voiceCapture.isReviewPresented,
            onDismiss: voiceCapture.dismissReview
        ) {
            VoiceCommandFlowView(model: model, capture: voiceCapture)
        }
        .sheet(item: $menuDestination) { destination in
            menuSheet(for: destination)
        }
        .sheet(item: $model.executionPrompt) { prompt in
            ExecutionPromptView(model: model, prompt: prompt)
        }
        .alert(
            "Voice capture",
            isPresented: Binding(
                get: { voiceCapture.alertMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        voiceCapture.clearAlert()
                    }
                }
            )
        ) {
            Button("Type instead") {
                voiceCapture.clearAlert()
                voiceCapture.presentTextEntry()
            }
            Button("OK", role: .cancel) {
                voiceCapture.clearAlert()
            }
        } message: {
            Text(voiceCapture.alertMessage ?? "")
        }
        .task {
            await model.prepareActiveExecution()
            await model.preparePlatformIntegrations()
            if MissionControlIntentBridge.shared.consumeCaptureRequest() {
                voiceCapture.presentTextEntry()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .missionControlCaptureRequested
            )
        ) { _ in
            if MissionControlIntentBridge.shared.consumeCaptureRequest() {
                voiceCapture.presentTextEntry()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSSystemTimeZoneDidChange
            )
        ) { _ in
            model.handleSignificantTimeChange()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.significantTimeChangeNotification
            )
        ) { _ in
            model.handleSignificantTimeChange()
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .home:
            HomeView(
                model: model,
                openMenu: openMenu,
                voicePressed: {
                    voiceCapture.pressBegan(
                        localeIdentifier: Locale.autoupdatingCurrent.identifier
                    )
                },
                voiceReleased: voiceCapture.pressEnded,
                voiceFallback: voiceCapture.presentTextEntry
            )
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
                case .nutrition:
                    NutritionView(model: model)
                case .training:
                    TrainingProgramView(model: model)
                case .appearance:
                    AppearanceSettingsView(profile: model.snapshot.profile, onSave: model.updateProfile)
                case .history:
                    HistoryConsistencyView(model: model)
                case .notifications:
                    NotificationSettingsView(model: model)
                case .calendar:
                    CalendarIntegrationView(model: model)
                case .health:
                    HealthIntegrationView(model: model)
                case .aiBehavior:
                    AIBehaviorSettingsView(model: model)
                case .appSettings:
                    PrivacyAndDataSettingsView(model: model)
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
