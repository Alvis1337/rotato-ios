import SwiftUI

struct SourceHealthView: View {
    @Environment(AppSettings.self) private var settings
    @State private var testingIds: Set<String> = []

    var body: some View {
        List {
            ForEach(PluginRegistry.all, id: \.id) { plugin in
                let config = settings.config(for: plugin.id)
                let health = settings.sourceHealth[plugin.id]
                SourceHealthRow(
                    plugin: plugin,
                    config: config,
                    health: health,
                    isTesting: testingIds.contains(plugin.id),
                    onTest: { testPlugin(plugin) }
                )
            }
        }
        .navigationTitle("Source Health")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Test All") { testAll() }
                    .disabled(!testingIds.isEmpty)
            }
        }
    }

    private func testPlugin(_ plugin: any SourcePlugin) {
        let id = plugin.id
        guard !testingIds.contains(id) else { return }
        testingIds.insert(id)

        Task {
            let config = settings.config(for: id)
            var result = settings.sourceHealth[id] ?? SourceHealthResult()
            result.isTesting = true
            settings.updateHealth(result, for: id)

            do {
                let items = try await plugin.fetch(query: "", page: 0, config: config, nsfw: false)
                if items.isEmpty {
                    result.lastError = "Fetch succeeded but returned 0 items"
                } else {
                    result.lastSuccess = Date()
                    result.lastError = nil
                    result.successCount += 1
                }
                result.totalFetches += 1
                result.isTesting = false
            } catch {
                result.lastError = error.localizedDescription
                result.totalFetches += 1
                result.isTesting = false
            }
            settings.updateHealth(result, for: id)
            testingIds.remove(id)
        }
    }

    private func testAll() {
        for plugin in PluginRegistry.all {
            let config = settings.config(for: plugin.id)
            guard config.enabled else { continue }
            testPlugin(plugin)
        }
    }
}

private struct SourceHealthRow: View {
    let plugin: any SourcePlugin
    let config: SourceConfig
    let health: SourceHealthResult?
    let isTesting: Bool
    let onTest: () -> Void

    private var statusSymbol: String {
        if isTesting { return "circle.dotted" }
        if let h = health {
            if h.lastSuccess != nil && h.lastError == nil { return "checkmark.circle.fill" }
            if h.lastError != nil { return "xmark.circle.fill" }
        }
        return "questionmark.circle"
    }

    private var statusColor: Color {
        if isTesting { return .secondary }
        if let h = health {
            if h.lastSuccess != nil && h.lastError == nil { return .green }
            if h.lastError != nil { return .red }
        }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: plugin.sfSymbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(plugin.displayName)
                    .font(.headline)
                Spacer()
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                    .symbolEffect(.pulse, isActive: isTesting)
                if !config.enabled {
                    Text("Disabled")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }

            if let h = health {
                if let lastSuccess = h.lastSuccess {
                    Text("Last success: \(lastSuccess.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if h.totalFetches > 0 {
                    Text("\(h.successCount)/\(h.totalFetches) fetches succeeded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let err = h.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            } else {
                Text("Never tested")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button(isTesting ? "Testing…" : "Test") { onTest() }
                    .disabled(isTesting)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
