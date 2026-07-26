import Foundation
import MissionControlCore
import SwiftUI

struct MissionControlTabBar: View {
    @Binding var selection: AppTab
    let isRecording: Bool
    let microphonePressed: () -> Void
    let microphoneReleased: () -> Void
    let microphoneFallback: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            tabButton(.home)
            tabButton(.goals)

            MicrophoneCaptureButton(
                isRecording: isRecording,
                pressBegan: microphonePressed,
                pressEnded: microphoneReleased,
                accessibilityAction: microphoneFallback
            )
            .frame(maxWidth: .infinity)
            .offset(y: -13)

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

private struct MicrophoneCaptureButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var haloSize = 76
    @ScaledMetric(relativeTo: .body) private var buttonSize = 62
    @ScaledMetric(relativeTo: .body) private var iconSize = 25

    let isRecording: Bool
    let pressBegan: () -> Void
    let pressEnded: () -> Void
    let accessibilityAction: () -> Void

    @State private var isPressed = false

    var body: some View {
        ZStack {
            if isRecording {
                Circle()
                    .fill(Color.red.opacity(0.16))
                    .frame(width: haloSize, height: haloSize)
            }

            Image(systemName: isRecording ? "waveform" : "mic.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle().fill(isRecording ? Color.red : Color.accentColor)
                )
                .scaleEffect(isPressed ? 0.94 : 1)
                .shadow(
                    color: (isRecording ? Color.red : Color.accentColor).opacity(0.28),
                    radius: 12,
                    y: 6
                )
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    pressBegan()
                }
                .onEnded { _ in
                    guard isPressed else { return }
                    isPressed = false
                    pressEnded()
                }
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: isPressed
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: isRecording
        )
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            Text(isRecording ? "Recording voice command" : "Voice command")
        )
        .accessibilityHint(
            "Press and hold to record, then release to review. Activate to type instead."
        )
        .accessibilityAction {
            accessibilityAction()
        }
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

            Text("Phase 9 · Local-first beta hardening")
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
            ""
        case .training:
            ""
        case .history:
            ""
        case .calendar:
            ""
        case .health:
            ""
        case .notifications:
            ""
        case .aiBehavior:
            ""
        case .appSettings:
            ""
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
