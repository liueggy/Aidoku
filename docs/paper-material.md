# Reader paper material

## Enable

Settings → Reader → Background Color → Texture, then Paper Material. The same picker is available from in-reader settings. Defaults remain unchanged: the background must be explicitly selected, and material scope defaults to background only. Background opacity and page strength are independent. Page strength defaults to 35%; preserve colored artwork defaults on. The preview is a labeled generated sample, not the current manga (the global settings screen has no current page).

Seven ambientCG CC0 styles and their existing light/dark asset variants are preserved. See `Aidoku/App/Resources/ReaderTextureAttribution.json` for provenance and checksums. Backgrounds follow appearance; pages always request the LIGHT variant, including in dark mode.

## Pipeline audit / isolation

`ReaderPageView.imageRequest` is also used for page fetching, processing and caching outside visible pages. Its Nuke processors include source interception, border cropping and resampling; those must not receive paper material. The material processor is intentionally not an `ImageProcessing` appended to Nuke requests.

`ReaderPageView.setPageImage` now hands the existing decoded image to an independent presentation object. `imageView.image` remains the original post-existing-processing image. A noninteractive, accessibility-hidden child UIImageView displays the material result below dictionary overlays. Live Text, dictionary OCR, aspect-ratio calculations, background selection and spread splitting continue reading the original `imageView.image`; dictionary paragraph coordinates remain unchanged. Original downloads, source caches, cover requests and export code are not modified. OCR retains the application's existing crop/downsample/upscale behavior, not a second unprocessed source bitmap.

`replacePageImage` clears animation and material on recycling, reload, text switch and spread replacement. Material settings notifications cancel pending work and immediately remove the old display result. Generation tokens prevent stale results from returning after disable or page replacement. Disabling background texture, selecting background-only or zero page strength restores the original without refetching.

## Compositing and resource limits

Core Image multiplies a light texture mixed with white by page strength. Color protection masks the result into near-white neutral pixels (minimum RGB > 0.75, fading with chroma); it is not a semantic color-page detector. Turning protection off multiplies the full page; black ink remains black but colors may be tinted.

Textures tile every 512 source pixels in both axes, never stretch to webtoon height. Scale is relative to the existing decoded/resampled image, not physical screen points. Tile seams and alignment between independently split pages can be visible.

One serial OperationQueue bounds concurrent page renders. Each page stores at most one display result in addition to its preexisting original; no shared material cache or material disk data is introduced. Reuse is keyed by image generation plus `paper-material-v1/light/tile512/scope=pages/style/strength/color`. CIContext intermediate caching is disabled and rendering uses autorelease pools. Pending operations are canceled on replacement/disable/deallocation. An already-running Core Image render cannot be interrupted, but its result is discarded.

Processing skips animated UIImage/GIF data, non-CGImage-backed images, images over 8,000,000 pixels or over 32,768 pixels on either axis. Such pages display their original. These guards bound additional raster memory and tall-page work; the reader's existing original-image memory costs remain unchanged. GIF URL/archive pages and base64 GIFs bypass material. Animation formats not already supported by the reader retain existing decoding behavior.

## Verification

`PaperMaterialProcessorTests` complements the existing Nuke `PageProcessorTests`: input immutability, multiply white/black, color protection, zero intensity, orientation/scale, identifier variation, bundled light variants, animation/size guards and fixed repeat pitch. CI archive validates application compilation. The manual `paper-material-tests.yml` workflow runs Swift Testing through `xcodebuild test -scheme Aidoku`, selecting the processor and display suites, discovering an available iPhone simulator, and uploading destinations, test logs and xcresult. No local Xcode/simulator is available in Minis; execution uses the existing hosted `xcode-27` runner.

## Device report audit (iOS simulator verified; physical device unresolved)

The report that **the generated settings sample also remains unchanged** is important: the sample calls the same processor directly and does not use `PaperMaterialDisplay`, the page size guard, Nuke, dictionary overlays or a reader image view. A reader overlay-only explanation therefore cannot explain the entire report. With scope `pages`, kraft at high strength and a white generated sample, visible change is expected even with color protection enabled.

Confirmed separate defect in 2257fae: webtoon uses `ReaderWebtoonPageNode -> GIFImageNode -> GIFImageView`, not `ReaderPageView`. `GIFImageNode` had no `PaperMaterialDisplay` at all. This is now connected at custom-view creation and image assignment, and reset/animated-data paths clear or bypass the material. Original node and view images remain original for OCR, geometry and exports.

