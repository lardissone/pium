import Testing
import Foundation
@testable import Pium

/// The examples are what a reader copies and an agent imitates. One that does
/// not load would teach the wrong format.
@Suite("Example plugins")
struct ExamplePluginTests {
    @Test func everyShippedExampleIsValid() throws {
        let directory = try #require(
            Bundle.main.url(forResource: "ExamplePlugins", withExtension: nil)
        )
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(PluginLoader.manifestSuffix) }

        #expect(names.count >= 3, "The examples must ship in the bundle")

        for name in names {
            let data = try Data(contentsOf: directory.appending(path: name))
            switch ManifestDecoder.decode(data) {
            case .failure(let diagnostic):
                Issue.record("\(name) does not decode: \(diagnostic.message)")
            case .success(let manifest):
                if let diagnostic = ManifestValidator.validate(manifest) {
                    Issue.record("\(name) is invalid: \(diagnostic.message)")
                }
            }
        }
    }
}
