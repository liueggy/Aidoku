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

`PaperMaterialProcessorTests` complements the existing Nuke `PageProcessorTests`: input immutability, multiply white/black, color protection, zero intensity, orientation/scale, identifier variation, bundled light variants, animation/size guards and fixed repeat pitch. CI archive validates application compilation; unit tests must be run separately with an iOS simulator using the Aidoku scheme. No local simulator/device execution was available in Minis.

Manual device checklist:
- Enable/disable while a page is loaded; move strength to zero and back; switch every style.
- Verify white manga regions have paper, black ink remains legible, color protection works.
- Switch system light/dark: page paper must remain light; background should switch variants.
- Swipe quickly, rotate, zoom, split/join double spreads; check no stale material from previous page.
- Test webtoon repeats and oversized original fallback, GIF playback, reload and text chapters.
- Verify Live Text and dictionary overlays and exported/downloaded images remain original.
- Profile memory and scrolling on older iPhones before considering wider pixel limits.
