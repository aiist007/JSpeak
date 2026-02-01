import Foundation

enum PythonRuntime {
    struct Resolved {
        var pythonPath: String
        var environment: [String: String]
    }

    private struct Bootstrap {
        var pythonPath: String
        var environment: [String: String]
    }

    static func resolvedPython(requirementsPath: String, wheelhousePath: String?) throws -> Resolved {
        let bootstrap = try resolvedBootstrap()

        let fm = FileManager.default
        let support = try appSupportDirectory()
        let venvDir = support.appendingPathComponent("venv", isDirectory: true)
        let venvPython = venvDir.appendingPathComponent("bin/python3", isDirectory: false)

        if fm.fileExists(atPath: venvPython.path) {
            return Resolved(pythonPath: venvPython.path, environment: [:])
        }

        try fm.createDirectory(at: support, withIntermediateDirectories: true)

        try run([bootstrap.pythonPath, "-m", "venv", venvDir.path], env: bootstrap.environment, timeout: 600)

        // Make sure pip exists in the venv even on minimal python installs.
        try run([venvPython.path, "-m", "ensurepip", "--upgrade"], env: [:], timeout: 600)

        if let wheelhousePath, fm.fileExists(atPath: wheelhousePath) {
            // Offline install from bundled wheelhouse
            try run(
                [
                    venvPython.path,
                    "-m",
                    "pip",
                    "install",
                    "--no-index",
                    "--find-links",
                    wheelhousePath,
                    "-r",
                    requirementsPath,
                    "--upgrade",
                ],
                env: [:],
                timeout: 1800
            )
        } else {
            // Online install
            try run([venvPython.path, "-m", "pip", "install", "-r", requirementsPath, "--upgrade"], env: [:], timeout: 1800)
        }

        return Resolved(pythonPath: venvPython.path, environment: [:])
    }

    private static func resolvedBootstrap() throws -> Bootstrap {
        let fm = FileManager.default

        if let env = ProcessInfo.processInfo.environment["JSPEAK_PYTHON"], !env.isEmpty {
            return Bootstrap(pythonPath: env, environment: [:])
        }

        // Prefer a bundled python runtime if present (true copy-only distribution).
        if let bundled = bundledPythonRuntime() {
            return Bootstrap(pythonPath: bundled.pythonPath, environment: bundled.environment)
        }

        let candidates = [
            "/opt/homebrew/opt/python@3.14/bin/python3.14",
            "/opt/homebrew/bin/python3",
            "/usr/bin/python3",
        ]
        guard let py = candidates.first(where: { fm.fileExists(atPath: $0) }) else {
            throw NSError(
                domain: "JSpeakAgent",
                code: 100,
                userInfo: [NSLocalizedDescriptionKey: "No python interpreter found. Install python3 or set JSPEAK_PYTHON."]
            )
        }
        return Bootstrap(pythonPath: py, environment: [:])
    }

    private static func bundledPythonRuntime() -> Resolved? {
        guard let res = Bundle.main.resourceURL else { return nil }
        let runtimeRoot = res.appendingPathComponent("PythonRuntime", isDirectory: true)
        let py = runtimeRoot.appendingPathComponent("bin/python3", isDirectory: false)
        if !FileManager.default.fileExists(atPath: py.path) { return nil }

        // python-build-standalone and similar layouts work best when PYTHONHOME points at runtime root.
        // Also disable user site-packages to keep execution deterministic.
        return Resolved(
            pythonPath: py.path,
            environment: [
                "PYTHONHOME": runtimeRoot.path,
                "PYTHONNOUSERSITE": "1",
                "PYTHONUTF8": "1",
            ]
        )
    }

    private static func appSupportDirectory() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("JSpeak", isDirectory: true)
    }

    private static func run(_ argv: [String], env: [String: String], timeout: TimeInterval) throws {
        let cmd = argv.joined(separator: " ")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: argv[0])
        process.arguments = Array(argv.dropFirst())

        if !env.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(env, uniquingKeysWith: { _, new in new })
        }

        let errPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        if process.isRunning {
            process.terminate()
            throw NSError(
                domain: "JSpeakAgent",
                code: 101,
                userInfo: [NSLocalizedDescriptionKey: "Timeout running: \(cmd)"]
            )
        }

        if process.terminationStatus != 0 {
            let err = errPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: err, encoding: .utf8) ?? ""
            throw NSError(
                domain: "JSpeakAgent",
                code: 102,
                userInfo: [NSLocalizedDescriptionKey: "Command failed: \(cmd)\n\(msg)"]
            )
        }
    }
}
