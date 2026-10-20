import SwiftUI

@MainActor
final class NormalizedExportController: ObservableObject {
    @Published var running = false
    @Published var completed = 0
    @Published var total = 0
    @Published var message: String?
    @Published var showMessage = false
    @Published var showShare = false
    private(set) var result: NormalizedExport.Result?
    private var worker: Task<NormalizedExport.Result, Error>?

    func start(manga: DownloadedMangaInfo, chapters: [DownloadedChapterInfo], bundle: Bool,
               catalog: [DownloadedChapterInfo]? = nil) {
        guard !running else { return }
        cleanup()
        let sorted = chapters.sorted { $0.chapterId < $1.chapterId }
        let ids = (catalog ?? chapters).map(\.chapterId).sorted()
        let inputs = sorted.map { chapter in
            let ordinal = (ids.firstIndex(of: chapter.chapterId) ?? 0) + 1
            return
            NormalizedExport.Input(
                source: DownloadManager.shared.normalizedExportSource(for: .init(
                    sourceKey: manga.sourceId, mangaKey: manga.mangaId, chapterKey: chapter.chapterId
                )),
                name: NormalizedExport.chapterName(manga: manga.displayTitle, chapter: chapter, ordinal: ordinal),
                metadata: ComicInfo.load(manga: manga.toManga(), chapter: chapter.toChapter()).export(),
                failed: chapter.failed
            )
        }
        running = true
        completed = 0
        total = inputs.count
        let title = manga.displayTitle
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            try NormalizedExport.run(inputs: inputs, mangaTitle: title, bundle: bundle) { done, count in
                Task { @MainActor [weak self] in
                    self?.completed = done
                    self?.total = count
                }
            }
        }
        worker = task
        Task {
            do {
                let value = try await task.value
                result = value
                running = false
                worker = nil
                if value.skipped > 0 {
                    message = String(format: NSLocalizedString("EXPORT_SKIPPED"), value.exported, value.skipped)
                    showMessage = true
                } else { showShare = true }
            } catch {
                running = false
                worker = nil
                if !(error is CancellationError) {
                    message = error.localizedDescription
                    showMessage = true
                }
            }
        }
    }

    func cancel() { worker?.cancel() }
    func cleanup() {
        result?.cleanup()
        result = nil
    }
}

struct NormalizedExportShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
