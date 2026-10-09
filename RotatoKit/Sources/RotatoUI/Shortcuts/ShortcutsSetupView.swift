import RotatoKit
import SwiftUI

/// How to make rotation automatic. iOS doesn't let apps change the wallpaper, so Rotato provides
/// a "Get Rotato Wallpaper" action and the user's own shortcut hands its image to Apple's
/// "Set Wallpaper" action; Shortcuts automations then run that shortcut on a schedule.
public struct ShortcutsSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""

    public init() {}

    public var body: some View {
        List {
            Section {
                Label {
                    Text("iPhone apps can't change the wallpaper themselves. Rotato picks and prepares each wallpaper; a shortcut of yours sets it, and an automation runs that shortcut on a schedule.")
                } icon: {
                    Image(systemName: "info.circle.fill").foregroundStyle(.tint)
                }
                .font(.subheadline)
            }

            Section("1 · Make the shortcut") {
                step(1, "Open **Shortcuts** and tap **+** to make a new shortcut.")
                step(2, "Name it **\(model.settings.shortcutName)** (or change the name below).")
                step(3, "Add Rotato's **Get Rotato Wallpaper** action and choose **Home Screen**.")
                step(4, "Add **Set Wallpaper**. Pick the wallpaper to change, choose **Lock Screen and Home Screen**, and turn off **Show Preview** and **Crop to Subject**.")
                DisclosureGroup("Different images for home and lock") {
                    Text("Use two pairs instead: **Get Rotato Wallpaper (Home Screen)** → **Set Wallpaper (Home Screen)**, then **Get Rotato Wallpaper (Lock Screen)** → **Set Wallpaper (Lock Screen)**. Collections set to Home only or Lock only feed their own screen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                step(1, "In Shortcuts, open **Automation** and tap **+**.")
                step(2, "Choose **Time of Day**, pick a time and **Daily**. Add one automation per change you want (for example 8:00, 12:00, 18:00).")
                step(3, "Choose **Run Immediately** and turn off **Notify When Run**.")
                step(4, "Pick the **Run Shortcut** action with your **\(model.settings.shortcutName)** shortcut.")
            } header: {
                Text("2 · Run it automatically")
            } footer: {
                Text("Other triggers work too: when you connect a charger, at an alarm, when a Focus starts, or when you open an app. Night auto-pause in Settings keeps the current wallpaper during its hours.")
            }

            Section {
                TextField("Shortcut name", text: $name)
                    .plainTextEntry()
                    .onSubmit(saveName)
                Button {
                    saveName()
                    model.runShortcut()
                } label: {
                    Label("Run my shortcut now", systemImage: "play.circle.fill")
                }
            } header: {
                Text("3 · Try it")
            } footer: {
                Text("Rotato's own \"Set now\" buttons run the shortcut with this name. If nothing happens, check the name matches exactly.")
            }

            Section("More actions") {
                actionRow("Previous Rotato Wallpaper", "Shows the last wallpaper again on the next run.", "arrow.uturn.backward")
                actionRow("Save Current Wallpaper", "Saves what's on your home screen to Favorites.", "star")
                actionRow("Block Current Wallpaper", "Removes it from rotation and never adds it again.", "hand.raised")
            }
        }
        .groupedList()
        .navigationTitle("Shortcuts Setup")
        .inlineTitle()
        .onAppear { name = model.settings.shortcutName }
    }

    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != model.settings.shortcutName else { return }
        model.updateSettings { $0.shortcutName = trimmed }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.tint, in: Circle())
            Text(text).font(.subheadline)
        }
        .padding(.vertical, 2)
    }

    private func actionRow(_ title: String, _ detail: String, _ icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
        }
    }
}
