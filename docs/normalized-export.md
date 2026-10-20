# Normalized export — original files

## Entry points

Settings → Downloads → select a manga → top-right menu → **Export all downloaded chapters (ZIP)**.
Long-press a completed chapter in that same list → **Export normalized CBZ (original files)**.
Single chapter produces one CBZ. All chapters produces one ZIP with a human-readable manga folder containing CBZs (even if only one chapter completes). Existing share actions elsewhere are unchanged. Multi-selection UI is not offered.

## Guarantees and policy

- Export-only. The download cache, database, failed staging directories, and reader material settings are never renamed or written. Original means the bytes already saved by the downloader; source-required download-time page interception cannot be undone.
- Images are copied, not decoded or reencoded. Extensions and animated formats remain intact. Text/Markdown pages remain text. Root pages use natural reader ordering (`localizedStandardCompare`), not lexical sorting, then names `001.ext` through a dynamically padded maximum (`0001` for 1000+). Raw downloads use the reader's top-level selection; CBZs use its full-path selection and case-insensitive extension recognition.
- Names contain bounded manga title, available fractional volume/chapter, and chapter title. Missing chapter numbers use a stable chapter-ID-sorted catalog ordinal (not current ascending/descending UI order). Unicode graphemes are never split. Components are NFC normalized and byte-bounded; path separators, control characters, reserved punctuation, Windows device names, leading/trailing dots/spaces are handled. Case-insensitive collisions get deterministic numeric suffixes.
- Existing ComicInfo.xml is preserved byte-for-byte, including unknown fields (even malformed existing XML is retained for recovery). Missing ComicInfo.xml is generated with the existing `ComicInfo.load(manga:chapter:)` helper. Available metadata is limited to downloaded manga/chapter models. No XML fields are merged into existing documents. Existing ComicInfo volume schema/helper is integer-valued; filename volume remains fractional where the model has it.
- Page descriptions are mapped by their original one-based numeric association and renamed to match page padding. Visible non-page auxiliary files are flattened into `Extras/` with collision-safe names. Hidden internal state, nested archives, and raw subdirectories are excluded. Nested CBZ image folders are flattened into the normalized page sequence, not nested archives. Duplicate ComicInfo files other than the selected one are auxiliary files.
- ZIP entries with traversal, absolute paths, control characters, colon/backslash paths or symlinks reject that chapter. Raw symlinks also reject it. CBZ extraction uses random scratch filenames, never archive-provided destinations; ZIPFoundation calculates CRC and export explicitly compares it with each entry's stored checksum.
- Failed downloads, missing/unreadable/empty/unsafe chapters are skipped. Exact exported/skipped counts require confirmation before sharing partial output. Zero completed chapters is an error. Downloads not present in the management list (e.g. currently queued tasks) are not included. An old cache with unmarked missing pages cannot be diagnosed without an expected-page manifest.
- Streaming ZIPFoundation file APIs and one-page disk spooling avoid whole-archive memory buffers. No recompression is applied. Temporary disk space includes the final bundle plus approximately one chapter and one spooled page. Cancellation is checked between pages/chapters and at every ZIPFoundation read/write chunk (including the outer bundle). Outer ZIP write failure aborts the transaction. Temporary output is removed on failure/cancel or share-sheet dismissal, never before the share sheet has finished using it. iOS process termination can leave temporary files for OS reclamation.

## Tests

`normalized-export-tests.yml` is **manual dispatch only**, using the existing `xcode-27` runner and an available iPhone simulator. Only NormalizedExportTests, ComicInfoTests and ArchiveTests execute; the AidokuTests host application and its package dependencies must compile normally. Tests cover fractional numbers, missing numbers, sanitization, Unicode bounds, collisions, 1001 pages, original-byte SHA256 equality for raw/CBZ round trips, XML preservation/generation, text and description files, nested archive exclusion, skip counts, traversal/symlink rejection, and cancellation.

On forks where a new workflow is not registered until it reaches the default branch, dispatch the already-registered `paper-material-tests.yml` on this feature branch with input `suite=normalized-export`. Its default remains `paper`, preserving both paper regression suites. No default-branch change is required.

The existing nightly workflow builds unsigned IPAs on pushes; this feature adds no automatic test execution. Paper material implementation and diagnostic assets are inherited unchanged.

## Manual regression checklist

- Export raw-directory and compressed downloads, compare page hashes after unzipping.
- Export a 1000+ page chapter and check lexical image order.
- Export manga with fractional chapter number, long CJK/emoji title, punctuation and colliding chapter names.
- Export failed/incomplete downloads mixed with complete ones; verify exact warning counts and no failed staging content.
- Export text pages and description sidecars; reimport into local source and verify reading order.
- Cancel during a large chapter; verify no share appears and sources remain intact.
- Dismiss share sheet with cancel, Save to Files, and third-party activity; verify output remains accessible to the activity and temporary files are removed afterwards.
- iPad popover/sheet presentation and en/zh-Hans/zh-Hant labels.
- Reader paper materials, preview diagnostics, downloads, deletion and original share routes outside Downloads remain unchanged.
