import Foundation
import JSpeakCore
import Dispatch

public final class PythonSpeechService {
    public struct Config: Sendable {
        public var pythonPath: String
        public var scriptPath: String
        public var environment: [String: String]

        public init(pythonPath: String = "/usr/bin/python3", scriptPath: String, environment: [String: String] = [:]) {
            self.pythonPath = pythonPath
            self.scriptPath = scriptPath
            self.environment = environment
        }
    }

    private let config: Config
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private let requestQueue = DispatchQueue(label: "JSpeakPythonBridge.PythonSpeechService.requestQueue")

    public init(config: Config) {
        self.config = config
    }

    public func start() throws {
        if process != nil { return }

        // print("[Swift] Spawning python process: \(config.pythonPath) \(config.scriptPath)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.pythonPath)
        // -u: unbuffered binary stdout/stderr, essential for IPC pipes to work immediately
        process.arguments = ["-u", config.scriptPath]

        if !config.environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(config.environment, uniquingKeysWith: { _, new in new })
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        // print("[Swift] Process started, pid=\(process.processIdentifier)")

        // Forward stderr to our stderr so we can see python logs/errors
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                // Prefix python logs so we spot them easily
                FileHandle.standardError.write(("[PYTHON] " + str).data(using: .utf8)!)
            }
        }

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
    }

    public func stop() {
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
    }

    public func ping(timeoutSeconds: TimeInterval = 2) throws -> String {
        let resp = try request(method: "ping", params: nil, timeoutSeconds: timeoutSeconds)
        if let dict = resp.result?.value as? [String: Any],
           let msg = dict["message"] as? String {
            return msg
        }
        return "ok (no message)"
    }

    public func capabilities(timeoutSeconds: TimeInterval = 2) throws -> [String: Any] {
        let resp = try request(method: "capabilities", params: nil, timeoutSeconds: timeoutSeconds)
        guard resp.ok else {
            throw NSError(domain: "JSpeakPythonBridge", code: 10, userInfo: [NSLocalizedDescriptionKey: resp.error ?? "capabilities failed"]) 
        }
        return (resp.result?.value as? [String: Any]) ?? [:]
    }

    public func request(method: String, params: [String: String]?, timeoutSeconds: TimeInterval) throws -> SpeechResponse {
        try requestQueue.sync {
            try requestUnlocked(method: method, params: params, timeoutSeconds: timeoutSeconds)
        }
    }

    private func requestUnlocked(method: String, params: [String: String]?, timeoutSeconds: TimeInterval) throws -> SpeechResponse {
        try start()

        guard let stdinHandle = stdinPipe?.fileHandleForWriting,
              let stdoutHandle = stdoutPipe?.fileHandleForReading
        else {
            throw NSError(domain: "JSpeakPythonBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Pipes not initialized"])
        }

        let id = UUID().uuidString
        let req = SpeechRequest(id: id, method: method, params: params)
        let data = try JSONLines.encodeLine(req)
        try stdinHandle.write(contentsOf: data)

        final class State: @unchecked Sendable {
            var buffer = Data()
            var response: SpeechResponse?
            var decodeError: Error?
        }

        let state = State()
        let semaphore = DispatchSemaphore(value: 0)

        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            state.buffer.append(data)

            while let newlineIndex = state.buffer.firstIndex(of: 0x0A) {
                let line = state.buffer.prefix(upTo: newlineIndex)
                let remainder = state.buffer.suffix(from: state.buffer.index(after: newlineIndex))
                state.buffer = Data(remainder)

                if line.isEmpty { continue }
                do {
                    let resp = try JSONLines.decodeLine(SpeechResponse.self, from: Data(line))
                    if resp.id == id {
                        state.response = resp
                        semaphore.signal()
                        return
                    }
                } catch {
                    state.decodeError = error
                    semaphore.signal()
                    return
                }
            }
        }

        let deadline = DispatchTime.now() + timeoutSeconds
        let waitResult = semaphore.wait(timeout: deadline)
        stdoutHandle.readabilityHandler = nil

        if let err = state.decodeError {
            throw err
        }
        if let resp = state.response {
            return resp
        }
        if waitResult == .timedOut {
            throw NSError(domain: "JSpeakPythonBridge", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timeout waiting for response"])
        }
        throw NSError(domain: "JSpeakPythonBridge", code: 3, userInfo: [NSLocalizedDescriptionKey: "No response"])
    }
}
