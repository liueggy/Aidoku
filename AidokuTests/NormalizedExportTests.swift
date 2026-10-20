import CryptoKit
import Foundation
import Testing
import ZIPFoundation
@testable import Aidoku

@Suite struct NormalizedExportTests {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func contents(_ archive: Archive, _ name: String) throws -> Data {
        let entry = try #require(archive[name])
        var bytes = Data()
        _ = try archive.extract(entry) { bytes.append($0) }
        return bytes
    }

    @Test func filenames() {
        #expect(NormalizedExport.component("../a/b\\c:*?<>|\n") == "_a_b_c_______")
        #expect(NormalizedExport.component("CON") == "_CON")
        #expect(NormalizedExport.component("... ") == "Untitled")
        let long = NormalizedExport.component(String(repeating: "漫画👩🏽‍🚀", count: 100))
        #expect(long.utf8.count <= 180)
        #expect(!long.contains("�"))
        let info = DownloadedChapterInfo(chapterId: "x", title: "Extra", chapterNumber: 12.125, volumeNumber: 2.5, size: 0)
        #expect(NormalizedExport.chapterName(manga: "Series", chapter: info, ordinal: 1) == "Series - Vol. 2.5 - Ch. 12.125 - Extra")
        #expect(NormalizedExport.chapterName(manga: "Series", chapter: .init(chapterId: "unknown", size: 0), ordinal: 42) == "Series - Chapter 042")
    }

    @Test func collisionsAndPageWidth() {
        var used = Set<String>()
        #expect(NormalizedExport.unique("Title", used: &used) == "Title")
        #expect(NormalizedExport.unique("TITLE", used: &used) == "TITLE (2)")
        #expect(NormalizedExport.unique("Title (2)", used: &used) == "Title (2) (2)")
        #expect(NormalizedExport.pageName(index: 1, count: 1001, ext: "gif") == "0001.gif")
        #expect(NormalizedExport.pageName(index: 1000, count: 1001, ext: "gif") == "1000.gif")
        #expect(NormalizedExport.pageName(index: 1, count: 2, ext: "webp") == "001.webp")
    }

