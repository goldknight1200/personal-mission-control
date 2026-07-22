import Foundation
import MissionControlCore
import SwiftUI

struct MissionControlTabBar: View {
    @Binding var selection: AppTab
    let microphoneAction: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            tabButton(.home)
            tabButton(.goals)

            Button(action: microphoneAction) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(Circle().fill(Color.accentColor))
                    .shadow(color: Color.accentColor.opacity(0.28), radius: 12, y: 6)
            }
            .frame(maxWidth: .infinity)
            .offset(y: -13)
            .accessibilityLabel("Microphone")
            .accessibilityHint("Voice capture arrives in Phase 3")

            tabButton(.lists)
            tabButton(.plan)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 5)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: selection == tab ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 20, weight: .medium))
                Text(tab.title)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}

struct SideMenu: View {
    let profile: UserProfile
    let selection: (MenuDestination) -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.displayName.isEmpty ? "Personal Mission Control" : profile.displayName)
                        .font(.title2.weight(.semibold))
                    Text("Local only · \(profile.timeZoneIdentifier)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close menu")
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Divider()

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(MenuDestination.allCases) { destination in
                        Button {
                            selection(destination)
                        } label: {
                            Label(destination.title, systemImage: destination.icon)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 13)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 10)
            }

            Text("Phase 1 · On-device data")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(22)
        }
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .ignoresSafeArea(edges: .vertical)
        .shadow(color: .black.opacity(0.16), radius: 24, x: -8)
    }
}

struct ScreenMenuButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "line.3.horizontal")
                .font(.headline)
        }
        .accessibilityLabel("Open menu")
    }
}

struct VoicePlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.slash")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Voice capture arrives in Phase 3")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("This control is visual only for now. No recording, transcription, or command processing has started.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
    }
}

struct MenuPlaceholderView: View {
    let destination: MenuDestination

    var body: some View {
        ContentUnavailableView {
            Label(destination.title, systemImage: destination.icon)
        } description: {
            Text(availabilityMessage)
        }
        .padding()
    }

    private var availabilityMessage: String {
        switch destination {
        case .nutrition:
            "Nutrition targets are editable in Profile. Full nutrition planning arrives in Phase 6."
        case .training:
            "Approved training program management arrives in Phase 7."
        case .history:
            "Completion history and consistency summaries arrive in Phase 4."
        case .calendar:
            "Calendar access is not requested in Phase 1. Integration arrives in Phase 8."
        case .health:
            "Health access is not requested in Phase 1. Integration arrives in Phase 8."
        case .notifications:
            "Actionable local notifications arrive in Phase 4."
        case .aiBehavior:
            "No AI provider is used. Optional interpretation arrives in Phase 9."
        case .appSettings:
            "Additional app settings will appear as their local features are implemented."
        case .profile, .appearance:
            ""
        }
    }
}

extension AccentName {
    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .orange: .orange
        case .green: .green
        case .red: .red
        case .teal: .teal
        case .purple: .purple
        case .gray: .gray
        }
    }
}

extension UserProfile {
    func color(for category: MissionCategory) -> Color {
        accent(for: category).color
    }
}

enum MissionControlFormatters {
    static func time(_ date: Date, profile: UserProfile) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: profile.timeZoneIdentifier) ?? .current
        formatter.locale = Locale(identifier: profile.uses24HourTime ? "en_GB" : "en_US")
        formatter.dateFormat = profile.uses24HourTime ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }

    static func timeRange(_ block: ScheduleBlock, profile: UserProfile) -> String {
        "\(time(block.start, profile: profile))–\(time(block.end, profile: profile))"
    }

    static func minuteOfDay(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

struct MissionControlCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
    }
}

extension View {
    func missionControlCard() -> some View {
        modifier(MissionControlCardModifier())
    }
}
