import AgentBoxProtocol
import Darwin
import Foundation

struct SpawnedPTY: Sendable {
    var master: Int32
    var pid: pid_t
}

/// Cria o PTY e lança o processo com `setsid` (líder de sessão e de grupo: `pgid == pid`) sem `fork` do processo
/// multithread do daemon: `posix_spawn` com `POSIX_SPAWN_SETSID`, o slave aberto por caminho (vira o tty de controle)
/// e `POSIX_SPAWN_CLOEXEC_DEFAULT` (nenhum fd do daemon vaza para o filho).
enum PTYSpawner {
    static func spawn(argv: [String], cwd: String, env: [String: String], cols: UInt16, rows: UInt16) throws(DaemonError) -> SpawnedPTY {
        guard let first = argv.first else { throw DaemonError(.badRequest, "argv must not be empty") }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw DaemonError(.spawnFailed, "cwd does not exist", errnoValue: ENOENT, path: cwd)
        }
        guard let executable = resolve(first, path: env["PATH"]) else {
            throw DaemonError(.spawnFailed, "executable not found", errnoValue: ENOENT, path: first)
        }

        var master: Int32 = -1
        var slave: Int32 = -1
        var name = [CChar](repeating: 0, count: 128)
        var size = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, &name, nil, &size) == 0 else {
            throw DaemonError(.spawnFailed, "openpty failed", errnoValue: errno)
        }
        var attributes = termios()
        if tcgetattr(master, &attributes) == 0 {
            attributes.c_iflag |= tcflag_t(IUTF8)
            _ = tcsetattr(master, TCSANOW, &attributes)
        }
        _ = fcntl(master, F_SETFD, FD_CLOEXEC)
        _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)

        var spawnAttributes: posix_spawnattr_t? = nil
        posix_spawnattr_init(&spawnAttributes)
        defer { posix_spawnattr_destroy(&spawnAttributes) }
        var defaults = sigset_t()
        sigfillset(&defaults)
        posix_spawnattr_setsigdefault(&spawnAttributes, &defaults)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigmask(&spawnAttributes, &mask)
        let flags = POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&spawnAttributes, Int16(flags))

        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, name, O_RDWR, 0)
        posix_spawn_file_actions_adddup2(&actions, 0, 1)
        posix_spawn_file_actions_adddup2(&actions, 0, 2)
        posix_spawn_file_actions_addchdir_np(&actions, cwd)

        var cArgv: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cArgv.append(nil)
        var cEnv: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") }
        cEnv.append(nil)
        defer {
            for pointer in cArgv { free(pointer) }
            for pointer in cEnv { free(pointer) }
        }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, executable, &actions, &spawnAttributes, cArgv, cEnv)
        close(slave)
        guard result == 0 else {
            close(master)
            throw DaemonError(.spawnFailed, "posix_spawn failed", errnoValue: result, path: executable)
        }
        return SpawnedPTY(master: master, pid: pid)
    }

    static func resolve(_ name: String, path: String?) -> String? {
        if name.contains("/") { return access(name, X_OK) == 0 ? name : nil }
        let search = path ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in search.split(separator: ":") {
            let candidate = "\(directory)/\(name)"
            if access(candidate, X_OK) == 0 { return candidate }
        }
        return nil
    }
}