Shared-path investigation: this commit contains **no CIColorKernel/custom kernel compilation**. It uses built-in Core Image filters and `CIContext.createCGImage`; missing assets, missing CGImages and a nil raster result previously silently restored the sample/original. All seven catalog definitions and fourteen JPEGs validate/decode on Linux; kraft light is a genuine non-white 1024x1024 texture (mean normalized channel value about 0.708). This does not prove successful asset-catalog packaging/decoding or Core Image output on iOS. A shared `lightTexture(for:)` helper now resolves the catalog imageAsset explicitly under light traits and freezes its CGImage before queue handoff. This is defensive hardening, **not a proven diagnosis of an asset failure**.

The settings sample now explicitly reports background-only, zero strength, missing light CGImage, failed render, or successful render; it also warns if reader background is not Texture and states oversized/animation/non-CGImage fallback limits. `[PaperMaterial]` console diagnostics distinguish actual-page inactive settings, animated source, dimensions/pixel limit, missing light asset, and render result (including overlay/host bounds). All diagnostic UI strings are localized in English, Simplified Chinese and Traditional Chinese. Actual current-page status aggregation into settings is still a recommended follow-up, not implemented by this patch.

New tests cover material creation in an actual UIImageView, zero-to-laid-out overlay geometry, disabling while loaded, original image identity, webtoon view-block wiring/reset, and the previously missing critical invariant: **preserveColor=true must still change a white page**, both with a synthetic gray texture and bundled kraft. Existing color tests only asserted red preservation and metadata, which could pass if protection accidentally masked everything. These tests have now executed on a hosted iOS simulator, not locally in Minis. `git diff --check` and fourteen JPEG/catalog static checks pass; Swift/Xcode/iOS SDK are unavailable locally.

To resolve the remaining shared-path uncertainty on a device, use kraft 100% and inspect the sample status. If missing CGImage: inspect the built IPA's Assets.car and asset resolution; if render failed: collect Core Image console errors and test CPU CIContext as a diagnostic (not an unconditional production fallback). If status reports rendered but white is unchanged, run the new neutral-white protection test and compare preserveColor on/off: this separates mask logic from tiling/multiply. If sample works but a paged page does not, inspect `[PaperMaterial]` host/overlay sizes and capture a UIKit hierarchy snapshot. No claim is made that the shared sample failure is fixed until these checks pass.

### Hosted iOS regression evidence (2026-10-19)

Run https://github.com/liueggy/Aidoku/actions/runs/39277385581 executed 14 tests in two suites on iPhone 18 Pro / iOS 27.0. The test log reports all 14 passed. Earlier successful run https://github.com/liueggy/Aidoku/actions/runs/39274532314 executed 11 tests. Build-only failures encountered while introducing diagnostics/tests were fixed (removed unavailable NSStringFromCGRect, explicitly imported AsyncDisplayKit, removed throwing trait-closure and nested Testing macro usage).

Rendered RGBA evidence at kraft strength 100%:
- White input: protected and unprotected both `[221, 189, 151, 255]`.
- Actual paged UIImageView overlay and Webtoon GIFImageNode overlay: both `[221, 189, 151, 255]`; original UIImage identities remain unchanged.
- Legacy UIImage(named:compatibleWith:) path: the same RGBA under both light and dark ambient traits, with CGImage present.
- Background rendering: legacy and frozen asset both produce the same RGBA.
- DeviceGray-backed scanned white page: both protection settings produce the same RGBA.

Synthetic 50% gray texture mask branches (protected / unprotected RGB): black `0/0`; gray 128 `128/61`; gray 230 `216/115`; white `128/128`; yellow `[255,255,0]/[128,128,0]`; pale pink `[240,216,216]/[128,115,115]`. Both protection states pass synthetic 512-pixel periodic tiling tests. This validates the filter graph for opaque RGB and grayscale input on the tested runtime; it does not prove all alpha/color-space/GPU combinations on physical devices.

**Important negative finding:** no shared processor failure has been reproduced. The legacy resource path also passes, so the new light-texture freezing helper must NOT be described as the proven root cause of the unchanged settings sample. No speculative filter rewrite or unconditional CPU fallback was added. The confirmed Webtoon wiring omission is fixed, but it cannot explain the reported unchanged generated preview. Physical-device sample failure remains open; simulator success is not a claim that the user's entire issue is resolved.

Manual device checklist:
- Enable/disable while a page is loaded; move strength to zero and back; switch every style.
- Verify white manga regions have paper, black ink remains legible, color protection works.
- Switch system light/dark: page paper must remain light; background should switch variants.
- Swipe quickly, rotate, zoom, split/join double spreads; check no stale material from previous page.
- Test webtoon repeats and oversized original fallback, GIF playback, reload and text chapters.
- Verify Live Text and dictionary overlays and exported/downloaded images remain original.
- Profile memory and scrolling on older iPhones before considering wider pixel limits.
