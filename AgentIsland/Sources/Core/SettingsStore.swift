import Foundation

enum DisplayMode: String, Codable, CaseIterable {
    case compact
    case detailed
}

@MainActor
@Observable
final class SettingsStore {
    // MARK: - General
    var launchAtLogin: Bool { didSet { persist() } }
    var hoverToExpand: Bool { didSet { persist() } }
    var hoverDelay: TimeInterval { didSet { persist() } }
    var smartSuppression: Bool { didSet { persist() } }
    var hideInFullscreen: Bool { didSet { persist() } }
    var hideWhenNoActiveSessions: Bool { didSet { persist() } }
    var autoCollapseOnMouseExit: Bool { didSet { persist() } }
    var autoReminderDuration: TimeInterval { didSet { persist() } }
    var dismissOnClickOutside: Bool { didSet { persist() } }
    var agentTeamAutoExpand: Bool { didSet { persist() } }
    var idleCleanupInterval: TimeInterval { didSet { persist() } }
    var disableClickToJump: Bool { didSet { persist() } }
    // MARK: - Display
    var displayMode: DisplayMode { didSet { persist() } }
    var monitorSelection: Int { didSet { persist() } }
    var panelFontSize: CGFloat { didSet { persist() } }
    var completionCardHeight: CGFloat { didSet { persist() } }
    var maxPanelHeight: CGFloat { didSet { persist() } }
    var maxPanelWidth: CGFloat { didSet { persist() } }
    var notchWidthOffset: CGFloat { didSet { persist() } }
    var notchHeightOffset: CGFloat { didSet { persist() } }
    var showSubAgentDetails: Bool { didSet { persist() } }
    // MARK: - Notification Filter
    var enableBuiltInFilters: Bool { didSet { persist() } }
    var filterKeywords: [String] { didSet { persist() } }
    // MARK: - Sound
    var soundEnabled: Bool { didSet { persist() } }
    var soundVolume: Float { didSet { persist() } }
    var soundSessionStart: String { didSet { persist() } }
    var soundSessionEnd: String { didSet { persist() } }
    var soundConfirmationArrived: String { didSet { persist() } }
    var soundConfirmationApproved: String { didSet { persist() } }
    var soundConfirmationDenied: String { didSet { persist() } }
    var soundError: String { didSet { persist() } }
    var soundReconnected: String { didSet { persist() } }
    var soundIdleReminder: String { didSet { persist() } }

