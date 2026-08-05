import Foundation

/// The app's identity, in one place.
///
/// The bundle identifier is duplicated by necessity in `project.yml` (the build
/// setting), `Resources/Info.plist` (via that setting), and `justfile` (the log
/// predicates and `tccutil` scopes). Drift between them is not a cosmetic
/// problem: the identifier is what TCC keys the Accessibility and Input
/// Monitoring grants to, and what `SMAppService` keys the login item to, so a
/// mismatch silently strands both. `just verify-identity` compares the copies.
public enum AppIdentity {
    public static let bundleIdentifier = "jp.kaizudenki.noBudsMusic"

    /// `os.Logger` subsystem. Kept equal to the bundle identifier so
    /// `log stream --predicate 'subsystem == "<bundle id>"'` works.
    public static let logSubsystem = bundleIdentifier

    /// URL scheme registered in `Info.plist`.
    public static let urlScheme = "nobudsmusic"
}
