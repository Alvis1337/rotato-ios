import SwiftUI
import AppIntents

struct AutoRotationView: View {
    @State private var isShareSheetPresented = false

    var body: some View {
        List {
            // MARK: - Get Shortcut (primary CTA)
            Section {
                VStack(spacing: 14) {
                    // ShortcutsLink: opens Shortcuts and shows Rotato's actions page
                    ShortcutsLink()
                        .shortcutsLinkStyle(.automaticOutline)
                        .frame(maxWidth: .infinity)

                    // Also let user share/export the pre-built .shortcut file
                    Button {
                        isShareSheetPresented = true
                    } label: {
                        Label("Share Shortcut File", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
                .sheet(isPresented: $isShareSheetPresented) {
                    ShareShortcutSheet()
                }
            } header: {
                Text("Install shortcut")
            } footer: {
                Text("\"Add to Siri\" installs the shortcut instantly. \"Share\" lets you send the .shortcut file to a friend or your other devices — they just tap it to import.")
            }

            // MARK: - How it works
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.sparkles")
                            .font(.largeTitle)
                            .foregroundStyle(Color.accentColor)
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

            // MARK: - Setup steps
            Section {
                StepRow(number: 1, icon: "arrow.down.app", title: "Add the Shortcut",
                        detail: "Tap \"Add to Siri\" above, or open the shared .shortcut file — then tap \"Add Shortcut\".")
                StepRow(number: 2, icon: "clock.badge.plus", title: "Create an Automation",
                        detail: "Open Shortcuts → Automation tab → + → Time of Day. Set your desired interval.")
                StepRow(number: 3, icon: "app.badge.fill", title: "Add Rotato Action",
                        detail: "Tap \"New Blank Automation\" → search \"Rotato\" → add \"Rotate Wallpaper\" (or \"Fetch Next Wallpaper\").")
                StepRow(number: 4, icon: "photo.badge.arrow.down", title: "Add Set Wallpaper",
                        detail: "After the Rotato action, tap + and add \"Set Wallpaper\". The image output is passed automatically.")
                StepRow(number: 5, icon: "checkmark.seal.fill", title: "Disable Confirmation",
                        detail: "Toggle OFF \"Ask Before Running\" so the automation fires silently in the background.")
            } header: {
                Text("Setup steps")
            }

            // MARK: - Wallpaper target
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
                Text("In the \"Set Wallpaper\" Shortcuts action, choose which screen(s) to update. Requires iOS 16.4+ for fully silent automations.")
            }
        }
        .navigationTitle("Auto-Rotation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Share Sheet

/// Wraps UIActivityViewController to share the bundled .shortcut file.
private struct ShareShortcutSheet: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let url = Bundle.main.url(forResource: "RotatoAutoWallpaper", withExtension: "shortcut")
        let items: [Any] = url.map { [$0] } ?? ["Could not find the shortcut file."]
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text("\(number)")
                    .font(.system(.headline, design: .rounded).bold())
                    .foregroundStyle(Color.accentColor)
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
