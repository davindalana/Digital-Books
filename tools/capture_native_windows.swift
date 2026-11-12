import Cocoa

func clickAt(x: CGFloat, y: CGFloat) {
    let pt = CGPoint(x: x, y: y)
    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left)
    let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left)
    down?.post(tap: .cghidEventTap)
    usleep(80000)
    up?.post(tap: .cghidEventTap)
    usleep(400000)
}

func getWindowInfo() -> (id: Int, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)? {
    guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return nil }
    for w in list {
        if let owner = w[kCGWindowOwnerName as String] as? String, owner == "Digital Books" {
            if let id = w[kCGWindowNumber as String] as? Int,
               let bounds = w[kCGWindowBounds as String] as? [String: Any],
               let x = bounds["X"] as? CGFloat,
               let y = bounds["Y"] as? CGFloat,
               let width = bounds["Width"] as? CGFloat,
               let height = bounds["Height"] as? CGFloat {
                return (id, x, y, width, height)
            }
        }
    }
    return nil
}

func runAppleScript(_ source: String) {
    var error: NSDictionary?
    if let script = NSAppleScript(source: source) {
        script.executeAndReturnError(&error)
        if let err = error {
            print("AppleScript error: \(err)")
        }
    }
}

func setWindow(x: Int, y: Int, w: Int, h: Int) {
    let script = """
    tell application "System Events" to tell process "Digital Books"
        set frontmost to true
        set position of window 1 to {\(x), \(y)}
        set size of window 1 to {\(w), \(h)}
    end tell
    """
    runAppleScript(script)
    usleep(500000)
}

func capture(id: Int, toPath: String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-l\(id)", toPath]
    try? task.run()
    task.waitUntilExit()
}

let winX = 100
let winY = 100

print("Setting up directory...")
let fileManager = FileManager.default
let outputDir = "/Users/davindalana/Documents/Project/Digital Books/docs/visual_evidence/phase_2_native"
try? fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

// 1. Compact (700)
print("1. Capturing Compact 700...")
setWindow(x: winX, y: winY, w: 700, h: 750)
if let info = getWindowInfo() {
    // Click Sedang Dibaca in compact rail (X ~ 32, Y ~ 75)
    clickAt(x: CGFloat(winX) + 32, y: CGFloat(winY) + 75)
    capture(id: info.id, toPath: "\(outputDir)/01_native_compact_700_sedang_dibaca.png")
    
    // Click Semua Buku in compact rail (X ~ 32, Y ~ 120)
    clickAt(x: CGFloat(winX) + 32, y: CGFloat(winY) + 120)
    capture(id: info.id, toPath: "\(outputDir)/02_native_compact_700_semua_buku.png")
}

// 2. Standard (900)
print("2. Capturing Standard 900...")
setWindow(x: winX, y: winY, w: 900, h: 750)
if let info = getWindowInfo() {
    // Click Sedang Dibaca in standard sidebar (X ~ 100, Y ~ 145)
    clickAt(x: CGFloat(winX) + 100, y: CGFloat(winY) + 145)
    capture(id: info.id, toPath: "\(outputDir)/03_native_standard_900_sedang_dibaca.png")
    
    // Click Semua Buku in standard sidebar (X ~ 100, Y ~ 185)
    clickAt(x: CGFloat(winX) + 100, y: CGFloat(winY) + 185)
    capture(id: info.id, toPath: "\(outputDir)/04_native_standard_900_semua_buku.png")
}

// 3. Expansive (1280)
print("3. Capturing Expansive 1280...")
setWindow(x: winX, y: winY, w: 1280, h: 800)
if let info = getWindowInfo() {
    // Click Sedang Dibaca in expansive sidebar (X ~ 100, Y ~ 145)
    clickAt(x: CGFloat(winX) + 100, y: CGFloat(winY) + 145)
    capture(id: info.id, toPath: "\(outputDir)/05_native_expansive_1280_sedang_dibaca.png")
    
    // Click Semua Buku in expansive sidebar (X ~ 100, Y ~ 185)
    clickAt(x: CGFloat(winX) + 100, y: CGFloat(winY) + 185)
    capture(id: info.id, toPath: "\(outputDir)/06_native_expansive_1280_semua_buku.png")
}

print("Done! Captured all 6 native screenshots.")

