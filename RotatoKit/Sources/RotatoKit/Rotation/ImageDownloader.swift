import Foundation

/// Downloads full images, rejecting HTML error pages (hotlink blocks, Cloudflare challenges)
/// that would otherwise be saved as a broken .jpg.
public enum ImageDownloader {
    public struct Result: Sendable {
        public let data: Data
        public let ext: String
    }

    public static func download(_ url: String, fallback: String = "", authHeader: String? = nil) async -> Result? {
        if let r = await fetch(url, authHeader: authHeader) { return r }
        if !fallback.isBlank, fallback != url { return await fetch(fallback, authHeader: authHeader) }
        return nil
    }

    private static func fetch(_ url: String, authHeader: String?) async -> Result? {
        guard !url.isBlank else { return nil }
        var headers = HTTP.imageHeaders(for: url)
        if let authHeader { headers["Authorization"] = authHeader }
        guard let (data, resp) = await HTTP.data(url, headers: headers) else { return nil }
        let contentType = resp.value(forHTTPHeaderField: "Content-Type")?.lowercased()
        if contentType?.hasPrefix("text/") == true { return nil }
        if let first = data.first(where: { $0 != 0x20 && $0 != 0x0A && $0 != 0x0D }), first == UInt8(ascii: "<") { return nil }
        let ext = extFromContentType(contentType) ?? extFromURL(url) ?? extFromBytes(data) ?? "jpg"
        return Result(data: data, ext: ext)
    }

    static func extFromContentType(_ ct: String?) -> String? {
        guard let ct else { return nil }
        if ct.contains("jpeg") || ct.contains("jpg") { return "jpg" }
        if ct.contains("png") { return "png" }
        if ct.contains("webp") { return "webp" }
        if ct.contains("gif") { return "gif" }
        if ct.contains("heic") { return "heic" }
        if ct.contains("mp4") { return "mp4" }
        if ct.contains("webm") { return "webm" }
        return nil
    }

    static func extFromURL(_ url: String) -> String? {
        let path = URL(string: url)?.path ?? url
        let ext = (path as NSString).pathExtension.lowercased()
        guard (1...5).contains(ext.count), ext.allSatisfy(\.isLetter) || ext == "mp4" else { return nil }
        return ext == "jpeg" ? "jpg" : ext
    }

    static func extFromBytes(_ d: Data) -> String? {
        guard d.count >= 12 else { return nil }
        let b = [UInt8](d.prefix(12))
        if b[0] == 0xFF, b[1] == 0xD8 { return "jpg" }
        if b[0] == 0x89, b[1] == 0x50 { return "png" }
        if b[0] == 0x47, b[1] == 0x49 { return "gif" }
        if b[0] == 0x52, b[1] == 0x49, b[8] == 0x57, b[9] == 0x45 { return "webp" }
        if b[4] == 0x66, b[5] == 0x74, b[6] == 0x79, b[7] == 0x70 { return "heic" }
        return nil
    }

    /// True when the file starts with known image magic bytes.
    public static func isValidImage(at url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 12), d.count >= 4 else { return false }
        return extFromBytes(d.count >= 12 ? d : d + Data(repeating: 0, count: 12 - d.count)) != nil
    }
}
