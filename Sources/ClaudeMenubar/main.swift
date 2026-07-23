import AppKit

// Headless self-check: resolve the runner, fetch once, print, exit.
// Useful for debugging PATH issues in the installed .app.
if CommandLine.arguments.contains("--diagnose") {
    let cc = CCUsage()
    print("runner: \(cc.runnerLabel ?? "NONE — ccusage/bunx/npx not found")")
    do {
        if let block = try cc.fetchActiveBlock() {
            print("active: tokens=\(block.totalTokens) cost=\(String(format: "%.2f", block.costUSD)) " +
                  "remainingMin=\(block.projection?.remainingMinutes.map(String.init) ?? "-") " +
                  "burn=\(block.burnRate?.costPerHour.map { String(format: "%.2f", $0) } ?? "-")/hr")
        } else {
            print("active: none (no live session)")
        }
        print("week tokens: \(cc.fetchCurrentWeekTokens().map(String.init) ?? "unavailable")")
    } catch {
        print("error: \((error as? CCUsageError)?.errorDescription ?? error.localizedDescription)")
        exit(1)
    }
    exit(0)
}

// Menu-bar-only agent app: no dock icon, no main window.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
