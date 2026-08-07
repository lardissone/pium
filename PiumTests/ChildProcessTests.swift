import Testing
import Foundation
@testable import Pium

@Suite("Child process")
struct ChildProcessTests {
    private func makeDirectory() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func script(_ body: String, in directory: URL) throws -> URL {
        let url = directory.appending(path: "script.sh")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func spawn(
        _ executable: String,
        _ arguments: [String] = [],
        in directory: URL = URL(filePath: "/tmp"),
        environment: [String: String] = ["PATH": "/usr/bin:/bin"]
    ) throws -> ChildProcess {
        try ChildProcess.spawn(
            executable: URL(filePath: executable),
            arguments: arguments,
            workingDirectory: directory,
            environment: environment
        )
    }

    @Test func itCapturesStandardOutputAndAZeroExit() throws {
        let child = try spawn("/bin/echo", ["hola"])
        let output = child.standardOutput.readDataToEndOfFile()
        #expect(child.waitForExit() == .exited(0))
        #expect(String(decoding: output, as: UTF8.self) == "hola\n")
    }

    @Test func itReportsANonZeroExit() throws {
        let child = try spawn("/usr/bin/false")
        #expect(child.waitForExit() == .exited(1))
    }

    @Test func itCapturesStandardErrorSeparately() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try script("echo out; echo err >&2", in: directory)

        let child = try spawn(url.path, in: directory)
        let out = child.standardOutput.readDataToEndOfFile()
        let err = child.standardError.readDataToEndOfFile()
        _ = child.waitForExit()
        #expect(String(decoding: out, as: UTF8.self) == "out\n")
        #expect(String(decoding: err, as: UTF8.self) == "err\n")
    }

    /// A plugin reads end-of-file, not whatever Pium is reading from. Pium's
    /// own stdin is replaced by a pipe for the length of this test so that an
    /// inherited descriptor would be something the child can tell apart from
    /// `/dev/null` — and so that the assertion holds wherever this suite runs,
    /// rather than only where the host's stdin happens to differ.
    ///
    /// The fixture compares descriptors instead of reading, because a child
    /// that inherited this pipe would block on a read until the test process
    /// itself ended.
    @Test func achildReadsFromDevNullRatherThanPiumsOwnStandardInput() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try script(
            "if [ /dev/fd/0 -ef /dev/null ]; then echo devnull; else echo inherited; fi",
            in: directory
        )

        var ends: [Int32] = [0, 0]
        try #require(pipe(&ends) == 0)
        let saved = dup(STDIN_FILENO)
        dup2(ends[0], STDIN_FILENO)
        defer {
            dup2(saved, STDIN_FILENO)
            close(saved)
            close(ends[0])
            close(ends[1])
        }

        let child = try spawn(url.path, in: directory)
        let output = String(decoding: child.standardOutput.readDataToEndOfFile(), as: UTF8.self)
        _ = child.waitForExit()
        #expect(output == "devnull\n")
    }

    @Test func theEnvironmentReachesTheChild() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try script("echo \"$PIUM_SECRET_TOKEN\"", in: directory)

        let child = try spawn(
            url.path,
            in: directory,
            environment: ["PATH": "/usr/bin:/bin", "PIUM_SECRET_TOKEN": "hunter2"]
        )
        let output = child.standardOutput.readDataToEndOfFile()
        _ = child.waitForExit()
        #expect(String(decoding: output, as: UTF8.self) == "hunter2\n")
    }

    @Test func theWorkingDirectoryIsTheOneGiven() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try script("pwd", in: directory)

        let child = try spawn(url.path, in: directory)
        let output = String(decoding: child.standardOutput.readDataToEndOfFile(), as: UTF8.self)
        _ = child.waitForExit()
        // Compared as `.path` strings, not as `URL`s: `pwd` reports the kernel's
        // physical path (through /private), and resolvingSymlinksInPath() collapses
        // that back to the /var alias `directory` already uses — the two land on
        // the same `.path`. `URL` equality still disagrees, because one side keeps
        // `hasDirectoryPath == true` from `directory`'s own construction and the
        // other does not; that flag, not the path, is what differs.
        #expect(
            URL(filePath: output.trimmingCharacters(in: .newlines)).resolvingSymlinksInPath().path
                == directory.resolvingSymlinksInPath().path
        )
    }

    @Test func achildIsTheLeaderOfItsOwnGroup() throws {
        let child = try spawn("/bin/sleep", ["30"])
        #expect(getpgid(child.pid) == child.pid)
        child.signalGroup(SIGKILL)
        _ = child.waitForExit()
    }

    /// PIUM-DOC-2 §11: "child processes survive cancellation" is a named risk,
    /// and a dedicated process group is its mitigation. This is the test that
    /// proves the group was assembled, not merely requested.
    @Test func signallingTheGroupReachesAGrandchild() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appending(path: "grandchild.pid")
        let url = try script("sleep 60 &\necho $! > \(pidFile.path)\nsleep 60", in: directory)

        let child = try spawn(url.path, in: directory)

        // The grandchild's pid appears only once the shell has forked it.
        var grandchild: pid_t?
        for _ in 0..<50 where grandchild == nil {
            usleep(100_000)
            if let text = try? String(contentsOf: pidFile, encoding: .utf8) {
                grandchild = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        let pid = try #require(grandchild, "The script never reported its grandchild")
        #expect(kill(pid, 0) == 0, "The grandchild should be running before the signal")

        child.signalGroup(SIGKILL)
        _ = child.waitForExit()

        var reaped = false
        for _ in 0..<50 where !reaped {
            usleep(100_000)
            reaped = kill(pid, 0) != 0
        }
        #expect(reaped, "The grandchild outlived a signal sent to its process group")
    }

    @Test func amissingExecutableFailsToSpawn() {
        #expect(throws: ExecutionFailure.self) {
            try spawn("/bin/definitely-not-here")
        }
    }
}
