import Cocoa

func getWindowId() -> Int? {
    guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return nil }
    for w in list {
        if let owner = w[kCGWindowOwnerName as String] as? String, owner == "Digital Books" {
            if let id = w[kCGWindowNumber as String] as? Int {
                return id
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
        repeat with i from 1 to 5
            try
                set position of window 1 to {\(x), \(y)}
                set size of window 1 to {\(w), \(h)}
                exit repeat
            on error
                delay 0.4
            end try
        end repeat
    end tell
    """
    runAppleScript(script)
    usleep(600000)
}

func captureWindow(toPath: String) {
    guard let id = getWindowId() else {
        print("Error: Could not find Digital Books window ID")
        return
    }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-l\(id)", toPath]
    try? task.run()
    task.waitUntilExit()
}

func launchApp(section: String) -> Process {
    // Kill any existing instances first
    let killTask = Process()
    killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    killTask.arguments = ["-9", "-f", "Digital Books"]
    try? killTask.run()
    killTask.waitUntilExit()
    usleep(300000)

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/Users/davindalana/Documents/Project/Digital Books/build/macos/Build/Products/Debug/Digital Books.app/Contents/MacOS/Digital Books")
    var env = ProcessInfo.processInfo.environment
    env["DIGITAL_BOOKS_SECTION"] = section
    task.environment = env
    try? task.run()
    usleep(2200000) // Wait for Flutter engine & window to initialize
    return task
}

let outputDir = "/Users/davindalana/Documents/Project/Digital Books/docs/visual_evidence/phase_2_native"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let winX = 100
let winY = 100

print("=== CAPTURING SEDANG DIBACA (HOME) ===")
var app = launchApp(section: "home")

print("1. Compact 700...")
setWindow(x: winX, y: winY, w: 700, h: 750)
captureWindow(toPath: "\(outputDir)/01_native_compact_700_sedang_dibaca.png")

print("2. Standard 900...")
setWindow(x: winX, y: winY, w: 900, h: 750)
captureWindow(toPath: "\(outputDir)/03_native_standard_900_sedang_dibaca.png")

print("3. Expansive 1280...")
setWindow(x: winX, y: winY, w: 1280, h: 800)
captureWindow(toPath: "\(outputDir)/05_native_expansive_1280_sedang_dibaca.png")

app.terminate()
usleep(500000)

print("\n=== CAPTURING SEMUA BUKU ===")
app = launchApp(section: "allBooks")

print("4. Compact 700...")
setWindow(x: winX, y: winY, w: 700, h: 750)
captureWindow(toPath: "\(outputDir)/02_native_compact_700_semua_buku.png")

print("5. Standard 900...")
setWindow(x: winX, y: winY, w: 900, h: 750)
captureWindow(toPath: "\(outputDir)/04_native_standard_900_semua_buku.png")

print("6. Expansive 1280...")
setWindow(x: winX, y: winY, w: 1280, h: 800)
captureWindow(toPath: "\(outputDir)/06_native_expansive_1280_semua_buku.png")

app.terminate()
usleep(300000)

print("\nAll 6 native macOS window screenshots successfully captured!")
