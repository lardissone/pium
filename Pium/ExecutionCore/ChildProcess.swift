import Darwin
import Foundation

/// One spawned command, in a process group of its own.
///
/// `posix_spawn` rather than Foundation's `Process`: `Process` exposes no way to
/// put the child in a new process group, so cancelling a plugin would leave its
/// descendants running — PIUM-DOC-2 §11's named risk. `POSIX_SPAWN_SETPGROUP`
/// with a group of 0 makes the child its own group leader, which is what lets a
/// signal sent to `-pid` reach everything it started.
///
/// No shell is involved anywhere: the executable and its arguments are handed to
/// the kernel as an `argv` array.
final class ChildProcess: @unchecked Sendable {
    enum Ending: Sendable, Equatable {
        case exited(Int32)
        case signalled(Int32)
    }

    let pid: pid_t
    let standardOutput: FileHandle
    let standardError: FileHandle

    private init(pid: pid_t, standardOutput: FileHandle, standardError: FileHandle) {
        self.pid = pid
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    static func spawn(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String]
    ) throws -> ChildProcess {
        var outPipe: [Int32] = [0, 0]
        guard pipe(&outPipe) == 0 else {
            throw ExecutionFailure.spawnFailed(code: errno)
        }
        var errPipe: [Int32] = [0, 0]
        guard pipe(&errPipe) == 0 else {
            let code = errno
            close(outPipe[0])
            close(outPipe[1])
            throw ExecutionFailure.spawnFailed(code: code)
        }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        // Nothing feeds a plugin's stdin, so it reads end-of-file rather than
        // whatever Pium's own stdin happens to be. Inherited, a command that
        // reads stdin blocks forever on a terminal build, and a blocked run
        // holds the single execution slot with no way to release it. The three
        // redirections claim descriptors 0, 1 and 2 respectively, so the order
        // the file actions apply in leaves each of them standing.
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], STDERR_FILENO)
        // The child holds no copy of the read ends; otherwise the reader never
        // sees EOF, because a descriptor it does not know about keeps the pipe
        // open.
        posix_spawn_file_actions_addclose(&actions, outPipe[0])
        posix_spawn_file_actions_addclose(&actions, errPipe[0])
        // `adddup2` leaves the original write-end fd open alongside its dup at
        // stdout/stderr; without closing it explicitly the child (and anything
        // it forks before the parent's own copy closes) inherits both.
        posix_spawn_file_actions_addclose(&actions, outPipe[1])
        posix_spawn_file_actions_addclose(&actions, errPipe[1])
        posix_spawn_file_actions_addchdir(&actions, workingDirectory.path)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)

        // `argv[0]` is the program's own name, as every program expects.
        var argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        var envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }

        var pid: pid_t = 0
        let code = posix_spawn(&pid, executable.path, &actions, &attributes, &argv, &envp)

        // The parent's copies of the write ends close here, so the reader sees
        // EOF when the child exits rather than blocking forever.
        close(outPipe[1])
        close(errPipe[1])

        guard code == 0 else {
            close(outPipe[0])
            close(errPipe[0])
            throw ExecutionFailure.spawnFailed(code: code)
        }

        return ChildProcess(
            pid: pid,
            standardOutput: FileHandle(fileDescriptor: outPipe[0], closeOnDealloc: true),
            standardError: FileHandle(fileDescriptor: errPipe[0], closeOnDealloc: true)
        )
    }

    /// Signals the whole group, which is the child and everything it started.
    func signalGroup(_ signal: Int32) {
        kill(-pid, signal)
    }

    /// Blocks until the child is reaped. Callers run this off the main actor.
    func waitForExit() -> Ending {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR { continue }
        if status & 0x7f == 0 {
            return .exited((status >> 8) & 0xff)
        }
        return .signalled(status & 0x7f)
    }
}
