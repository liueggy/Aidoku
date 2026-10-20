import AidokuRunner
import Foundation
import ZIPFoundation

/// Export-only: all output lives in a unique temporary directory, never in Downloads.
enum NormalizedExport {
    struct Input: Sendable {
        let source: URL
        let name: String
        let metadata: String
        let failed: Bool
    }

    struct Result: Sendable {
        let directory: URL
        let file: URL
        let exported: Int
        let skipped: Int

        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }

    enum ExportError: LocalizedError {
        case noCompleteChapters(Int)
        case unsafeInput
        var errorDescription: String? {
            switch self {
                case .noCompleteChapters(let count):
                    String(format: NSLocalizedString("EXPORT_NONE_COMPLETE"), count)
                case .unsafeInput: NSLocalizedString("EXPORT_UNSAFE_INPUT")
            }
        }
    }

    static func component(_ value: String, limit: Int = 180) -> String {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:*?\"<>|"))
        let clean = value.precomposedStringWithCanonicalMapping.unicodeScalars.map {
            forbidden.contains($0) ? "_" : String($0)
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        var result = ""
        for character in clean {
            let next = String(character)
            guard result.utf8.count + next.utf8.count <= limit else { break }
            result += next
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if result.isEmpty { result = "Untitled" }
        let stem = result.split(separator: ".").first.map(String.init)?.uppercased() ?? ""
        let reserved = ["CON", "PRN", "AUX", "NUL"] + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] }
        if reserved.contains(stem) { result = "_" + result }
        return result
    }

    static func chapterName(manga: String, chapter: DownloadedChapterInfo, ordinal: Int) -> String {
        func number(_ value: Float) -> String { String(value).replacingOccurrences(of: #"\.0$"#, with: "", options: .regularExpression) }
        var parts = [component(manga, limit: 72)]
        if let volume = chapter.volumeNumber, volume.isFinite { parts.append("Vol. " + number(volume)) }
        if let chapter = chapter.chapterNumber, chapter.isFinite { parts.append("Ch. " + number(chapter)) }
        else { parts.append(String(format: "Chapter %03d", ordinal)) }
        if let title = chapter.title, !title.isEmpty { parts.append(title) }
        return component(parts.joined(separator: " - "))
    }

    static func unique(_ proposed: String, used: inout Set<String>) -> String {
        let base = component(proposed)
        var candidate = base
        var suffix = 2
        while !used.insert(candidate.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))).inserted {
            candidate = component(base, limit: 160) + " (\(suffix))"
            suffix += 1
        }
        return candidate
    }

    static func pageName(index: Int, count: Int, ext: String) -> String {
        String(format: "%0*d", max(3, String(count).count), index) + "." + ext
    }

    /// No archive-controlled path is ever used as an extraction destination.
    private static func safePath(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.contains("\\") && !path.contains(":")
            && !path.split(separator: "/").contains("..")
            && !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private struct File {
        let path: String
        let url: URL?
        let entry: Entry?
    }

    static func chapter(source: URL, destination: URL, metadata: String, scratch: URL) throws {
        try Task.checkCancellation()
        let manager = FileManager.default
        let archive: Archive?
        let files: [File]
        if source.pathExtension.lowercased() == "cbz" {
            archive = try Archive(url: source, accessMode: .read)
            guard let archive else { throw ExportError.unsafeInput }
            guard archive.allSatisfy({ $0.type != .symlink && safePath($0.path) }) else { throw ExportError.unsafeInput }
            files = archive.filter { $0.type == .file }.map { File(path: $0.path, url: nil, entry: $0) }
        } else {
            archive = nil
            files = try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]).compactMap { url in
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw ExportError.unsafeInput }
                guard values.isRegularFile == true else { return nil }
                return File(path: url.lastPathComponent, url: url, entry: nil)
            }
        }
        let visible = files.filter { !(($0.path as NSString).lastPathComponent.hasPrefix(".")) }
        let pages = visible.filter {
            let ext = ($0.path as NSString).pathExtension
            return LocalFileManager.allowedPageExtensions.contains(archive == nil ? ext : ext.lowercased())
                && !$0.path.hasSuffix("desc.txt")
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard !pages.isEmpty else { throw ExportError.unsafeInput }
        let output = try Archive(url: destination, accessMode: .create)
        let transfer = scratch.appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: transfer) }
        func write(_ file: File, as name: String) throws {
            try Task.checkCancellation()
            if let url = file.url {
                try output.addEntry(with: name, fileURL: url, compressionMethod: .none)
            } else if let archive, let entry = file.entry {
                // CRC checked by ZIPFoundation; only one page is spooled to disk at a time.
                try? manager.removeItem(at: transfer)
                _ = try archive.extract(entry, to: transfer, progress: nil)
                try Task.checkCancellation()
                try output.addEntry(with: name, fileURL: transfer, compressionMethod: .none)
            }
        }
        for (index, page) in pages.enumerated() {
            try write(page, as: pageName(index: index + 1, count: pages.count, ext: (page.path as NSString).pathExtension))
        }
        for file in visible where file.path.hasSuffix("desc.txt") {
            let name = (file.path as NSString).lastPathComponent
            if let first = name.split(separator: ".").first, let index = Int(first), (1...pages.count).contains(index) {
                try write(file, as: pageName(index: index, count: pages.count, ext: "desc.txt"))
            }
        }
        let xml = visible.first { ($0.path as NSString).lastPathComponent.lowercased() == "comicinfo.xml" }
        if let xml {
            // Keep even unknown XML fields byte-for-byte. Invalid metadata is not silently replaced.
            try write(xml, as: "ComicInfo.xml")
        } else {
            let metadataURL = scratch.appendingPathComponent(UUID().uuidString)
            defer { try? manager.removeItem(at: metadataURL) }
            try Data(metadata.utf8).write(to: metadataURL)
            try output.addEntry(with: "ComicInfo.xml", fileURL: metadataURL)
        }
        // Preserve non-page auxiliary files without polluting the root page sequence.
        var used = Set<String>()
        for file in files where !pages.contains(where: { $0.path == file.path })
            && !file.path.hasSuffix("desc.txt") && file.path != xml?.path {
            let ext = (file.path as NSString).pathExtension.lowercased()
            // Nested archives and hidden internal state are deliberately excluded.
            guard !["zip", "cbz", "cbr", "7z"].contains(ext),
                  !(file.path as NSString).lastPathComponent.hasPrefix(".") else { continue }
            let name = unique((file.path as NSString).lastPathComponent, used: &used)
            try write(file, as: "Extras/" + name)
        }
    }

    static func run(inputs: [Input], mangaTitle: String, bundle: Bool,
                    progress: @Sendable (Int, Int) -> Void) throws -> Result {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("Aidoku-export-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var success = false
        defer { if !success { try? manager.removeItem(at: directory) } }
        let folder = component(mangaTitle)
        let outputURL = directory.appendingPathComponent(folder + ".zip")
        let outer = bundle ? try Archive(url: outputURL, accessMode: .create) : nil
        var used = Set<String>()
        var completed = 0
        var skipped = 0
        var single: URL?
        for (index, input) in inputs.enumerated() {
            try Task.checkCancellation()
            let name = unique(input.name, used: &used) + ".cbz"
            let chapterURL = directory.appendingPathComponent(name)
            if input.failed { skipped += 1 }
            else {
                do {
                    try chapter(source: input.source, destination: chapterURL, metadata: input.metadata, scratch: directory)
                } catch is CancellationError { throw CancellationError() }
                catch {
                    try? manager.removeItem(at: chapterURL)
                    skipped += 1
                    progress(index + 1, inputs.count)
                    continue
                }
                try Task.checkCancellation()
                // Outer ZIP write failures abort the entire transaction.
                if let outer {
                    try outer.addEntry(with: folder + "/" + name, fileURL: chapterURL, compressionMethod: .none)
                    try manager.removeItem(at: chapterURL)
                } else { single = chapterURL }
                completed += 1
            }
            progress(index + 1, inputs.count)
        }
        guard completed > 0 else { throw ExportError.noCompleteChapters(skipped) }
        try Task.checkCancellation()
        success = true
        return Result(directory: directory, file: single ?? outputURL, exported: completed, skipped: skipped)
    }
}
