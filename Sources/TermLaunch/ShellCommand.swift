import Foundation

enum ShellCommand {
    /// `/bin/sh` runs the user's login shell (so PATH matches a normal terminal;
    /// the app itself is started by launchd with a minimal environment) and
    /// records the real exit code in a file.
    static func wrapper(run: String, exitFile: String, shell: String = loginShell()) -> String {
        let script = "\(quote(shell)) -l -c \(quote(run)); printf %s $? > \(quote(exitFile))"
        return "/bin/sh -c \(quote(script))"
    }

    static func loginShell() -> String {
        if let pw = getpwuid(getuid()), let sh = pw.pointee.pw_shell { return String(cString: sh) }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
