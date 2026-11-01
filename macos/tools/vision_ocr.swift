import Foundation
import Vision
import AppKit

struct BoundingBox: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct OcrLine: Codable {
    let text: String
    let confidence: Double
    let box: BoundingBox
}

struct OcrOutput: Codable {
    let imagePath: String
    let width: Int
    let height: Int
    let durationMs: Double
    let lines: [OcrLine]
    let error: String?
}

func printUsage() {
    print("Usage: vision_ocr --image <image_path> [--languages id-ID,en-US] [--accurate|--fast]")
}

func runOcr(imagePath: String, languages: [String], accurate: Bool) {
    let startTime = DispatchTime.now()
    
    guard let image = NSImage(contentsOfFile: imagePath) else {
        let out = OcrOutput(imagePath: imagePath, width: 0, height: 0, durationMs: 0, lines: [], error: "Failed to load image from path")
        let data = try! JSONEncoder().encode(out)
        print(String(data: data, encoding: .utf8)!)
        return
    }
    
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        let out = OcrOutput(imagePath: imagePath, width: 0, height: 0, durationMs: 0, lines: [], error: "Failed to create CGImage")
        let data = try! JSONEncoder().encode(out)
        print(String(data: data, encoding: .utf8)!)
        return
    }
    
    let width = cgImage.width
    let height = cgImage.height
    var extractedLines: [OcrLine] = []
    var ocrError: String? = nil
    
    let request = VNRecognizeTextRequest { req, err in
        if let err = err {
            ocrError = err.localizedDescription
            return
        }
        guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
        
        for obs in observations {
            guard let top = obs.topCandidates(1).first else { continue }
            let bb = obs.boundingBox
            // Vision coordinate system has (0,0) at bottom-left.
            // Convert to standard document top-down coordinates:
            // top_y = 1.0 - (bb.origin.y + bb.size.height)
            let topY = 1.0 - (bb.origin.y + bb.size.height)
            let box = BoundingBox(
                x: Double(bb.origin.x),
                y: Double(topY),
                width: Double(bb.size.width),
                height: Double(bb.size.height)
            )
            extractedLines.append(OcrLine(
                text: top.string,
                confidence: Double(top.confidence),
                box: box
            ))
        }
    }
    
    request.recognitionLevel = accurate ? .accurate : .fast
    request.recognitionLanguages = languages
    request.usesLanguageCorrection = true
    
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        ocrError = error.localizedDescription
    }
    
    let endTime = DispatchTime.now()
    let elapsedNs = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
    let durationMs = Double(elapsedNs) / 1_000_000.0
    
    let output = OcrOutput(
        imagePath: imagePath,
        width: width,
        height: height,
        durationMs: durationMs,
        lines: extractedLines,
        error: ocrError
    )
    
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    if let data = try? encoder.encode(output), let json = String(data: data, encoding: .utf8) {
        print(json)
    }
}

// CLI Argument Parsing
var imagePath: String?
var languages = ["id-ID", "en-US"]
var accurate = true

var i = 1
while i < CommandLine.arguments.count {
    let arg = CommandLine.arguments[i]
    if arg == "--image" && i + 1 < CommandLine.arguments.count {
        imagePath = CommandLine.arguments[i + 1]
        i += 2
    } else if arg == "--languages" && i + 1 < CommandLine.arguments.count {
        languages = CommandLine.arguments[i + 1].split(separator: ",").map(String.init)
        i += 2
    } else if arg == "--fast" {
        accurate = false
        i += 1
    } else if arg == "--accurate" {
        accurate = true
        i += 1
    } else {
        i += 1
    }
}

guard let path = imagePath else {
    printUsage()
    exit(1)
}

runOcr(imagePath: path, languages: languages, accurate: accurate)

