import SwiftUI

struct MalSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var isAuthenticating = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    private let allStatuses = ["watching", "completed", "on_hold", "dropped", "plan_to_watch"]

    var body: some View {
        Form {
            Section {
                if settings.malUsername.isEmpty {
                    Button {
                        Task { await authenticate() }
                    } label: {
                        HStack {
                            Label("Connect MAL Account", systemImage: "link")
                            Spacer()
                            if isAuthenticating { ProgressView().scaleEffect(0.8) }
                        }
                    }
                    .disabled(isAuthenticating)
                } else {
                    LabeledContent("Connected as", value: settings.malUsername)
                    Button("Disconnect", role: .destructive) { disconnect() }
                }
            } header: {
                Text("MyAnimeList Account")
            } footer: {
                Text("Connect your MAL account to use your anime list as search tags on Gelbooru/Danbooru.")
            }

            if !settings.malUsername.isEmpty {
                Section("List Filters") {
                    @Bindable var settings = settings
                    Stepper("Min Score: \(settings.malMinScore)",
                            value: $settings.malMinScore,
                            in: 0...10)

                    let currentStatuses = settings.malFilterStatuses
                    ForEach(allStatuses, id: \.self) { status in
                        Toggle(displayName(for: status), isOn: Binding(
                            get: { currentStatuses.contains(status) },
                            set: { enabled in
                                var s = settings.malFilterStatuses
                                if enabled { s.insert(status) } else { s.remove(status) }
                                settings.malFilterStatuses = s
                            }
                        ))
                    }
                }

                Section {
                    Button {
                        Task { await refreshList() }
                    } label: {
                        HStack {
                            Label("Refresh Anime List", systemImage: "arrow.clockwise")
                            Spacer()
                            if isRefreshing { ProgressView().scaleEffect(0.8) }
                        }
                    }
                    .disabled(isRefreshing)

                    if !settings.malAnimeList.isEmpty {
                        LabeledContent("Titles loaded", value: "\(settings.malAnimeList.count)")
                    }
                } header: {
                    Text("Anime List")
                } footer: {
                    Text("Refreshed titles are used as search suggestions in Discover.")
                }
            }

            if let error = errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }
            if let status = statusMessage {
                Section {
                    Label(status, systemImage: "checkmark.circle").foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("MyAnimeList")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func authenticate() async {
        isAuthenticating = true
        errorMessage = nil
        do {
            try await MalService.shared.authenticate(settings: settings)
            // Fetch username
            try await fetchUsername()
            await refreshList()
            statusMessage = "Connected!"
        } catch {
            errorMessage = error.localizedDescription
        }
        isAuthenticating = false
    }

    private func fetchUsername() async throws {
        guard let url = URL(string: "https://api.myanimelist.net/v2/users/@me") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(settings.malAccessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct User: Decodable { let name: String }
        let user = try JSONDecoder().decode(User.self, from: data)
        settings.malUsername = user.name
    }

    private func refreshList() async {
        isRefreshing = true
        errorMessage = nil
        do {
            let titles = try await MalService.shared.fetchAnimeList(settings: settings)
            settings.malAnimeList = titles
            statusMessage = "Loaded \(titles.count) titles"
        } catch {
            errorMessage = error.localizedDescription
        }
        isRefreshing = false
    }

    private func disconnect() {
        settings.malAccessToken = ""
        settings.malRefreshToken = ""
        settings.malUsername = ""
        settings.malAnimeList = []
        statusMessage = nil
        errorMessage = nil
    }

    private func displayName(for status: String) -> String {
        switch status {
        case "watching": return "Watching"
        case "completed": return "Completed"
        case "on_hold": return "On Hold"
        case "dropped": return "Dropped"
        case "plan_to_watch": return "Plan to Watch"
        default: return status.capitalized
        }
    }
}
