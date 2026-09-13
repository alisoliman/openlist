import Foundation

func check(_ condition: @autoclosure () -> Bool, _ description: String) {
    precondition(condition(), description)
}
check(AppGroup.identifier == "Y5UE64R7TQ.solimanali.openlist.dev", "Dev never names the production App Group")
check(ReviewSession.identifier == nil, "Normal Dev is not a disposable review session")
let root = AppGroup.containerURL!
check(root.pathComponents.contains("Openlist Dev"), "Ad-hoc Dev has a named private data root")
check(StoreLocation.storeURL.path.hasPrefix(root.path + "/"), "Dev database is under its own root")
check(MediaStore.shared.url(for: "isolation-check.txt").path.hasPrefix(root.path + "/"), "Dev media is under its own root")
let key = "dev-isolation-check-\(UUID().uuidString)"
ReviewSession.defaults.set("dev-only", forKey: key)
defer { ReviewSession.defaults.removeObject(forKey: key) }
check(UserDefaults(suiteName: "solimanali.openlist.dev")?.string(forKey: key) == "dev-only", "Dev uses its distinct preferences suite")
check(UserDefaults(suiteName: "solimanali.openlist")?.object(forKey: key) == nil, "Dev preferences do not write production defaults")
let settingsSuite = "solimanali.openlist.dev-check.\(UUID().uuidString)"
let settingsDefaults = UserDefaults(suiteName: settingsSuite)!
defer { settingsDefaults.removePersistentDomain(forName: settingsSuite) }
let settings = AppSettings(defaults: settingsDefaults)
check(settings.mcpPort == 45874 && !settings.mcpEnabled && !settings.mcpAllowsWrites, "Dev MCP is opt-in on a distinct default port")
check(!settings.quickCaptureHotKeyEnabled, "Dev does not take production's global shortcut by default")
print("Passed 9 development storage, preference and coexistence checks")
