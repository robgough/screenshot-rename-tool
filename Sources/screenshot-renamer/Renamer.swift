import Foundation
import FoundationModels
import ImageIO
import CoreGraphics

enum Renamer {
    /// Default folder = the system screenshot location on this machine.
    static let defaultDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/img.screenshots", isDirectory: true)

    /// Shared on-device model. Uses permissive content-transformation guardrails: this is a
    /// benign "describe my own screenshot" task, and the default guardrails over-trigger on
    /// ordinary content (error messages, forms, social posts, login screens).
    static let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)

    // MARK: - File selection

    /// A file macOS just created with its default screenshot name (i.e. not yet renamed by us).
    static func isDefaultScreenshotName(_ name: String) -> Bool {
        guard name.hasPrefix("Screenshot ") else { return false }
        let lower = name.lowercased()
        return lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg")
    }

    /// Un-renamed screenshots in `dir`, oldest first, skipping files modified within `minAge`
    /// seconds (they may still be flushing to disk).
    static func candidates(in dir: URL, minAge: TimeInterval = 2) -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let now = Date()
        return items
            .filter { isDefaultScreenshotName($0.lastPathComponent) }
            .filter { url in
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return now.timeIntervalSince(mod) >= minAge
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Naming pieces

    /// Sortable timestamp prefix "yyyyMMdd_HHmm" (no separators that read as confusing, no
    /// seconds). Prefers the capture time embedded in the macOS default filename
    /// ("Screenshot 2026-06-17 at 21.28.35.png"); falls back to the file's creation date.
    static func capturePrefix(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let parts = stem.components(separatedBy: " ")
        if parts.count >= 4, parts[0] == "Screenshot", parts[2] == "at" {
            let date = parts[1].split(separator: "-")  // [2026, 06, 17]
            let time = parts[3].split(separator: ".")  // [21, 28, 35]
            if date.count == 3, time.count >= 2 {
                let h = String(format: "%02d", Int(time[0]) ?? 0)
                let m = String(format: "%02d", Int(time[1]) ?? 0)
                return "\(date[0])\(date[1])\(date[2])_\(h)\(m)"
            }
        }
        let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmm"
        return f.string(from: date)
    }

    /// Filename-safe slug: lowercase ASCII letters/digits only, single spaces between words,
    /// trimmed to `maxLen` on a word boundary. Restricting to ASCII keeps names unambiguous
    /// (no Unicode homoglyphs/look-alikes) and valid on any filesystem.
    static func slug(_ s: String, maxLen: Int = 90) -> String {
        var out = ""
        var lastWasSpace = true   // also prevents a leading space
        for ch in s.lowercased() {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                out.append(ch); lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" "); lastWasSpace = true
            }
        }
        out = out.trimmingCharacters(in: .whitespaces)
        if out.count > maxLen {
            out = String(out.prefix(maxLen))
            if let lastSpace = out.lastIndex(of: " ") { out = String(out[..<lastSpace]) }
            out = out.trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    // MARK: - Image + model

    /// Load a downscaled CGImage (long side ≤ maxPixel). Returns nil if the file isn't a
    /// readable, complete image yet. Downscaling is faster and dodges a full-res Vision crop bug.
    static func loadDownscaled(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Ask the on-device model to describe the screenshot. A fresh session per call keeps latency
    /// flat (a reused session accumulates history and slows down). Returns a slug, or nil on error.
    static func describe(_ cg: CGImage) async -> String? {
        let session = LanguageModelSession(model: model)
        do {
            let resp = try await session.respond {
                """
                Describe this screenshot for use as a filename. Reply with ONLY the description: \
                5 to 12 words, all lowercase, plain words separated by single spaces, no \
                punctuation, no dates or times, no file extension. Start with the app or website \
                if you can identify it, then describe specifically what is shown — the main \
                subject, topic or content, including key names or labels visible on screen. \
                Be specific, not generic. Examples: \
                "stripe dashboard monthly payout summary for june", \
                "github pull request review comments on auth module", \
                "bbc news article about uk interest rate rise".
                """
                Attachment(cg)
            }
            let desc = slug(resp.content)
            // Empty only if the model returned no usable ASCII text; name it generically so the
            // file gets renamed once instead of being retried on every scan.
            return desc.isEmpty ? "screenshot" : desc
        } catch {
            warn("model error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Rename

    /// A destination that doesn't collide with an existing file.
    static func uniqueDestination(dir: URL, base: String, ext: String) -> URL {
        func make(_ b: String) -> URL {
            dir.appendingPathComponent(ext.isEmpty ? b : "\(b).\(ext)")
        }
        var candidate = make(base)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = make("\(base) \(n)")
            n += 1
        }
        return candidate
    }

    /// Process one screenshot. Returns the new filename (or, in dry-run, the proposed name).
    static func process(_ url: URL, dryRun: Bool, maxPixel: Int) async -> String? {
        guard let cg = loadDownscaled(url, maxPixel: maxPixel) else { return nil }
        guard let desc = await describe(cg) else {
            warn("no name for \(url.lastPathComponent) — leaving as-is")
            return nil
        }
        let dest = uniqueDestination(
            dir: url.deletingLastPathComponent(),
            base: "\(capturePrefix(for: url)) \(desc)",
            ext: url.pathExtension
        )
        if dryRun { return dest.lastPathComponent }
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            return dest.lastPathComponent
        } catch {
            warn("rename failed for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }
}

func warn(_ s: String) {
    FileHandle.standardError.write(Data(("  " + s + "\n").utf8))
}
