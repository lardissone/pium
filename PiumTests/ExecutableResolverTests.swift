import Testing
import Foundation
@testable import Pium

@Suite("Executable resolution")
struct ExecutableResolverTests {
    private func makeDirectory() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeScript(
        _ contents: String = "#!/bin/sh\nexit 0\n",
        named name: String,
        in directory: URL,
        executable: Bool = true
    ) throws -> URL {
        let url = directory.appending(path: name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        if executable {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path
            )
        }
        return url
    }

    private func quarantine(_ url: URL) throws {
        try url.path.withCString { path in
            try "0081;00000000;Safari;".withCString { value in
                guard setxattr(path, "com.apple.quarantine", value, strlen(value), 0, 0) == 0 else {
                    throw ExecutionFailure.spawnFailed(code: errno)
                }
            }
        }
    }

    private var resolver: ExecutableResolver {
        ExecutableResolver(searchPaths: ["/usr/bin", "/bin"])
    }

    @Test func abareNameIsFoundOnTheSearchPath() throws {
        let resolved = try resolver.resolve("echo", relativeTo: URL(filePath: "/tmp")).get()
        #expect(resolved.path == "/bin/echo")
    }

    /// First match wins, so the order of the path is the order of preference.
    @Test func theFirstMatchOnThePathWins() throws {
        let resolver = ExecutableResolver(searchPaths: ["/bin", "/usr/bin"])
        let resolved = try resolver.resolve("echo", relativeTo: URL(filePath: "/tmp")).get()
        #expect(resolved.path == "/bin/echo")
    }

    /// PRD §10.4: the error names what was looked for and where.
    @Test func anUnresolvableNameNamesTheSearchPath() {
        guard case .failure(let failure) = resolver.resolve(
            "definitely-not-a-real-tool", relativeTo: URL(filePath: "/tmp")
        ) else {
            Issue.record("An unresolvable executable must fail")
            return
        }
        #expect(
            failure == .executableNotFound(
                name: "definitely-not-a-real-tool", searched: ["/usr/bin", "/bin"]
            )
        )
    }

    @Test func anAbsolutePathIsUsedAsWritten() throws {
        let resolved = try resolver.resolve("/bin/echo", relativeTo: URL(filePath: "/tmp")).get()
        #expect(resolved.path == "/bin/echo")
    }

    @Test func amissingAbsolutePathIsReported() {
        guard case .failure(let failure) = resolver.resolve(
            "/bin/definitely-not-here", relativeTo: URL(filePath: "/tmp")
        ) else {
            Issue.record("A missing absolute path must fail")
            return
        }
        #expect(failure == .executableMissing(path: "/bin/definitely-not-here"))
    }

    @Test func arelativePathResolvesAgainstThePluginDirectory() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = try writeScript(named: "run.sh", in: directory)

        let resolved = try resolver.resolve("./run.sh", relativeTo: directory).get()
        #expect(resolved.resolvingSymlinksInPath() == script.resolvingSymlinksInPath())
    }

    /// Invoking an interpreter instead would run a different program than the
    /// shebang declares, so the missing bit is reported rather than worked around.
    @Test func ascriptWithoutItsExecuteBitIsReported() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = try writeScript(named: "run.sh", in: directory, executable: false)

        guard case .failure(let failure) = resolver.resolve("./run.sh", relativeTo: directory) else {
            Issue.record("A script without its execute bit must fail")
            return
        }
        #expect(failure == .executableNotExecutable(path: script.path))
    }

    /// PIUM-89: a file macOS quarantined is executable by its permission bits
    /// and still refused by the kernel, so `resolve` must catch it before a
    /// spawn attempt would surface only an unreadable errno.
    @Test func aquarantinedScriptIsReportedAsQuarantined() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = try writeScript(named: "run.sh", in: directory)
        try quarantine(script)

        guard case .failure(let failure) = resolver.resolve("./run.sh", relativeTo: directory) else {
            Issue.record("A quarantined script must fail")
            return
        }
        #expect(failure == .quarantined(path: script.path))
    }

    /// Proves the check discriminates rather than always firing: an ordinary
    /// script in the same directory, with no quarantine attribute, still
    /// resolves.
    @Test func anUnquarantinedScriptStillResolves() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = try writeScript(named: "run.sh", in: directory)

        let resolved = try resolver.resolve("./run.sh", relativeTo: directory).get()
        #expect(resolved.resolvingSymlinksInPath() == script.resolvingSymlinksInPath())
    }
}
