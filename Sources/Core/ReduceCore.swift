// Core/ReduceCore.swift - shrink a PDF by recompressing and downsampling its
// raster images through the macOS Quartz image filter, applied to a redraw of the
// document (the pdfreduce role). Text and vectors are re-recorded losslessly;
// only image XObjects are re-encoded. Redraw loses annotations, links, outline,
// and form fields - use qpdf for structure-preserving optimization.

import Foundation
import CoreGraphics
import PDFKit
import Quartz

struct ReduceOptions {
    var quality = 85       // JPEG quality 1-100
    var dpi = 150          // downsample images above this DPI; 0 disables
    // Cap the longest image edge in pixels; 0 disables. The default matches the
    // system "Reduce File Size.qfilter" (2400) rather than being off, and that
    // is load-bearing rather than cosmetic - see buildReduceFilter.
    var maxEdge = 2400
    var gray = false       // convert to grayscale via the system "Gray Tone" filter
    var filterPath: String?  // an explicit .qfilter, mutually exclusive with the above

    // True when the run's only purpose is to make the file smaller. That is what
    // licenses throwing away a result that grew: --gray and --filter ask for a
    // visual transformation, so their output is kept whatever it weighs, but a
    // plain recompression that produced a bigger file has simply failed.
    var isPureRecompression: Bool { filterPath == nil && !gray }
}

// Build the Quartz filter for the requested options. An explicit --filter file
// takes precedence; then --gray; otherwise the JPEG recompress/downsample filter
// built from the pdfreduce runtime-properties schema.
private func buildReduceFilter(_ opts: ReduceOptions) throws -> QuartzFilter {
    if let path = opts.filterPath {
        guard FileManager.default.fileExists(atPath: path) else {
            throw PDFUtilError.processing("filter not found: \(path)")
        }
        guard let filter = QuartzFilter(url: URL(fileURLWithPath: path)) else {
            throw PDFUtilError.processing("cannot load filter: \(path)")
        }
        return filter
    }
    if opts.gray {
        return try grayToneFilter()
    }

    // ImageSizeMax is what makes the JPEG setting below take effect at all.
    //
    // Measured: Quartz applies ImageJPEGCompress only to images it actually
    // RESCALES. Give it scale settings that match nothing and it decodes each
    // image and re-encodes it LOSSLESSLY as Flate, so a document of JPEG photos
    // grows several-fold - a 7.4 MB file of two camera images became 54.4 MB.
    // Omit the scale keys entirely and the images pass through untouched, which
    // is harmless but achieves nothing. Only a cap that fires produces JPEG.
    //
    // ImageResolution alone is the trap, because it is relative to the page: an
    // image placed at 72 DPI is never "above 150 DPI" however many pixels it
    // has, so -r never fires on documents assembled at the images' own DPI.
    // ImageSizeMax is absolute, so it fires on exactly the large images that
    // make a file big. That is why the system filter ships one and why the
    // default here is 2400 rather than off.
    var imageScale: [String: Any] = ["ImageScaleInterpolate": true, "ImageSizeMin": 0]
    if opts.dpi > 0 { imageScale["ImageResolution"] = opts.dpi }
    if opts.maxEdge > 0 { imageScale["ImageSizeMax"] = opts.maxEdge }

    let props: [String: Any] = [
        "Name": "pdfutil Reduce",
        "FilterType": 1,
        "Domains": ["Applications": true, "Printing": true],
        "FilterData": ["ColorSettings": ["ImageSettings": [
            "ImageCompression": "ImageJPEGCompress",
            "Compression Quality": Double(opts.quality) / 100.0,
            "ImageScaleSettings": imageScale,
        ]]],
    ]
    guard let filter = QuartzFilter(properties: props) else {
        throw PDFUtilError.processing("failed to create the reduce filter")
    }
    return filter
}

// Locate the system "Gray Tone" filter: first among the installed filters by
// localized name, then the on-disk fallback. A processing error if neither is
// present.
private func grayToneFilter() throws -> QuartzFilter {
    let managed = (QuartzFilterManager.filters(inDomains: nil) as? [QuartzFilter]) ?? []
    for filter in managed where filter.localizedName() == "Gray Tone" {
        return filter
    }
    let fallback = "/System/Library/Filters/Gray Tone.qfilter"
    if FileManager.default.fileExists(atPath: fallback),
       let filter = QuartzFilter(url: URL(fileURLWithPath: fallback)) {
        return filter
    }
    throw PDFUtilError.processing("the system 'Gray Tone' filter is not available")
}

// Size of the file at `path`, following symlinks.
//
// attributesOfItem is lstat-like: handed a symlink it reports the length of the
// link's target STRING, not of the document. That was cosmetic while this only
// fed the printed report, but the growth guard turns it into a decision - an
// 8-byte "size" makes every real output look like a catastrophic expansion, so
// reduce would decline on every symlinked input and quietly do nothing.
private func fileSize(_ path: String) -> Int {
    let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: resolved),
          let size = attrs[.size] as? Int else { return 0 }
    return size
}

