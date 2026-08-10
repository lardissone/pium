import Foundation

/// What a HUD shows while a run is still going, as opposed to `HUDPresentation`'s
/// account of how one ended.
///
/// It carries no duration: a running HUD lives exactly as long as the run
/// does, which `HUDController` learns about by being told the run finished —
/// not by a timer counting down from a guess. Forcing this through
/// `HUDPresentation` would mean giving it a `duration` of infinity, which is
/// not what that field means.
///
/// It also carries no `PluginOutputMode`: `silent` describes the command's
/// output, not whether Pium admits it started something (PIUM-106).
struct RunningPresentation: Equatable, Sendable {
    let pluginName: String
    /// The run's own start time, so elapsed time is measured from when the
    /// run began rather than from whenever the HUD happens to appear.
    let startedAt: Date
}
