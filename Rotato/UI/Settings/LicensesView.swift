import SwiftUI

private struct LicenseItem: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let license: String
    let url: String
}

struct LicensesView: View {
    @Environment(\.openURL) private var openURL

    private let items: [LicenseItem] = [
        LicenseItem(
            name: "Rotato iOS",
            detail: "This app is open source",
            license: "MIT",
            url: "https://github.com/Alvis1337/rotato-ios"
        ),
        LicenseItem(
            name: "SwiftUI",
            detail: "Declarative UI framework",
            license: "Apple SDK",
            url: "https://developer.apple.com/xcode/swiftui/"
        ),
        LicenseItem(
            name: "SwiftData",
            detail: "Persistent model storage",
            license: "Apple SDK",
            url: "https://developer.apple.com/documentation/swiftdata"
        ),
        LicenseItem(
            name: "AuthenticationServices",
            detail: "OAuth / web authentication sessions (MAL login)",
            license: "Apple SDK",
            url: "https://developer.apple.com/documentation/authenticationservices"
        ),
        LicenseItem(
            name: "Photos",
            detail: "Save wallpapers to Photo Library",
            license: "Apple SDK",
            url: "https://developer.apple.com/documentation/photokit"
        ),
        LicenseItem(
            name: "Network",
            detail: "Network path monitoring (Wi‑Fi only mode)",
            license: "Apple SDK",
            url: "https://developer.apple.com/documentation/network"
        ),
    ]

    var body: some View {
        List(items) { item in
            Button {
                if let url = URL(string: item.url) { openURL(url) }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(item.name)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(item.license)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Open Source Licenses")
        .navigationBarTitleDisplayMode(.large)
    }
}
