import Foundation

/// Hides desktop icons the honest way: Finder's own `CreateDesktop` pref.
/// Toggling it requires relaunching Finder (`killall Finder`) — Finder only
/// reads the key at launch. Swab reads the prior value first so Restore can
/// write back exactly what was there (including "no value at all").
enum DesktopIcons {
    /// nil means the key is absent, which Finder treats as `true`.
    static func readCreateDesktop() -> Bool? {
        let result = Shell.run("/usr/bin/defaults",
                               ["read", "com.apple.finder", "CreateDesktop"])
        guard result.status == 0 else { return nil }
        let value = result.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return !(value == "0" || value == "false" || value == "no")
    }

    static func hideIcons() {
        Shell.run("/usr/bin/defaults",
                  ["write", "com.apple.finder", "CreateDesktop", "-bool", "false"])
        relaunchFinder()
    }

    static func restore(_ snapshot: Snapshot.FinderSnapshot) {
        if snapshot.keyWasAbsent {
            Shell.run("/usr/bin/defaults",
                      ["delete", "com.apple.finder", "CreateDesktop"])
        } else {
            Shell.run("/usr/bin/defaults",
                      ["write", "com.apple.finder", "CreateDesktop",
                       "-bool", snapshot.createDesktop ? "true" : "false"])
        }
        relaunchFinder()
    }

    private static func relaunchFinder() {
        Shell.run("/usr/bin/killall", ["Finder"])
    }
}
