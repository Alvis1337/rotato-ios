import CoreGraphics
import Foundation
@testable import RotatoKit

// Checks for the platform-neutral core, runnable without Xcode:
//   swift run RotatoChecks            (offline checks)
//   swift run RotatoChecks --network  (also fetches from the keyless sources)

var failures = 0
func check(_ cond: @autoclosure () -> Bool, _ what: String, file: String = #file, line: Int = #line) {
    if cond() { print("  ok   \(what)") } else { failures += 1; print("  FAIL \(what) (line \(line))") }
}

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rotato-checks-\(UUID().uuidString)")
let db = RotatoDatabase(directory: tmp.appendingPathComponent("Data"))
let poolDir = tmp.appendingPathComponent("Pool")
try FileManager.default.createDirectory(at: poolDir, withIntermediateDirectories: true)

print("Query normalisation")
check(normalizeBooruQuery("  Fate/Zero ") == "fate/zero", "booru title keeps punctuation")
check(normalizeBooruQuery("-Steins;Gate  0") == "steins;gate_0", "leading exclude dropped, spaces → _")
check(normalizeUserQuery("Hatsune_Miku_  -Rating:Explicit ~a") == "hatsune_miku -rating:explicit ~a", "user query tokens")
check(normalizeUserQuery(" - ~ ") == "", "bare operators dropped")
check(normalizeTag(" Hatsune Miku ") == "hatsune_miku", "tag normalisation")

print("Media and filters")
check(MediaType.isVideoURL("https://x/y.MP4?x=1"), "mp4 with query is video")
check(MediaType.isVideoURL("https://v.redd.it/abc"), "v.redd.it is video")
check(!MediaType.isVideoURL("https://x/y.jpg"), "jpg not video")
var f = DiscoverFilters(minResolution: .FHD, aspectRatio: .PORTRAIT)
check(!f.matches(width: 1080, height: 1920), "FHD minimum is landscape-sized, as on Android")
check(DiscoverFilters(aspectRatio: .PORTRAIT).matches(width: 1080, height: 1920), "portrait ratio matches")
check(!f.matches(width: 1920, height: 1080), "landscape rejected for portrait")
check(f.matches(width: 0, height: 0), "unknown dimensions pass")
f = DiscoverFilters(minResolution: .MY_PHONE, aspectRatio: .MY_PHONE, phoneScreenWidth: 1179, phoneScreenHeight: 2556)
check(f.matches(width: 1179, height: 2556), "my phone exact")
check(!f.matches(width: 900, height: 1951), "my phone too small")

print("Engine query building")
let gq = GelbooruEngine().buildTagQuery("a b", nsfw: false, extras: ["ratingTag": "safe"], filters: DiscoverFilters(matchAny: true))
check(gq == "( a ~ b ) rating:safe", "gelbooru OR syntax: \(gq)")
let dq = DanbooruEngine().buildTagQuery("a b", nsfw: true, isPremium: false, exclude: ["1"], filters: DiscoverFilters())
check(dq == "a -rating:g", "danbooru free = one tag: \(dq)")
let mq = MoebooruEngine().buildTagQuery("", nsfw: false, filters: DiscoverFilters())
check(mq == "rating:s order:random", "moebooru default: \(mq)")

print("Bundled plugins")
check(PluginCatalog.bundled.count == 9, "9 bundled manifests (\(PluginCatalog.bundled.count))")
let gelbooru = PluginCatalog.bundled.first { $0.id == "GELBOORU" }
check(gelbooru?.maxTagCount == 2, "gelbooru max tags 2")
check(gelbooru?.requiresCredentials == true, "gelbooru needs credentials")
check(PluginCatalog.bundled.first { $0.id == "RULE34" }?.adultOnly == true, "rule34 adult only")
if let g = gelbooru {
    let roundTrip = try JSONDecoder().decode(PluginManifest.self, from: JSONEncoder().encode(g))
    check(roundTrip == g, "manifest JSON round trip")
}