    @Test func rawAndCBZPreserveBytesAndXML() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("raw")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        // Binary fixtures deliberately not decoded as images, including GIF/WebP and text.
        let fixtures: [(String, Data)] = [
            ("1.gif", Data([71, 73, 70, 0, 255, 1])),
            ("2.webp", Data([82, 73, 70, 70, 255, 0])),
            ("10.png", Data([137, 80, 78, 71, 0, 254])),
            ("11.md", Data("# Text page 漫画".utf8))
        ]
        let xml = Data("<?xml version=\"1.0\"?><ComicInfo><Series>A &amp; B</Series><Custom>Keep</Custom></ComicInfo>".utf8)
        for (name, data) in fixtures { try data.write(to: source.appendingPathComponent(name)) }
        try xml.write(to: source.appendingPathComponent("ComicInfo.xml"))
        try Data("description".utf8).write(to: source.appendingPathComponent("2.desc.txt"))
        try Data("auxiliary".utf8).write(to: source.appendingPathComponent("credits.json"))
        try Data("do not nest".utf8).write(to: source.appendingPathComponent("nested.cbz"))
        let cbz = root.appendingPathComponent("source.cbz")
        let archive = try Archive(url: cbz, accessMode: .create)
        for url in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            try archive.addEntry(with: url.lastPathComponent, fileURL: url)
        }
        for (index, input) in [source, cbz].enumerated() {
            let output = root.appendingPathComponent("out\(index).cbz")
            try NormalizedExport.chapter(source: input, destination: output, metadata: "not used", scratch: root)
            let exported = try Archive(url: output, accessMode: .read)
            for (position, fixture) in fixtures.enumerated() {
                let ext = (fixture.0 as NSString).pathExtension
                let actual = try contents(exported, NormalizedExport.pageName(index: position + 1, count: fixtures.count, ext: ext))
                #expect(SHA256.hash(data: actual) == SHA256.hash(data: fixture.1))
                #expect(try Data(contentsOf: source.appendingPathComponent(fixture.0)) == fixture.1)
            }
            #expect(try contents(exported, "ComicInfo.xml") == xml)
            #expect(try contents(exported, "002.desc.txt") == Data("description".utf8))
            #expect(try contents(exported, "Extras/credits.json") == Data("auxiliary".utf8))
            #expect(exported["Extras/nested.cbz"] == nil)
        }
    }

    @Test func bundleSkipsFailedAndFillsMetadata() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("1.jpg"))
        let metadata = ComicInfo(series: "A & B", number: "1.5").export()
        let inputs = [
            NormalizedExport.Input(source: root, name: "Chapter", metadata: metadata, failed: false),
            NormalizedExport.Input(source: root, name: "chapter", metadata: metadata, failed: false),
            NormalizedExport.Input(source: root, name: "Failed", metadata: metadata, failed: true),
            NormalizedExport.Input(source: root.appendingPathComponent("missing"), name: "Missing", metadata: metadata, failed: false)
        ]
        let result = try NormalizedExport.run(inputs: inputs, mangaTitle: "漫画", bundle: true) { _, _ in }
        defer { result.cleanup() }
        #expect(result.exported == 2)
        #expect(result.skipped == 2)
        let outer = try Archive(url: result.file, accessMode: .read)
        #expect(outer.map(\.path).sorted() == ["漫画/Chapter.cbz", "漫画/chapter (2).cbz"].sorted())
        let chapter = root.appendingPathComponent("check.cbz")
        try contents(outer, "漫画/Chapter.cbz").write(to: chapter)
        let inner = try Archive(url: chapter, accessMode: .read)
        let xml = try #require(String(data: contents(inner, "ComicInfo.xml"), encoding: .utf8))
        #expect(ComicInfo.load(xmlString: xml)?.series == "A & B")
        #expect(ComicInfo.load(xmlString: xml)?.number == "1.5")
    }

    @Test func rejectsTraversalAndSymlinks() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("bad.cbz")
        let zip = try Archive(url: input, accessMode: .create)
        let data = Data([1])
        try zip.addEntry(with: "../escape.jpg", type: .file, uncompressedSize: Int64(data.count)) { _, _ in data }
        #expect(throws: (any Error).self) {
            try NormalizedExport.chapter(source: input, destination: root.appendingPathComponent("out.cbz"), metadata: "", scratch: root)
        }
        let raw = root.appendingPathComponent("raw")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: raw.appendingPathComponent("1.jpg"), withDestinationURL: input)
        #expect(throws: (any Error).self) {
            try NormalizedExport.chapter(source: raw, destination: root.appendingPathComponent("link.cbz"), metadata: "", scratch: root)
        }
    }

    @Test func rejectsSourceSymlinkAndCorruptedCRC() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("source.cbz")
        do {
            let zip = try Archive(url: input, accessMode: .create)
            let bytes = Data([11, 22, 33, 44])
            try zip.addEntry(with: "1.jpg", type: .file, uncompressedSize: Int64(bytes.count)) { _, _ in bytes }
        }
        let link = root.appendingPathComponent("link.cbz")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: input)
        #expect(throws: (any Error).self) {
            try NormalizedExport.chapter(source: link, destination: root.appendingPathComponent("link-out.cbz"), metadata: "", scratch: root)
        }
        var damaged = try Data(contentsOf: input)
        // Local file header: 30 fixed bytes followed by filename and extra field.
        let nameLength = Int(damaged[26]) + Int(damaged[27]) * 256
        let extraLength = Int(damaged[28]) + Int(damaged[29]) * 256
        damaged[30 + nameLength + extraLength] ^= 0xff
        try damaged.write(to: input)
        #expect(throws: (any Error).self) {
            try NormalizedExport.chapter(source: input, destination: root.appendingPathComponent("bad-out.cbz"), metadata: "", scratch: root)
        }
    }

    @Test func hugeChapterOrder() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let raw = root.appendingPathComponent("raw")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        for index in 1...1001 { try Data("\(index)".utf8).write(to: raw.appendingPathComponent("\(index).jpg")) }
        let out = root.appendingPathComponent("out.cbz")
        try NormalizedExport.chapter(source: raw, destination: out, metadata: ComicInfo().export(), scratch: root)
        let zip = try Archive(url: out, accessMode: .read)
        #expect(try contents(zip, "0002.jpg") == Data("2".utf8))
        #expect(try contents(zip, "1000.jpg") == Data("1000".utf8))
        #expect(zip.map(\.path).filter { $0.hasSuffix("jpg") }.sorted().first == "0001.jpg")
    }

    @Test func cancellationRemovesTemporaryOutput() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: root.appendingPathComponent("1.jpg"))
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try NormalizedExport.run(inputs: [.init(source: root, name: "Chapter", metadata: "", failed: false)], mangaTitle: "Test", bundle: false) { _, _ in }
        }
        do {
            let result = try await task.value
            result.cleanup()
            Issue.record("Cancelled export unexpectedly succeeded")
        } catch { #expect(error is CancellationError) }
        #expect(try Data(contentsOf: root.appendingPathComponent("1.jpg")) == Data([1]))
    }
}
