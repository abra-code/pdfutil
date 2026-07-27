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
    var maxEdge = 0        // cap the longest image edge in pixels; 0 disables
    var gray = false       // convert to grayscale via the system "Gray Tone" filter
    var filterPath: String?  // an explicit .qfilter, mutually exclusive with the above
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

private func fileSize(_ path: String) -> Int {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
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
    try writeAtomically(to: output, force: force, inPlaceOf: path) { tmpURL in
        try redraw(document: cgDoc, to: tmpURL, auxiliaryInfo: aux, filter: filter)
    }
    let outSize = fileSize(output ?? path)
    // Recompression can enlarge a file (re-encoding an already-optimal image,
    // or the redraw's own overhead on a mostly-vector document). Say which way
    // it went: the old format printed a signed number against a fixed word, so
    // a file that grew by 9.2% was reported as "(-9.2% smaller)".
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