print("Lenient decoding")
let androidSource = #"[{"type":"SAFEBOORU","enabled":true,"nsfwEnabled":null},{"bad":1},{"pluginId":"REDDIT","instanceId":"Animewallpaper","nsfwEnabled":"false"}]"#
let srcs = LossyDecoding.decodeArray([SourceConfig].self, from: Data(androidSource.utf8)) ?? []
check(srcs.count == 2, "bad source row dropped, old 'type' key read")
check(srcs.last?.nsfwEnabled == false, "string nsfwEnabled read")
let partialSettings = try JSONDecoder().decode(RotatoSettings.self, from: Data(#"{"nsfwMode":true,"filters":{"minResolution":"NOPE"}}"#.utf8))
check(partialSettings.nsfwMode && partialSettings.shuffleMode && partialSettings.filters.minResolution == .ANY, "settings defaults fill gaps")

print("Collections")
let repo = CollectionsRepository(db: db)
let fav = repo.create(name: "Favorites")!
check(repo.create(name: "favorites") == nil, "duplicate name rejected")
let wp = Wallpaper(id: "1", source: "safebooru", thumbUrl: "t", sampleUrl: "s", fullUrl: "https://x/1.jpg", resolution: "100x200", pageUrl: "", tags: ["blue_sky", "Cat Ears"])
check(repo.add(wp, to: fav.id), "add")
check(!repo.add(wp, to: fav.id), "no duplicate add")
let other = repo.create(name: "Other")!
check(repo.copy(entryIds: Set(repo.entries.map(\.id)), to: other.id) == 1, "copy to other")
check(repo.merge(other.id, into: fav.id) == 0, "merge skips duplicates")
check(repo.collections.count == 1, "merged collection deleted")
let smart = repo.create(name: "Ears", smartRule: SmartRule(requireAll: ["cat_ears"]))!
check(repo.refreshSmartCollections() == 1, "smart collection picks up match")
check(repo.entries(in: smart.id).count == 1, "smart entry stored")
check(repo.rename(smart.id, to: "Favorites") == false, "rename to taken name rejected")
repo.move(smart.id, by: -1)
check(repo.collections.first?.id == smart.id, "move collection")

print("Rotation")
let pool = RotationPool(directory: poolDir, db: db)
func makeImage(_ name: String, gray: CGFloat) throws -> URL {
    let ctx = CGContext(data: nil, width: 60, height: 120, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 120))
    let url = poolDir.appendingPathComponent(name)
    try WallpaperRenderer.writeJPEG(ctx.makeImage()!, to: url)
    return url
}
let dark = try makeImage("dark.jpg", gray: 0.05)
_ = try makeImage("light.jpg", gray: 0.95)
_ = try makeImage("mid.jpg", gray: 0.6)
check(pool.files().count == 3, "pool lists images")
check(ImageDownloader.isValidImage(at: dark), "jpeg magic bytes valid")
let engine = RotationEngine(db: db, pool: pool)
var seen = Set<String>()
for _ in 0..<12 { seen.insert(try engine.next(for: .home).file.lastPathComponent) }
check(seen.count >= 2, "shuffle visits several images")
let h = db.read(DataFiles.state).history
check(zip(h, h.dropFirst()).allSatisfy { $0.poolFile != $1.poolFile }, "never the same twice in a row")
engine.queue(dark, screens: [.home, .lock])
let qh = try engine.next(for: .home).file, ql = try engine.next(for: .lock).file
check(qh == dark, "queued wallpaper shown on home")
check(ql == dark, "queued wallpaper shown on lock")
check(db.read(DataFiles.state).queuedNext.isEmpty, "queue consumed")
db.update(DataFiles.state) { $0.nsfwFileNames = ["light.jpg", "mid.jpg"] }
db.update(DataFiles.settings) { $0.nsfwHomeOnly = true }
for _ in 0..<5 { let f = try engine.next(for: .lock).file; check(f.lastPathComponent == "dark.jpg", "nsfw kept off lock screen") }
db.update(DataFiles.settings) { $0.nsfwHomeOnly = false; $0.shuffleMode = false }
let seq = try (0..<3).map { _ in try engine.next(for: .home).file.lastPathComponent }
check(Set(seq).count == 3, "sequential walks the pool: \(seq)")
db.update(DataFiles.settings) { $0.autoPause = AutoPauseSettings(nightEnabled: true, nightStartHour: 0, nightEndHour: 0) }
db.update(DataFiles.settings) { $0.autoPause = AutoPauseSettings(nightEnabled: true, nightStartHour: 23, nightEndHour: 22) }
let before = db.read(DataFiles.state).current(for: .home)?.poolFile
let paused = try engine.next(for: .home, automatic: true, now: Calendar.current.date(bySettingHour: 23, minute: 30, second: 0, of: Date())!)
check(paused.paused && paused.file.lastPathComponent == before, "night auto-pause keeps current")
let looks = ImageAnalysis.brightness(of: pool.files(), db: db)
check((looks["dark.jpg"] ?? 1) < ImageAnalysis.darkThreshold && (looks["light.jpg"] ?? 0) > 0.8, "brightness analysis")

print("Rendering")
var s = RotatoSettings()
s.filters.phoneScreenWidth = 300; s.filters.phoneScreenHeight = 650
s.wallpaperEffects = WallpaperEffects(blur: 1, dimPercent: 30)
let rendered = try WallpaperRenderer.render(dark, for: .home, settings: s)
check(ImageLoader.pixelSize(rendered) == CGSize(width: 300, height: 650), "rendered to screen size")
s.wallpaperFit = .FIT
let fitted = try WallpaperRenderer.render(dark, for: .lock, settings: s)
check(ImageLoader.pixelSize(fitted) == CGSize(width: 300, height: 650), "fit render size")

print("Discover ordering")
let feedForOrder = DiscoverFeed(db: db)
func post(_ id: String, _ tags: [String]) -> Wallpaper {
    Wallpaper(id: id, source: "x", thumbUrl: "", sampleUrl: "", fullUrl: "https://x/\(id).jpg", resolution: "", pageUrl: "", tags: tags)
}
let ordered = await feedForOrder.order([post("1", ["meh"]), post("2", ["plain"]), post("3", ["love_it"])],
                                       boost: ["love_it"], demote: ["meh"], forYou: false, weights: [:])
check(ordered.map(\.id) == ["3", "2", "1"], "tier boost first, dislikes last")

if CommandLine.arguments.contains("--network") {
    print("Live sources")
    for id in ["SAFEBOORU", "KONACHAN", "YANDERE", "ZEROCHAN", "WALLHAVEN", "DANBOORU", "REDDIT"] {
        guard let m = PluginCatalog.bundled.first(where: { $0.id == id }) else { continue }
        let source = SourceConfig(pluginId: id, instanceId: id == "REDDIT" ? "Animewallpaper" : "", enabled: true)
        let page = await PluginExecutor.fetchPage(FetchRequest(manifest: m, source: source, query: "", nsfw: false, limit: 10))
        let good = page.filter { $0.fullUrl.hasPrefix("http") && !$0.id.isEmpty }
        if id == "REDDIT" && good.isEmpty {
            // Reddit refuses unauthenticated JSON from some networks (HTTP 403); not a parsing failure.
            print("  note REDDIT: no posts (Reddit may be blocking this network)")
            continue
        }
        check(!good.isEmpty, "\(id): \(page.count) posts, e.g. \(good.first?.fullUrl ?? "-")")
        if id == "SAFEBOORU", let first = good.first {
            let dl = await ImageDownloader.download(first.fullUrl)
            check(dl != nil && ImageDownloader.extFromBytes(dl!.data) != nil, "download real image (\(dl?.ext ?? "-"), \(dl?.data.count ?? 0) bytes)")
            let tagged = await PluginExecutor.fetchPage(FetchRequest(manifest: m, source: source, query: "blue_sky", nsfw: false, limit: 5))
            check(!tagged.isEmpty && tagged.allSatisfy { $0.tags.contains("blue_sky") }, "tag search returns tagged posts")
        }
    }
    print("Live Discover feed")
    let feedDb = RotatoDatabase(directory: tmp.appendingPathComponent("FeedData"))
    let cat = PluginCatalog(db: feedDb)
    cat.installAllBundled()
    SourcesRepository(db: feedDb).setPluginEnabled("SAFEBOORU", true)
    SourcesRepository(db: feedDb).setPluginEnabled("KONACHAN", true)
    feedDb.update(DataFiles.settings) { $0.discoverBatchSize = 10 }
    let live = DiscoverFeed(db: feedDb)
    let b1 = await live.next(initial: true)
    let b2 = await live.next(initial: false)
    let all = b1.items + b2.items
    check(b1.items.count == 20, "initial batch is double size (\(b1.items.count))")
    check(Set(all.map(\.key)).count == all.count, "no duplicates across batches (\(all.count))")
    check(Set(all.map(\.source)).count == 2, "sources interleave: \(Set(all.map(\.source)))")
    check(feedDb.read(DataFiles.state).seenKeys.count == all.count, "seen keys recorded")
    await live.reset(query: "blue_sky")
    let searched = await live.next(initial: true)
    check(!searched.items.isEmpty && searched.items.allSatisfy { $0.tags.contains("blue_sky") }, "search feed (\(searched.items.count))")
    feedDb.update(DataFiles.settings) { $0.nsfwMode = true }
    await live.reset(query: "")
    let nsfwBatch = await live.next(initial: true)
    check(nsfwBatch.noResults == .noSources, "safe-only sources sit out in NSFW mode")

    let store = try? await PluginCatalog(db: db).fetchStore(PluginCatalog.storeIndexURL)
    check((store?.entries.count ?? 0) > 0, "plugin store index (\(store?.entries.count ?? 0) entries)")
}

try? FileManager.default.removeItem(at: tmp)
print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
