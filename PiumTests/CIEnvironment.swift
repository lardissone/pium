import Foundation

/// Whether this test run is on CI, for the handful of tests that need a real
/// Spotlight index and skip themselves where CI cannot supply one.
///
/// Not `ProcessInfo.processInfo.environment["CI"] != nil`: the scheme
/// declares `CI` as a test-action environment variable so that GitHub
/// Actions' own `CI=true` (an unrelated inherited shell variable, invisible
/// to the test host otherwise — `xcodebuild` does not forward its own
/// environment to a macOS test host by default) reaches this process. That
/// declaration means the key is always present, with an empty string once
/// there is nothing to resolve it to, so presence alone cannot tell a CI run
/// apart from a local one; the value has to be checked instead.
let isRunningOnCI = ProcessInfo.processInfo.environment["CI"] == "true"
