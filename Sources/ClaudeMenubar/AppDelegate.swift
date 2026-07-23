import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let ccusage = CCUsage()
    private let calibration = CalibrationStore()
    private let prefs = Preferences()

    private var timer: Timer?
    private let workQueue = DispatchQueue(label: "de.bestler.claude-menubar.fetch", qos: .utility)

    /// Latest successful snapshot (nil until the first fetch succeeds).
    private var snapshot: UsageSnapshot?
    /// Latest error, if the last fetch failed.
    private var lastError: String?
    /// True while a fetch is in flight (avoids overlap).
    private var fetching = false

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "…"
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent",
                                   accessibilityDescription: "Claude usage")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
        }
        rebuildMenu()
        startTimer()
        refresh()
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: TimeInterval(prefs.refreshInterval),
                                     repeats: true) { [weak self] _ in
            self?.refresh()
        }
        t.tolerance = 2
        timer = t
    }

    // MARK: Fetch

    private func refresh() {
        guard !fetching else { return }
        fetching = true
        let wantWeek = prefs.weekTracking
        workQueue.async { [weak self] in
            guard let self else { return }
            var snap: UsageSnapshot?
            var err: String?
            do {
                if let block = try self.ccusage.fetchActiveBlock() {
                    // Reset time: prefer a live calibration (exact for this window),
                    // fall back to ccusage's floored block estimate.
                    let calibratedRemaining = self.calibration.calibratedRemainingMinutes()
                    var s = UsageSnapshot(
                        isActive: true,
                        tokens: block.totalTokens,
                        cost: block.costUSD,
                        costPerHour: block.burnRate?.costPerHour,
                        tokensPerMinute: block.burnRate?.tokensPerMinute,
                        remainingMinutes: calibratedRemaining ?? block.projection?.remainingMinutes,
                        sessionPct: self.calibration.sessionPct(forTokens: block.totalTokens),
                        sessionCalibratedAt: self.calibration.sessionCalibratedAt
                    )
                    s.resetCalibrated = calibratedRemaining != nil
                    s.resetRolled = calibratedRemaining != nil && self.calibration.resetHasRolled()
                    if wantWeek, let wk = self.ccusage.fetchCurrentWeekTokens() {
                        s.weekTokens = wk
                        s.weekPct = self.calibration.weekPct(forTokens: wk)
                        s.weekCalibratedAt = self.calibration.weekCalibratedAt
                    }
                    snap = s
                } else {
                    // No active session — still surface calibration status.
                    snap = UsageSnapshot.idle()
                }
            } catch {
                err = (error as? CCUsageError)?.errorDescription ?? error.localizedDescription
            }
            DispatchQueue.main.async {
                self.fetching = false
                if let snap {
                    self.snapshot = snap
                    self.lastError = nil
                } else {
                    self.lastError = err
                }
                self.updateBarTitle()
                self.rebuildMenu()
            }
        }
    }

    // MARK: Menu-bar title

    private func updateBarTitle() {
        guard let button = statusItem.button else { return }
        if lastError != nil {
            button.title = "⚠"
            return
        }
        guard let s = snapshot, s.isActive else {
            button.title = "—"
            return
        }
        switch prefs.barMetric {
        case .cost:
            button.title = Fmt.costShort(s.cost)
        case .tokens:
            button.title = Fmt.tokens(s.tokens)
        case .timeLeft:
            if let rem = s.remainingMinutes {
                button.title = (s.resetCalibrated ? "" : "~") + Fmt.durationShort(rem)
            } else {
                button.title = "—"
            }
        case .percent:
            button.title = s.sessionPct.map(Fmt.pct) ?? "—%"
        }
    }

    // MARK: Menu

    private func rebuildMenu() {
        let menu = NSMenu()

        // Header / state line.
        let header = NSMenuItem(title: headerText(), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if let err = lastError {
            let item = NSMenuItem(title: err, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            if case .some = ccusage.runnerLabel {} else {
                menu.addItem(withTitle: "How to install ccusage…",
                             action: #selector(showInstallHelp), keyEquivalent: "").target = self
            }
        } else if let s = snapshot, s.isActive {
            addDisabled(menu, "Cost: \(Fmt.cost(s.cost))")
            addDisabled(menu, "Tokens: \(Fmt.tokens(s.tokens))")
            if let cph = s.costPerHour, let tpm = s.tokensPerMinute {
                addDisabled(menu, "Burn: \(Fmt.costShort(cph))/hr · \(Fmt.tokens(Int(tpm)))/min")
            }
            if let rem = s.remainingMinutes {
                if s.resetCalibrated {
                    let note: String
                    if s.resetRolled {
                        note = " (auto-rolled)"
                    } else {
                        note = calibration.resetCalibratedAt.map { " (calibrated \(Fmt.ago($0)))" } ?? ""
                    }
                    addDisabled(menu, "Resets in: \(Fmt.duration(rem))\(note)")
                } else {
                    addDisabled(menu, "Block ends in: ~\(Fmt.duration(rem)) (estimate)")
                }
            }

            menu.addItem(.separator())

            // Session %.
            if let pct = s.sessionPct {
                let note = s.sessionCalibratedAt.map { " (calibrated \(Fmt.ago($0)))" } ?? ""
                addDisabled(menu, "Session: \(Fmt.pct(pct))\(note)")
            } else {
                addDisabled(menu, "Session %: not calibrated")
            }

            // Week (optional).
            if prefs.weekTracking {
                if let wpct = s.weekPct {
                    addDisabled(menu, "Week: \(Fmt.pct(wpct))")
                } else if let wt = s.weekTokens {
                    addDisabled(menu, "Week: \(Fmt.tokens(wt)) (not calibrated)")
                } else {
                    addDisabled(menu, "Week: —")
                }
            }
        } else {
            addDisabled(menu, "No active session")
        }

        menu.addItem(.separator())

        // Menu bar shows ▸
        let barMenu = NSMenu()
        for metric in BarMetric.allCases {
            let mi = NSMenuItem(title: metric.menuLabel, action: #selector(selectBarMetric(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = metric.rawValue
            mi.state = (prefs.barMetric == metric) ? .on : .off
            if metric == .percent && calibration.sessionLimit == nil {
                mi.isEnabled = false
                mi.toolTip = "Calibrate the session % first"
            }
            barMenu.addItem(mi)
        }
        let barItem = NSMenuItem(title: "Menu bar shows", action: nil, keyEquivalent: "")
        barItem.submenu = barMenu
        menu.addItem(barItem)

        // Refresh interval ▸
        let refreshMenu = NSMenu()
        for secs in Preferences.refreshChoices {
            let mi = NSMenuItem(title: "\(secs)s", action: #selector(selectRefresh(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = secs
            mi.state = (prefs.refreshInterval == secs) ? .on : .off
            refreshMenu.addItem(mi)
        }
        let refreshItem = NSMenuItem(title: "Refresh interval", action: nil, keyEquivalent: "")
        refreshItem.submenu = refreshMenu
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        // Calibration.
        menu.addItem(makeItem("Calibrate Session %…", #selector(calibrateSession)))
        menu.addItem(makeItem("Calibrate reset time…", #selector(calibrateReset)))
        if prefs.weekTracking {
            menu.addItem(makeItem("Calibrate Week %…", #selector(calibrateWeek)))
        }

        // Clear calibration ▸
        let clearMenu = NSMenu()
        let clearSess = makeItem("Session calibration", #selector(clearSessionCalibration))
        clearSess.isEnabled = calibration.sessionLimit != nil
        clearMenu.addItem(clearSess)
        let clearReset = makeItem("Reset-time calibration", #selector(clearResetCalibration))
        clearReset.isEnabled = calibration.resetAt != nil
        clearMenu.addItem(clearReset)
        let clearWk = makeItem("Week calibration", #selector(clearWeekCalibration))
        clearWk.isEnabled = calibration.weekLimit != nil
        clearMenu.addItem(clearWk)
        let clearItem = NSMenuItem(title: "Clear calibration", action: nil, keyEquivalent: "")
        clearItem.submenu = clearMenu
        clearItem.isEnabled = calibration.sessionLimit != nil || calibration.weekLimit != nil || calibration.resetAt != nil
        menu.addItem(clearItem)

        menu.addItem(.separator())

        // Week tracking toggle.
        let weekToggle = makeItem("Track weekly usage", #selector(toggleWeekTracking))
        weekToggle.state = prefs.weekTracking ? .on : .off
        menu.addItem(weekToggle)

        // Launch at login.
        let login = makeItem("Launch at login", #selector(toggleLoginItem))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(makeItem("Refresh now", #selector(refreshNow)))

        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Claude Menubar", #selector(quit)))

        statusItem.menu = menu
    }

    private func headerText() -> String {
        if lastError != nil { return "⚠ ccusage error" }
        guard let s = snapshot else { return "● Loading…" }
        return s.isActive ? "● Active session" : "○ Idle — no active session"
    }

    // MARK: Menu helpers

    private func addDisabled(_ menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: Actions

    @objc private func refreshNow() { refresh() }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    @objc private func selectBarMetric(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let m = BarMetric(rawValue: raw) else { return }
        prefs.barMetric = m
        updateBarTitle()
        rebuildMenu()
    }

    @objc private func selectRefresh(_ sender: NSMenuItem) {
        guard let secs = sender.representedObject as? Int else { return }
        prefs.refreshInterval = secs
        startTimer()
        rebuildMenu()
    }

    @objc private func toggleWeekTracking() {
        prefs.weekTracking.toggle()
        rebuildMenu()
        refresh()
    }

    @objc private func toggleLoginItem() {
        let want = !LoginItem.isEnabled
        if !LoginItem.setEnabled(want) {
            alert(title: "Couldn’t change login item",
                  text: "Status: \(LoginItem.statusDescription).\n\nLaunch-at-login only works when running from an installed app (build the .app and move it to /Applications).")
        }
        rebuildMenu()
    }

    @objc private func clearSessionCalibration() {
        calibration.clearSession()
        if prefs.barMetric == .percent { prefs.barMetric = .cost }
        refresh()
        rebuildMenu()
    }

    @objc private func clearWeekCalibration() {
        calibration.clearWeek()
        refresh()
        rebuildMenu()
    }

    @objc private func clearResetCalibration() {
        calibration.clearReset()
        refresh()
        rebuildMenu()
    }

    @objc private func calibrateReset() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Calibrate reset time"
        a.informativeText = "Claude Code shows the real reset ('resets in …') from live API data that isn’t stored on disk, so it can’t be read automatically. Type what Claude Code shows and we’ll count down exactly for this window, then auto-roll every 5h.\n\nFormats: 1h8 · 1h 8m · 1:08 · 68m"
        a.addButton(withTitle: "Save")
        a.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "e.g. 1h8"
        a.accessoryView = field
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return }
        guard let mins = Fmt.parseDurationMinutes(field.stringValue) else {
            alert(title: "Couldn’t read that", text: "Try a format like 1h8, 1:08, or 68m.")
            return
        }
        if calibration.calibrateReset(minutesFromNow: mins) {
            refresh()
            rebuildMenu()
        } else {
            alert(title: "Out of range", text: "Enter a time between 0 and 5 hours.")
        }
    }

    @objc private func calibrateSession() {
        guard let tokens = snapshot?.tokens, snapshot?.isActive == true, tokens > 0 else {
            alert(title: "No active session",
                  text: "Calibration needs a live token count. Start a Claude session and try again once usage shows up.")
            return
        }
        promptPercent(title: "Calibrate Session %",
                      message: "Open the Claude app and read the SESSION percentage it shows right now, then enter it here. We’ll map it to the current \(Fmt.tokens(tokens)) tokens.") { [weak self] pct in
            guard let self else { return }
            if self.calibration.calibrateSession(currentTokens: tokens, observedPercent: pct) {
                self.refresh()
                self.rebuildMenu()
            } else {
                self.alert(title: "Invalid percentage", text: "Enter a number between 0 and 100.")
            }
        }
    }

    @objc private func calibrateWeek() {
        guard let tokens = snapshot?.weekTokens, tokens > 0 else {
            alert(title: "No week data yet",
                  text: "Enable weekly tracking and wait for a refresh so the week’s token count is available.")
            return
        }
        promptPercent(title: "Calibrate Week %",
                      message: "Read the WEEK percentage from the Claude app and enter it here. We’ll map it to this week’s \(Fmt.tokens(tokens)) tokens.\n\nNote: ccusage’s week is a calendar week and may not exactly match Anthropic’s rolling window.") { [weak self] pct in
            guard let self else { return }
            if self.calibration.calibrateWeek(currentTokens: tokens, observedPercent: pct) {
                self.refresh()
                self.rebuildMenu()
            } else {
                self.alert(title: "Invalid percentage", text: "Enter a number between 0 and 100.")
            }
        }
    }

    @objc private func showInstallHelp() {
        alert(title: "Install ccusage",
              text: "This app runs the `ccusage` CLI. Install one of:\n\n• bun:  curl -fsSL https://bun.sh/install | bash\n• ccusage:  npm i -g ccusage\n\nWith bun or node installed, it can be run automatically via bunx/npx.")
    }

    // MARK: Dialogs

    private func promptPercent(title: String, message: String, onSubmit: @escaping (Double) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "Save")
        a.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "e.g. 47"
        a.accessoryView = field
        a.window.initialFirstResponder = field
        if a.runModal() == .alertFirstButtonReturn {
            let raw = field.stringValue.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
            if let pct = Double(raw) {
                onSubmit(pct)
            } else {
                alert(title: "Invalid percentage", text: "Enter a number between 0 and 100.")
            }
        }
    }

    private func alert(title: String, text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "OK")
        a.runModal()
    }
}
