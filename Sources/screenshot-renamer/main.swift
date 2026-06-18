import Foundation
import FoundationModels

setvbuf(stdout, nil, _IONBF, 0)

// MARK: - Options

struct Options {
    var dir = Renamer.defaultDir
    var dryRun = false
    var watch = false
    var max: Int? = nil
    var maxPixel = 1536
    var interval: TimeInterval = 3
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

func printUsage() {
    print("""
    screenshot-renamer — rename new screenshots using the on-device Apple model.

    USAGE: screenshot-renamer [options] [directory]

    OPTIONS:
      --dry-run         Show proposed names without renaming anything
      --watch           Keep running and poll the folder (Ctrl-C to stop)
      --once            Process current screenshots and exit (default)
      --max N           Process at most N files (handy with --dry-run)
      --max-pixel N     Downscale long edge to N pixels before analysis (default 1536)
      --interval N      Seconds between scans in --watch mode (default 3)
      -h, --help        Show this help

    Default directory: \(Renamer.defaultDir.path)
    """)
}

func parseArgs() -> Options {
    var o = Options()
    let args = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--dry-run": o.dryRun = true
        case "--watch": o.watch = true
        case "--once": o.watch = false
        case "--max": i += 1; o.max = Int(args[safe: i] ?? "")
        case "--max-pixel": i += 1; o.maxPixel = Int(args[safe: i] ?? "") ?? o.maxPixel
        case "--interval": i += 1; o.interval = Double(args[safe: i] ?? "") ?? o.interval
        case "-h", "--help": printUsage(); exit(0)
        case let a where !a.hasPrefix("-"):
            o.dir = URL(fileURLWithPath: (a as NSString).expandingTildeInPath, isDirectory: true)
        default:
            warn("ignoring unknown option: \(args[i])")
        }
        i += 1
    }
    return o
}

// MARK: - Availability

func ensureModelAvailable() {
    switch Renamer.model.availability {
    case .available:
        return
    case .unavailable(let reason):
        var msg = "On-device model unavailable: "
        switch reason {
        case .appleIntelligenceNotEnabled: msg += "turn on Apple Intelligence in System Settings."
        case .deviceNotEligible:           msg += "this device isn't eligible."
        case .modelNotReady:               msg += "model still downloading/preparing — try again shortly."
        @unknown default:                  msg += "\(reason)"
        }
        warn(msg)
        exit(1)
    }
}

// MARK: - Run

func scanOnce(_ o: Options) async {
    var list = Renamer.candidates(in: o.dir)
    if let m = o.max { list = Array(list.prefix(m)) }
    guard !list.isEmpty else { return }
    print("\(o.dryRun ? "DRY RUN — " : "")\(list.count) screenshot(s) in \(o.dir.path)")
    for url in list {
        guard let newName = await Renamer.process(url, dryRun: o.dryRun, maxPixel: o.maxPixel) else { continue }
        print("  \(o.dryRun ? "would →" : "renamed →") \(newName)")
        if o.dryRun { print("      (from \(url.lastPathComponent))") }
    }
}

let opts = parseArgs()
ensureModelAvailable()

if opts.watch {
    print("Watching \(opts.dir.path) every \(Int(opts.interval))s — Ctrl-C to stop.")
    while true {
        await scanOnce(opts)
        try? await Task.sleep(for: .seconds(opts.interval))
    }
} else {
    await scanOnce(opts)
}
