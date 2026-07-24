import MissionControlCore
import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Mission reminders", systemImage: statusIcon)
                    Spacer()
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }

                if model.notificationAuthorizationState == .notDetermined {
                    Button("Allow notifications") {
                        Task {
                            await model.requestNotificationAuthorization()
                        }
                    }
                } else if model.notificationAuthorizationState == .authorized
                    || model.notificationAuthorizationState == .provisional {
                    Button("Refresh pending reminders") {
                        Task {
                            await model.reconcileNotifications()
                        }
                    }
                }
            } footer: {
                Text("Mission Control reconciles local reminders whenever the plan changes so stale mission notifications are removed.")
            }

            Section("Reminder timing") {
                Label("15 minutes before", systemImage: "bell")
                Label("At mission start", systemImage: "play")
                Label("About 15 minutes late if unresolved", systemImage: "clock.badge.exclamationmark")
                Label("About 30 minutes late if unresolved", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
            }

            Section("Actions") {
                Text("Already Started")
                Text("Start Now")
                Text("Replan")
                Text("Skip")
            }
        }
        .task {
            await model.prepareActiveExecution()
        }
    }

    private var statusText: String {
        switch model.notificationAuthorizationState {
        case .notDetermined: "Not requested"
        case .denied: "Off in Settings"
        case .authorized: "Allowed"
        case .provisional: "Provisional"
        case .unavailable: "Unavailable"
        }
    }

    private var statusIcon: String {
        switch model.notificationAuthorizationState {
        case .authorized, .provisional: "bell.badge.fill"
        case .denied: "bell.slash"
        case .notDetermined, .unavailable: "bell"
        }
    }
}
