import SwiftUI

struct AutoRotationView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.sparkles")
                            .font(.largeTitle)
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic Rotation")
                                .font(.headline)
                            Text("Powered by Shortcuts")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("iOS doesn't allow apps to set wallpapers directly in the background — but Shortcuts can. " +
                         "By chaining Rotato's \"Fetch Wallpaper\" action with the built-in \"Set Wallpaper\" " +
                         "action in a time-based automation, you get fully automatic wallpaper rotation.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("How it works")
            }

            Section {
                StepRow(number: 1, icon: "arrow.down.app", title: "Open Shortcuts",
                        detail: "Tap the button below to open the Shortcuts app.")
                StepRow(number: 2, icon: "clock.badge.plus", title: "Create an Automation",
                        detail: "Tap the Automation tab → + → Time of Day. Set your desired interval (hourly, daily, etc.).")
                StepRow(number: 3, icon: "app.badge.fill", title: "Add Rotato Action",
                        detail: "Tap \"New Blank Automation\" → search for \"Rotato\" → add \"Fetch Next Wallpaper\".")
                StepRow(number: 4, icon: "photo.badge.arrow.down", title: "Add Set Wallpaper",
                        detail: "After the Rotato action, add the \"Set Wallpaper\" action. Set the wallpaper input to \"Shortcut Input\".")
                StepRow(number: 5, icon: "checkmark.seal.fill", title: "Disable Confirmation",
                        detail: "Toggle OFF \"Ask Before Running\" so the automation fires silently in the background.")
            } header: {
                Text("Setup steps")
            }

            Section {
                Link(destination: URL(string: "shortcuts://")!) {
                    Label("Open Shortcuts", systemImage: "arrow.up.right.square")
                        .foregroundStyle(.blue)
                }
            } header: {
                Text("Launch")
            } footer: {
                Text("Requires iOS 16.4+ for fully silent automations. On iOS 16.0–16.3 you may receive a notification tap prompt.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Home Screen only", systemImage: "house.fill")
                    Label("Lock Screen only", systemImage: "lock.fill")
                    Label("Both screens", systemImage: "rectangle.split.1x2.fill")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } header: {
                Text("Wallpaper target")
            } footer: {
                Text("In the \"Set Wallpaper\" Shortcuts action, choose which screen(s) to update.")
            }
        }
        .navigationTitle("Auto-Rotation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Step Row

private struct StepRow: View {
    let number: Int
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text("\(number)")
                    .font(.system(.headline, design: .rounded).bold())
                    .foregroundStyle(.purple)
            }
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: icon)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