// Reduce the document at `path`, writing the smaller PDF under the overwrite
// policy, and print a size-report line to stderr (pdfreduce's format).
func reduceDocument(path: String, output: String?, force: Bool, password: String?,
                    options: ReduceOptions) throws {
    let cgDoc = try openCGPDF(path: path, password: password)
    let pageCount = cgDoc.numberOfPages
    guard pageCount > 0 else {
        throw PDFUtilError.processing("PDF has no pages: \(path)")
    }
    let filter = try buildReduceFilter(options)

    // Carry the Info metadata across the redraw (best effort; a reduce of a
    // locked file has already been unlocked above with the same password).
    var aux: [CFString: Any] = [:]
    if let doc = try? openPDF(path: path, password: password) {
        aux = metadataContextInfo(from: doc)
    }

    let inSize = fileSize(path)

    // Recompression can enlarge a file - re-encoding an already-optimal image,
    // or the redraw's own overhead on a mostly-vector document. When shrinking
    // is the whole point of the run, that result is not worth keeping: the user
    // asked for a smaller PDF and the honest answer is the one they already had.
    var rejectedSize = 0
    let committed = try writeAtomically(to: output, force: force, inPlaceOf: path, accept: { tmpURL in
        guard options.isPureRecompression else { return true }
        let produced = fileSize(tmpURL.path)
        if produced > 0 && produced < inSize { return true }
        rejectedSize = produced
        return false
    }) { tmpURL in
        try redraw(document: cgDoc, to: tmpURL, auxiliaryInfo: aux, filter: filter)
    }

    if !committed {
        // In place there is nothing to do - the file was never touched. With -o
        // the user still asked for a document at that path, so give them one:
        // a copy of the input, which is both smaller and structurally intact,
        // since it never went through the redraw.
        if let output = output {
            try copyOriginal(from: path, to: output, force: force)
        }
        let grew = inSize > 0 ? (Double(rejectedSize) / Double(inSize) - 1.0) * 100.0 : 0
        writeErr(String(format:
            "reduce: %d page(s), %d bytes, kept the original (recompression produced %d bytes, %.1f%% larger)\n",
            pageCount, inSize, rejectedSize, grew))
        return
    }

    let outSize = fileSize(output ?? path)
    // Say which way it went: the old format printed a signed number against a
    // fixed word, so a file that grew by 9.2% was reported as "(-9.2% smaller)".
    // A run can still land here having grown - --gray and --filter are kept
    // whatever their size, because the transformation was the point.
    let ratio = inSize > 0 ? Double(outSize) / Double(inSize) : 1.0
    let pct = abs(1.0 - ratio) * 100.0
    if outSize == inSize {
        writeErr(String(format: "reduce: %d page(s), %d -> %d bytes (unchanged)\n",
                        pageCount, inSize, outSize))
    } else {
        let direction = outSize < inSize ? "smaller" : "larger"
        writeErr(String(format: "reduce: %d page(s), %d -> %d bytes (%.1f%% %@)\n",
                        pageCount, inSize, outSize, pct, direction))
    }
}

// Put the input at the output path unchanged, for a reduce that declined its own
// result.
//
// Everything here is done on RESOLVED paths, because both hazards are symlinks:
//
//  - "-o names the input" is not just string equality. A symlinked input whose
//    -o names its own target is the same file by another name, and the earlier
//    version of this function removed the destination and then copied - which
//    deleted the real document and left a symlink pointing at itself. Comparing
//    resolved paths is what catches that.
//  - FileManager.copyItem COPIES A SYMLINK AS A SYMLINK rather than copying what
//    it points at, so copying an unresolved source produced an 8-byte link where
//    a PDF was promised. Reading through the link is the only correct source.
//
// Routed through writeAtomically rather than remove-then-copy so the fallback
// inherits the same overwrite policy as the normal path: staged through a temp
// sibling, and committed with moveItem, which FAILS rather than clobbering a
// file that appeared while the redraw was running. remove-then-copy would have
// silently overwritten it, which is exactly the race the create-only MCP tier
// relies on this not doing.
private func copyOriginal(from path: String, to output: String, force: Bool) throws {
    let srcURL = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    let destURL = URL(fileURLWithPath: output).resolvingSymlinksInPath()
    guard destURL.path != srcURL.path else { return }

    try writeAtomically(to: output, force: force, inPlaceOf: path) { tmpURL in
        do {
            try FileManager.default.copyItem(at: srcURL, to: tmpURL)
        } catch {
            throw PDFUtilError.processing("failed to save output: \(output)")
        }
    }
}
