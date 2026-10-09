import RotatoKit
import SwiftUI

extension AppModel {
    /// Fills a collection from the enabled sources off the main thread. Returns the new entry
    /// ids (for Undo) and shows a summary.
    @discardableResult
    func fill(_ c: WallpaperCollection, tags: String, count: Int, pluginId: String?, instanceId: String?) async -> Set<String> {
        let before = Set(entries(in: c.id).map(\.id))
        let db = self.db, listId = c.id
        let added = await Task.detached {
            await CollectionFiller(db: db).fill(listId: listId, tags: tags, count: count, pluginId: pluginId, instanceId: instanceId)
        }.value
        afterCollectionsChange()
        showToast(added == 0 ? "No new images found. Try different tags or sources."
                  : added < count ? "Added \(added) of \(count). That's all the sources had."
                  : "Added \(added) to \(c.name)")
        return Set(entries(in: c.id).map(\.id)).subtracting(before)
    }

    /// Saves picked photos into a collection as device images.
    func importPhotos(_ datas: [Data], into c: WallpaperCollection) {
        var n = 0
        for data in datas {
            let b = [UInt8](data.prefix(12))
            let ext = b.count >= 2 && b[0] == 0x89 && b[1] == 0x50 ? "png"
                : b.count >= 8 && b[4] == 0x66 && b[5] == 0x74 ? "heic" : "jpg"
            let name = "\(UUID().uuidString.lowercased()).\(ext)"
            guard (try? data.write(to: RotatoPaths.device.appendingPathComponent(name), options: .atomic)) != nil else { continue }
            collectionsRepo.addDeviceImage(fileName: name, to: c.id)
            n += 1
        }
        afterCollectionsChange()
        showToast("Added \(n) photo\(n == 1 ? "" : "s") to \(c.name)")
    }
}

/// A collection's menu, the same everywhere (the card's ⋮ and the collection screen):
/// add, fill, screens, interval, blur and lock, order, merge, rename, delete.
struct CollectionMenu: View {
    @Environment(AppModel.self) private var model
    let collection: WallpaperCollection
    var onAddPhotos: () -> Void
    var onFill: () -> Void
    var onRename: () -> Void
    var onMerge: () -> Void
    var onDelete: () -> Void

    var body: some View {
        let c = collection
        Button(action: onAddPhotos) { Label("Add from device", systemImage: "photo.badge.plus") }
        Button(action: onFill) { Label("Fill from sources", systemImage: "arrow.down.circle") }
        Divider()
        Picker("Screens", selection: Binding(
            get: { c.rotationTarget },
            set: { t in model.modifyCollection(c.id) { $0.rotationTarget = t } }
        )) {
            Text("Home & Lock").tag(ScreenRotationTarget.BOTH)
            Text("Home only").tag(ScreenRotationTarget.HOME_ONLY)
            Text("Lock only").tag(ScreenRotationTarget.LOCK_ONLY)
        }
        Menu {
            Picker("Interval", selection: Binding(
                get: { c.rotationIntervalMinutes },
                set: { m in model.modifyCollection(c.id) { $0.rotationIntervalMinutes = m } }
            )) {
                Text("Global").tag(Int?.none)
                ForEach([60, 180, 360, 720, 1440], id: \.self) { m in
                    Text(m < 1440 ? "At most every \(m / 60) h" : "At most daily").tag(Int?.some(m))
                }
            }
        } label: {
            Label("Interval: \(c.rotationIntervalMinutes.map { $0 < 1440 ? "\($0 / 60) h" : "Daily" } ?? "Global")", systemImage: "timer")
        }
        Divider()
        if !model.settings.nsfwHidden {
            Toggle(isOn: Binding(get: { c.blurExempt }, set: { v in model.modifyCollection(c.id) { $0.blurExempt = v } })) {
                Label("Skip NSFW blur for this collection", systemImage: "eye")
            }
            Toggle(isOn: Binding(get: { c.isLocked }, set: { v in model.modifyCollection(c.id) { $0.isLocked = v } })) {
                Label("Lock collection", systemImage: "lock")
            }
            Divider()
        }
        Button { model.collectionsRepo.move(c.id, by: -1); model.reload() } label: { Label("Move earlier", systemImage: "arrow.left") }
        Button { model.collectionsRepo.move(c.id, by: 1); model.reload() } label: { Label("Move later", systemImage: "arrow.right") }
        Button(action: onMerge) { Label("Merge into…", systemImage: "arrow.triangle.merge") }
            .disabled(model.visibleCollections.count < 2)
        Button(action: onRename) { Label("Rename", systemImage: "pencil") }
        Divider()
        Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
    }
}
