import CoreGraphics
import Foundation

/// A set of near-identical images: `keep` is the best copy, `duplicates` can be removed.
public struct DuplicateGroup: Sendable, Hashable {
    public let keep: URL
    public let duplicates: [URL]
}

public enum DuplicateFinder {
    /// Finds near-identical images with a 64-bit difference hash, which survives resizing,
    /// recompression and small colour shifts (the same art saved from two sites). Images whose
    /// hashes differ in at most `maxDistance` bits are grouped; each group keeps its
    /// highest-resolution copy.
    public static func groups(in files: [URL], maxDistance: Int = 6) -> [DuplicateGroup] {
        let hashed: [(URL, UInt64, Int)] = files.compactMap { f in
            guard let h = fingerprint(f) else { return nil }
            let size = ImageLoader.pixelSize(f).map { Int($0.width * $0.height) } ?? 0
            return (f, h, size)
        }
        var parent = Array(hashed.indices)
        func find(_ i: Int) -> Int {
            var x = i
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        for i in hashed.indices {
            for j in (i + 1)..<hashed.count where (hashed[i].1 ^ hashed[j].1).nonzeroBitCount <= maxDistance {
                parent[find(j)] = find(i)
            }
        }
        return Dictionary(grouping: hashed.indices, by: find).values
            .filter { $0.count > 1 }
            .map { members in
                let sorted = members.map { hashed[$0] }.sorted { a, b in
                    a.2 != b.2 ? a.2 > b.2 : fileSize(a.0) > fileSize(b.0)
                }
                return DuplicateGroup(keep: sorted[0].0, duplicates: sorted.dropFirst().map(\.0))
            }
    }

    static func fingerprint(_ url: URL) -> UInt64? {
        guard let img = ImageLoader.thumbnail(url, maxPixel: 64) else { return nil }
        let w = 9, h = 8
        var px = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var hash: UInt64 = 0
        var bit: UInt64 = 0
        for y in 0..<h {
            for x in 0..<(w - 1) {
                if px[y * w + x] > px[y * w + x + 1] { hash |= 1 << bit }
                bit += 1
            }
        }
        // Near-flat images all hash to almost the same value and would be grouped though they
        // differ; leave them out.
        let set = hash.nonzeroBitCount
        return set <= 2 || set >= 62 ? nil : hash
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
