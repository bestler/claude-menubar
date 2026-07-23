import Foundation

/// Errors surfaced to the UI.
enum CCUsageError: LocalizedError {
    /// No way to run ccusage was found (no ccusage binary, no bunx, no npx).
    case unavailable
    case processFailed(String)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "ccusage not found (install ccusage, or bun/node so it can be run via bunx/npx)"
        case .processFailed(let s):
            return "ccusage failed: \(s)"
        case .decodeFailed(let s):
            return "could not parse ccusage output: \(s)"
        }
    }
}

/// Resolves how to invoke ccusage and runs it, off the main thread.
///
/// GUI apps do NOT inherit the shell PATH, so we search common locations
/// explicitly rather than relying on the environment we were launched with.
final class CCUsage {
    /// A resolved way to run ccusage: `launchPath` + leading `argv` prefix.
    struct Runner {
        let launchPath: String
        let prefixArgs: [String]
        let label: String
        /// PATH to expose to the child (so bunx/npx can locate node).
        let path: String
    }

    static let defaultsOverrideKey = "ccusageRunnerPath"

    private var cached: Runner?
    private let lock = NSLock()

    // MARK: Candidate search

    private static func homeDir() -> String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// Directories to search for executables, in priority order.
    private static func candidateDirs() -> [String] {
        let home = homeDir()
        var dirs = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/homebrew/opt/node/bin",
            "/usr/local/opt/node/bin",
            "\(home)/.bun/bin",
            "\(home)/.local/bin",
            "\(home)/.deno/bin",
            "/usr/bin",
            "/bin",
        ]
        // nvm: ~/.nvm/versions/node/<version>/bin — pick the highest version present.
        let nvmBase = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmBase) {
            let sorted = versions.sorted { compareVersions($0, $1) }
            for v in sorted.reversed() {
                dirs.append("\(nvmBase)/\(v)/bin")
            }
        }
        // fnm / volta / asdf shims, plus whatever PATH we did inherit.
        dirs.append("\(home)/.fnm/aliases/default/bin")
        dirs.append("\(home)/.volta/bin")
        dirs.append("\(home)/.asdf/shims")
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            dirs.append(contentsOf: envPath.split(separator: ":").map(String.init))
        }
        // De-dupe, preserving order.
        var seen = Set<String>()
        return dirs.filter { seen.insert($0).inserted }
    }

    /// Compares "v20.12.0" style strings numerically (returns a < b).
    private static func compareVersions(_ a: String, _ b: String) -> Bool {
        func nums(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
                .split(separator: ".").map { Int($0) ?? 0 }
        }
        let x = nums(a), y = nums(b)
        for i in 0..<max(x.count, y.count) {
            let xi = i < x.count ? x[i] : 0
            let yi = i < y.count ? y[i] : 0
            if xi != yi { return xi < yi }
        }
        return false
    }

    private static func findExecutable(_ name: String, in dirs: [String]) -> String? {
        let fm = FileManager.default
        for dir in dirs {
            let full = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: full) { return full }
        }
        return nil
    }

    /// Builds a PATH string from the candidate dirs so the child can find node.
    private static func augmentedPath(_ dirs: [String]) -> String {
        dirs.joined(separator: ":")
    }

    /// Resolve (and cache) a way to run ccusage.
    private func resolveRunner() -> Runner? {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }

        let dirs = Self.candidateDirs()
        let path = Self.augmentedPath(dirs)

        // 1. Explicit override from the user.
        if let override = UserDefaults.standard.string(forKey: Self.defaultsOverrideKey),
           !override.isEmpty, FileManager.default.isExecutableFile(atPath: override) {
            let r = Runner(launchPath: override, prefixArgs: [], label: override, path: path)
            cached = r
            return r
        }

        // 2. A real ccusage binary on disk.
        if let bin = Self.findExecutable("ccusage", in: dirs) {
            let r = Runner(launchPath: bin, prefixArgs: [], label: "ccusage", path: path)
            cached = r
            return r
        }

        // 3. bunx.
        if let bunx = Self.findExecutable("bunx", in: dirs) {
            let r = Runner(launchPath: bunx, prefixArgs: ["ccusage@latest"], label: "bunx ccusage@latest", path: path)
            cached = r
            return r
        }

        // 4. npx.
        if let npx = Self.findExecutable("npx", in: dirs) {
            let r = Runner(launchPath: npx, prefixArgs: ["-y", "ccusage@latest"], label: "npx ccusage@latest", path: path)
            cached = r
            return r
        }

        return nil
    }

    /// Label describing the resolved runner (for the menu / diagnostics), or nil if unavailable.
    var runnerLabel: String? { resolveRunner()?.label }

    /// Forget the cached runner (call after the user changes the override).
    func resetRunner() {
        lock.lock(); cached = nil; lock.unlock()
    }

    // MARK: Execution

    /// Run ccusage with `args`, returning raw stdout data. Throws on failure.
    private func run(_ args: [String]) throws -> Data {
        guard let runner = resolveRunner() else { throw CCUsageError.unavailable }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: runner.launchPath)
        proc.arguments = runner.prefixArgs + args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = runner.path
        env["HOME"] = Self.homeDir()
        proc.environment = env

        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err

        do {
            try proc.run()
        } catch {
            throw CCUsageError.processFailed(error.localizedDescription)
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8) ?? "exit \(proc.terminationStatus)"
            throw CCUsageError.processFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return data
    }

    /// Fetch the active block. Returns nil (not an error) when there is no active session.
    func fetchActiveBlock() throws -> Block? {
        let data = try run(["blocks", "--active", "--json"])
        let decoded: BlocksResponse
        do {
            decoded = try JSONDecoder().decode(BlocksResponse.self, from: data)
        } catch {
            throw CCUsageError.decodeFailed(error.localizedDescription)
        }
        return decoded.blocks.first { $0.isActive && !($0.isGap ?? false) }
    }

    /// Best-effort current-week total tokens. Returns nil on any failure (caller degrades gracefully).
    func fetchCurrentWeekTokens() -> Int? {
        guard let data = try? run(["weekly", "--json"]) else { return nil }
        guard let decoded = try? JSONDecoder().decode(WeeklyResponse.self, from: data) else { return nil }
        // The last row is the current calendar week.
        return decoded.weekly.last?.totalTokens
    }
}
