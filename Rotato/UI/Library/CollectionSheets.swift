import SwiftUI

struct SourceOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let sfSymbol: String
}

enum FillMinResolution: String, CaseIterable, Identifiable {
    case any
    case hd
    case fhd
    case fourK

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any"
        case .hd: return "HD"
        case .fhd: return "FHD"
        case .fourK: return "4K"
        }
    }

    var minimumWidth: Int {
        switch self {
        case .any: return 0
        case .hd: return 1280
        case .fhd: return 1920
        case .fourK: return 3840
        }
    }

    var minimumHeight: Int {
        switch self {
        case .any: return 0
        case .hd: return 720
        case .fhd: return 1080
        case .fourK: return 2160
        }
    }

    func matches(_ item: WallpaperItem) -> Bool {
        minimumWidth == 0 || (item.width >= minimumWidth && item.height >= minimumHeight)
    }
}

struct CollectionFillRequest: Equatable {
    var tags = ""
    var count = 25
    var matchAny = false
    var minResolution: FillMinResolution = .any
    var nsfwOverride: Bool? = nil
    var useMalFilter = false
    var sourceId: String? = nil

    var trimmedTags: String {
        tags.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SmartRulesEditorSheet: View {
    let collectionName: String
    let sourceOptions: [SourceOption]
    let initialRules: [SmartRule]
    let onSave: ([SmartRule]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftRules: [SmartRule]

    init(collectionName: String, sourceOptions: [SourceOption], initialRules: [SmartRule], onSave: @escaping ([SmartRule]) -> Void) {
        self.collectionName = collectionName
        self.sourceOptions = sourceOptions
        self.initialRules = initialRules
        self.onSave = onSave
        _draftRules = State(initialValue: initialRules)
    }

    var body: some View {
        NavigationStack {
            Form {
                if draftRules.isEmpty {
                    ContentUnavailableView(
                        "No Rules Yet",
                        systemImage: "sparkles.square.filled.on.square",
                        description: Text("Add include or exclude rules to turn this into a smart collection.")
                    )
                } else {
                    Section("Rules") {
                        ForEach(Array(draftRules.indices), id: \.self) { index in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Rule \(index + 1)")
                                        .font(.headline)
                                    Spacer()
                                    Button(role: .destructive) {
                                        draftRules.remove(at: index)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }

                                Picker(
                                    "Type",
                                    selection: Binding(
                                        get: { draftRules[index].type },
                                        set: { newType in
                                            draftRules[index].type = newType
                                            if newType == .source,
                                               sourceOptions.allSatisfy({ $0.id != draftRules[index].value }) {
                                                draftRules[index].value = sourceOptions.first?.id ?? ""
                                            }
                                        }
                                    )
                                ) {
                                    ForEach(SmartRuleType.allCases) { type in
                                        Text(type.title).tag(type)
                                    }
                                }
                                .pickerStyle(.segmented)

                                Toggle(
                                    "Exclude matches",
                                    isOn: Binding(
                                        get: { draftRules[index].isExclude },
                                        set: { draftRules[index].isExclude = $0 }
                                    )
                                )

                                if draftRules[index].type == .tag {
                                    TextField(
                                        "Tag",
                                        text: Binding(
                                            get: { draftRules[index].value },
                                            set: { draftRules[index].value = $0 }
                                        )
                                    )
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                } else if sourceOptions.isEmpty {
                                    Text("No sources available")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Picker(
                                        "Source",
                                        selection: Binding(
                                            get: {
                                                if sourceOptions.contains(where: { $0.id == draftRules[index].value }) {
                                                    return draftRules[index].value
                                                }
                                                return sourceOptions.first?.id ?? ""
                                            },
                                            set: { draftRules[index].value = $0 }
                                        )
                                    ) {
                                        ForEach(sourceOptions) { option in
                                            Label(option.displayName, systemImage: option.sfSymbol)
                                                .tag(option.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }

                Section {
                    Button {
                        draftRules.append(
                            SmartRule(
                                type: .tag,
                                value: "",
                                isExclude: false
                            )
                        )
                    } label: {
                        Label("Add Rule", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Edit Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let cleaned = draftRules.compactMap { rule -> SmartRule? in
                            let trimmed = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return nil }
                            return SmartRule(id: rule.id, type: rule.type, value: trimmed, isExclude: rule.isExclude)
                        }
                        onSave(cleaned)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct FillFromSourcesSheet: View {
    @Binding var request: CollectionFillRequest
    let sourceOptions: [SourceOption]
    let isLoading: Bool
    let progressMessage: String?
    let onFill: (CollectionFillRequest) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Tags") {
                    TextField("e.g. hatsune_miku blue_hair", text: $request.tags)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isLoading)
                }

                Section("Count") {
                    chipRow {
                        ForEach([10, 25, 50, 100], id: \.self) { count in
                            SelectionChip(title: "\(count)", isSelected: request.count == count) {
                                request.count = count
                            }
                            .disabled(isLoading)
                        }
                    }
                }

                Section("Match Mode") {
                    Picker("Match Mode", selection: $request.matchAny) {
                        Text("All tags (AND)").tag(false)
                        Text("Any tag (OR)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .disabled(isLoading)
                }

                Section("Min Resolution") {
                    chipRow {
                        ForEach(FillMinResolution.allCases) { resolution in
                            SelectionChip(title: resolution.title, isSelected: request.minResolution == resolution) {
                                request.minResolution = resolution
                            }
                            .disabled(isLoading)
                        }
                    }
                }

                Section("NSFW Override") {
                    chipRow {
                        SelectionChip(title: "Auto", isSelected: request.nsfwOverride == nil) {
                            request.nsfwOverride = nil
                        }
                        .disabled(isLoading)
                        SelectionChip(title: "On", isSelected: request.nsfwOverride == true) {
                            request.nsfwOverride = true
                        }
                        .disabled(isLoading)
                        SelectionChip(title: "Off", isSelected: request.nsfwOverride == false) {
                            request.nsfwOverride = false
                        }
                        .disabled(isLoading)
                    }
                }

                Section {
                    Toggle("MAL list only", isOn: $request.useMalFilter)
                        .disabled(isLoading)
                }

                Section("Source") {
                    Picker("Source", selection: $request.sourceId) {
                        Text("All enabled sources").tag(String?.none)
                        ForEach(sourceOptions) { option in
                            Label(option.displayName, systemImage: option.sfSymbol)
                                .tag(Optional(option.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(isLoading)
                }

                if isLoading {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Filling collection…")
                                    .font(.headline)
                                if let progressMessage, !progressMessage.isEmpty {
                                    Text(progressMessage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Fill from Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fill") {
                        onFill(request)
                    }
                    .disabled(isLoading || request.trimmedTags.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func chipRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                content()
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

private struct SelectionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color(.systemFill), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