    private let defaults: UserDefaults
    private var isLoading = false
    private static let keyPrefix = "ai."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchAtLogin = true; hoverToExpand = true; hoverDelay = 0.15
        smartSuppression = true; hideInFullscreen = true; hideWhenNoActiveSessions = false
        autoCollapseOnMouseExit = true; autoReminderDuration = 5.0; dismissOnClickOutside = false
        agentTeamAutoExpand = false; idleCleanupInterval = 7200; disableClickToJump = false
        enableBuiltInFilters = true; filterKeywords = []
        displayMode = .detailed; monitorSelection = 0; panelFontSize = 11
        completionCardHeight = 90; maxPanelHeight = 560; maxPanelWidth = 640
        notchWidthOffset = 0; notchHeightOffset = 0; showSubAgentDetails = false
        soundEnabled = true; soundVolume = 0.3
        soundSessionStart = "default"; soundSessionEnd = "default"
        soundConfirmationArrived = "default"; soundConfirmationApproved = "default"
        soundConfirmationDenied = "default"; soundError = "default"
        soundReconnected = "default"; soundIdleReminder = "default"
        load()
    }

    func resetToDefaults() {
        isLoading = true
        defer { isLoading = false; persist() }
        launchAtLogin = true; hoverToExpand = true; hoverDelay = 0.15
        smartSuppression = true; hideInFullscreen = true; hideWhenNoActiveSessions = false
        autoCollapseOnMouseExit = true; autoReminderDuration = 5.0; dismissOnClickOutside = false
        agentTeamAutoExpand = false; idleCleanupInterval = 7200; disableClickToJump = false
        enableBuiltInFilters = true; filterKeywords = []
        displayMode = .detailed; monitorSelection = 0; panelFontSize = 11
        completionCardHeight = 90; maxPanelHeight = 560; maxPanelWidth = 640
        notchWidthOffset = 0; notchHeightOffset = 0; showSubAgentDetails = false
        soundEnabled = true; soundVolume = 0.3
        soundSessionStart = "default"; soundSessionEnd = "default"
        soundConfirmationArrived = "default"; soundConfirmationApproved = "default"
        soundConfirmationDenied = "default"; soundError = "default"
        soundReconnected = "default"; soundIdleReminder = "default"
    }

    private func key(_ name: String) -> String { Self.keyPrefix + name }

    private func persist() {
        guard !isLoading else { return }
        let d = defaults
        let k = key
        d.set(launchAtLogin, forKey: k("launchAtLogin"))
        d.set(hoverToExpand, forKey: k("hoverToExpand"))
        d.set(hoverDelay, forKey: k("hoverDelay"))
        d.set(smartSuppression, forKey: k("smartSuppression"))
        d.set(hideInFullscreen, forKey: k("hideInFullscreen"))
        d.set(hideWhenNoActiveSessions, forKey: k("hideWhenNoActiveSessions"))
        d.set(autoCollapseOnMouseExit, forKey: k("autoCollapseOnMouseExit"))
        d.set(autoReminderDuration, forKey: k("autoReminderDuration"))
        d.set(dismissOnClickOutside, forKey: k("dismissOnClickOutside"))
        d.set(agentTeamAutoExpand, forKey: k("agentTeamAutoExpand"))
        d.set(idleCleanupInterval, forKey: k("idleCleanupInterval"))
        d.set(disableClickToJump, forKey: k("disableClickToJump"))
        d.set(displayMode.rawValue, forKey: k("displayMode"))
        d.set(monitorSelection, forKey: k("monitorSelection"))
        d.set(Double(panelFontSize), forKey: k("panelFontSize"))
        d.set(Double(completionCardHeight), forKey: k("completionCardHeight"))
        d.set(Double(maxPanelHeight), forKey: k("maxPanelHeight"))
        d.set(Double(maxPanelWidth), forKey: k("maxPanelWidth"))
        d.set(Double(notchWidthOffset), forKey: k("notchWidthOffset"))
        d.set(Double(notchHeightOffset), forKey: k("notchHeightOffset"))
        d.set(showSubAgentDetails, forKey: k("showSubAgentDetails"))
        d.set(soundEnabled, forKey: k("soundEnabled"))
        d.set(soundVolume, forKey: k("soundVolume"))
        d.set(soundSessionStart, forKey: k("soundSessionStart"))
        d.set(soundSessionEnd, forKey: k("soundSessionEnd"))
        d.set(soundConfirmationArrived, forKey: k("soundConfirmationArrived"))
        d.set(soundConfirmationApproved, forKey: k("soundConfirmationApproved"))
        d.set(soundConfirmationDenied, forKey: k("soundConfirmationDenied"))
        d.set(soundError, forKey: k("soundError"))
        d.set(soundReconnected, forKey: k("soundReconnected"))
        d.set(soundIdleReminder, forKey: k("soundIdleReminder"))
        d.set(enableBuiltInFilters, forKey: k("enableBuiltInFilters"))
        d.set(filterKeywords, forKey: k("filterKeywords"))
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        let d = defaults
        let k = key
        if d.object(forKey: k("launchAtLogin")) != nil { launchAtLogin = d.bool(forKey: k("launchAtLogin")) }
        if d.object(forKey: k("hoverToExpand")) != nil { hoverToExpand = d.bool(forKey: k("hoverToExpand")) }
        if d.object(forKey: k("hoverDelay")) != nil { hoverDelay = d.double(forKey: k("hoverDelay")) }
        if d.object(forKey: k("smartSuppression")) != nil { smartSuppression = d.bool(forKey: k("smartSuppression")) }
        if d.object(forKey: k("hideInFullscreen")) != nil { hideInFullscreen = d.bool(forKey: k("hideInFullscreen")) }
        if d.object(forKey: k("hideWhenNoActiveSessions")) != nil { hideWhenNoActiveSessions = d.bool(forKey: k("hideWhenNoActiveSessions")) }
        if d.object(forKey: k("autoCollapseOnMouseExit")) != nil { autoCollapseOnMouseExit = d.bool(forKey: k("autoCollapseOnMouseExit")) }
        if d.object(forKey: k("autoReminderDuration")) != nil { autoReminderDuration = d.double(forKey: k("autoReminderDuration")) }
        if d.object(forKey: k("dismissOnClickOutside")) != nil { dismissOnClickOutside = d.bool(forKey: k("dismissOnClickOutside")) }
        if d.object(forKey: k("agentTeamAutoExpand")) != nil { agentTeamAutoExpand = d.bool(forKey: k("agentTeamAutoExpand")) }
        if d.object(forKey: k("idleCleanupInterval")) != nil { idleCleanupInterval = d.double(forKey: k("idleCleanupInterval")) }
        if d.object(forKey: k("disableClickToJump")) != nil { disableClickToJump = d.bool(forKey: k("disableClickToJump")) }
        if let raw = d.string(forKey: k("displayMode")), let mode = DisplayMode(rawValue: raw) { displayMode = mode }
        if d.object(forKey: k("monitorSelection")) != nil { monitorSelection = d.integer(forKey: k("monitorSelection")) }
        if d.object(forKey: k("panelFontSize")) != nil { panelFontSize = CGFloat(d.double(forKey: k("panelFontSize"))) }
        if d.object(forKey: k("completionCardHeight")) != nil { completionCardHeight = CGFloat(d.double(forKey: k("completionCardHeight"))) }
        if d.object(forKey: k("maxPanelHeight")) != nil { maxPanelHeight = CGFloat(d.double(forKey: k("maxPanelHeight"))) }
        if d.object(forKey: k("maxPanelWidth")) != nil { maxPanelWidth = CGFloat(d.double(forKey: k("maxPanelWidth"))) }
        if d.object(forKey: k("notchWidthOffset")) != nil { notchWidthOffset = CGFloat(d.double(forKey: k("notchWidthOffset"))) }
        if d.object(forKey: k("notchHeightOffset")) != nil { notchHeightOffset = CGFloat(d.double(forKey: k("notchHeightOffset"))) }
        if d.object(forKey: k("showSubAgentDetails")) != nil { showSubAgentDetails = d.bool(forKey: k("showSubAgentDetails")) }
        if d.object(forKey: k("soundEnabled")) != nil { soundEnabled = d.bool(forKey: k("soundEnabled")) }
        if d.object(forKey: k("soundVolume")) != nil { soundVolume = d.float(forKey: k("soundVolume")) }
        if let v = d.string(forKey: k("soundSessionStart")) { soundSessionStart = v }
        if let v = d.string(forKey: k("soundSessionEnd")) { soundSessionEnd = v }
        if let v = d.string(forKey: k("soundConfirmationArrived")) { soundConfirmationArrived = v }
        if let v = d.string(forKey: k("soundConfirmationApproved")) { soundConfirmationApproved = v }
        if let v = d.string(forKey: k("soundConfirmationDenied")) { soundConfirmationDenied = v }
        if let v = d.string(forKey: k("soundError")) { soundError = v }
        if let v = d.string(forKey: k("soundReconnected")) { soundReconnected = v }
        if let v = d.string(forKey: k("soundIdleReminder")) { soundIdleReminder = v }
        if d.object(forKey: k("enableBuiltInFilters")) != nil { enableBuiltInFilters = d.bool(forKey: k("enableBuiltInFilters")) }
        if let arr = d.stringArray(forKey: k("filterKeywords")) { filterKeywords = arr }
    }
}
