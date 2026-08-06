import Testing
import Foundation
@testable import Pium

@Suite("Process runner")
struct ProcessRunnerTests {
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

    private func request(
        _ executable: String,
        _ arguments: [String] = [],
        in directory: URL = URL(filePath: "/tmp"),
        timeoutSeconds: Int? = nil
    ) -> ExecutionRequest {
        ExecutionRequest(
            executable: URL(filePath: executable),
            arguments: arguments,
            workingDirectory: directory,
            environment: ["PATH": "/usr/bin:/bin"],
            timeoutSeconds: timeoutSeconds
        )
    }

    @Test func itReportsOutputAndTheExitCode() async {
        let outcome = await ProcessRunner().run(
            request("/bin/echo", ["hola"]), cancellation: .init()
        )
        #expect(outcome.ending == .exited(0))
        #expect(outcome.standardOutput == "hola\n")
        #expect(outcome.wasTruncated == false)
    }

    /// Past the cap the beginning is kept and reading continues, because a
    /// reader that stops draining blocks the child on its next write — a
    /// truncated output would become a hung command.
    @Test func outputPastTheCapKeepsTheBeginningAndStillFinishes() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // 200 KB, comfortably past the 64 KB cap.
        let url = try script("for i in $(seq 1 200000); do printf 'x'; done", in: directory)

        let outcome = await ProcessRunner().run(request(url.path, in: directory), cancellation: .init())
        #expect(outcome.ending == .exited(0))
        #expect(outcome.standardOutput.count == ProcessRunner.outputCap)
        #expect(outcome.standardOutput.allSatisfy { $0 == "x" })
        #expect(outcome.wasTruncated == true)
    }

    @Test func atimeoutEndsTheRunAsTimedOut() async throws {
        let outcome = await ProcessRunner().run(
            request("/bin/sleep", ["30"], timeoutSeconds: 1), cancellation: .init()
        )
        #expect(outcome.ending == .timedOut)
    }

    @Test func acancellationEndsTheRunAsCancelled() async throws {
        let cancellation = ProcessRunner.Cancellation()
        async let outcome = ProcessRunner().run(request("/bin/sleep", ["30"]), cancellation: cancellation)
        try await Task.sleep(for: .milliseconds(300))
        cancellation.cancel()
        #expect(await outcome.ending == .cancelled)
    }

    /// PRD §11: a user's cancellation is reported as cancelled, never as a
    /// failure, however the process actually died.
    @Test func acancelledRunIsNotReportedAsAFailure() async throws {
        let cancellation = ProcessRunner.Cancellation()
        async let outcome = ProcessRunner().run(request("/bin/sleep", ["30"]), cancellation: cancellation)
        try await Task.sleep(for: .milliseconds(300))
        cancellation.cancel()
        let ending = await outcome.ending
        #expect(ending != .exited(143))
        #expect(ending == .cancelled)
    }
}
