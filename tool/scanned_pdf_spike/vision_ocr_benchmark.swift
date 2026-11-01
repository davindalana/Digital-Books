import Foundation
import PDFKit
import Vision
import CoreImage

struct PageOcrResult: Codable {
    let pageNumber: Int
    let linesCount: Int
    let meanConfidence: Double
    let durationSeconds: Double
    let sampleLines: [String]
    let detectedCategories: [String]
}

struct BenchmarkSummary: Codable {
    let documentName: String
    let totalPagesTested: Int
    let totalLinesDetected: Int
    let meanConfidence: Double
    let meanTimePerPageMs: Double
    let totalDurationSeconds: Double
    let peakMemoryMB: Double
    let pages: [PageOcrResult]
}

func getMemoryUsageMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    if kerr == KERN_SUCCESS {
        return Double(info.resident_size) / (1024.0 * 1024.0)
    }
    return 0.0
}

func benchmarkPdf(path: String, maxPages: Int, languages: [String] = ["id-ID", "en-US"]) -> BenchmarkSummary? {
    let url = URL(fileURLWithPath: path)
    guard let doc = PDFDocument(url: url) else {
        fputs("Cannot open PDF at \(path)\n", stderr)
        return nil
    }
    
    let docName = url.lastPathComponent
    let pagesToTest = min(doc.pageCount, maxPages)
    var pageResults: [PageOcrResult] = []
    let totalStart = CFAbsoluteTimeGetCurrent()
    
    var totalConfidenceSum: Double = 0.0
    var totalLinesSum: Int = 0
    let startMem = getMemoryUsageMB()
    var peakMem = startMem
    
    for i in 0..<pagesToTest {
        guard let page = doc.page(at: i) else { continue }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 200.0 / 72.0
        let targetSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let thumbnail = page.thumbnail(of: targetSize, for: .mediaBox)
        guard let cgImg = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
        
        let pStart = CFAbsoluteTimeGetCurrent()
        var recognizedLines: [(text: String, conf: Double, box: CGRect)] = []
        
        let req = VNRecognizeTextRequest { req, _ in
            guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
            for obs in observations {
                if let top = obs.topCandidates(1).first {
                    recognizedLines.append((text: top.string, conf: Double(top.confidence), box: obs.boundingBox))
                }
            }
        }
        req.recognitionLevel = .accurate
        req.recognitionLanguages = languages
        req.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: cgImg, options: [:])
        try? handler.perform([req])
        let pDuration = CFAbsoluteTimeGetCurrent() - pStart
        
        let linesCount = recognizedLines.count
        let confSum = recognizedLines.reduce(0.0) { $0 + $1.conf }
        let meanConf = linesCount > 0 ? (confSum / Double(linesCount)) : 0.0
        
        totalLinesSum += linesCount
        totalConfidenceSum += confSum
        
        var categories: [String] = []
        for line in recognizedLines {
            let t = line.text.lowercased()
            if line.box.origin.y > 0.90 && (t.count < 6 || t.contains("bab") || t.contains("halaman")) {
                if !categories.contains("header_page_num") { categories.append("header_page_num") }
            }
            if t.starts(with: "bab ") || t.starts(with: "chapter ") || t.starts(with: "i. ") || t.starts(with: "ii. ") {
                if !categories.contains("heading") { categories.append("heading") }
            }
            if t.contains("—") || t.contains("\"") || t.contains("“") || t.contains("kataku") || t.contains("tanyanya") {
                if !categories.contains("dialogue") { categories.append("dialogue") }
            }
            if t.contains("|") || (line.box.size.width < 0.35 && recognizedLines.filter({ abs($0.box.origin.y - line.box.origin.y) < 0.01 }).count > 1) {
                if !categories.contains("columns_or_tables") { categories.append("columns_or_tables") }
            }
        }
        if categories.isEmpty && linesCount > 0 {
            categories.append("body_paragraph")
        }
        
        let sample = Array(recognizedLines.prefix(3).map { $0.text })
        pageResults.append(
            PageOcrResult(
                pageNumber: i + 1,
                linesCount: linesCount,
                meanConfidence: meanConf,
                durationSeconds: pDuration,
                sampleLines: sample,
                detectedCategories: categories
            )
        )
        
        let currentMem = getMemoryUsageMB()
        if currentMem > peakMem { peakMem = currentMem }
    }
    
    let totalDuration = CFAbsoluteTimeGetCurrent() - totalStart
    let overallMeanConf = totalLinesSum > 0 ? (totalConfidenceSum / Double(totalLinesSum)) : 0.0
    let meanTimeMs = (totalDuration / Double(pagesToTest)) * 1000.0
    
    return BenchmarkSummary(
        documentName: docName,
        totalPagesTested: pagesToTest,
        totalLinesDetected: totalLinesSum,
        meanConfidence: overallMeanConf,
        meanTimePerPageMs: meanTimeMs,
        totalDurationSeconds: totalDuration,
        peakMemoryMB: peakMem,
        pages: pageResults
    )
}

// Run benchmarks on the target corpus
let targets = [
    ("/Users/davindalana/Documents/DigitalBooks/originals/8565c1aa-0bb7-4876-8fd6-38ce318d3ed4.pdf", 5, ["id-ID", "en-US"]), // Laut Bercerita (Scanned Novel)
    ("/Users/davindalana/Documents/DigitalBooks/originals/d25fb8e8-c1a6-431f-822f-ce78f2b756e3.pdf", 5, ["id-ID", "en-US"]), // Bicara Itu Ada Seninya (Scanned Nonfiction)
    ("test/fixtures/corpus/04_two_column_academic.pdf", 1, ["en-US"]),                          // Two-column academic
    ("test/fixtures/corpus/09_hybrid_mixed.pdf", 3, ["en-US"]),                                 // Hybrid mixed
    ("test/fixtures/corpus/01_single_column_novel.pdf", 1, ["en-US"])                            // Single column control
]

var summaries: [BenchmarkSummary] = []
print("=================================================================")
print("DIGITAL BOOKS — PHASE 3.0 APPLE VISION OCR BENCHMARK SUITE")
print("=================================================================")

for (path, pages, langs) in targets {
    if FileManager.default.fileExists(atPath: path) {
        if let s = benchmarkPdf(path: path, maxPages: pages, languages: langs) {
            summaries.append(s)
            print("[\(s.documentName)] Pages: \(s.totalPagesTested) | Lines: \(s.totalLinesDetected) | Mean Conf: \(String(format: "%.3f", s.meanConfidence)) | Latency: \(String(format: "%.1f", s.meanTimePerPageMs)) ms/page | Peak RAM: \(String(format: "%.1f", s.peakMemoryMB)) MB")
        }
    } else {
        print("Skipping \(path) (not found)")
    }
}

let encoder = JSONEncoder()
encoder.outputFormatting = .prettyPrinted
if let data = try? encoder.encode(summaries), let jsonStr = String(data: data, encoding: .utf8) {
    let outUrl = URL(fileURLWithPath: "tool/scanned_pdf_spike/benchmark_ocr_results.json")
    try? jsonStr.write(to: outUrl, atomically: true, encoding: .utf8)
    print("\nBenchmark results saved to: tool/scanned_pdf_spike/benchmark_ocr_results.json")
}

