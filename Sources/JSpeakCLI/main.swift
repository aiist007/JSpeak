import Foundation
import JSpeakPythonBridge

// Helper for unbuffered stderr logging
func log(_ msg: String) {
    fputs("[CLI] \(msg)\n", stderr)
}

enum CLI {
    static func run() -> Int32 {
        let args = Array(CommandLine.arguments.dropFirst())
        log("Started with args: \(args)")

        if args.isEmpty {
            print("Usage: jspeak ping|capabilities [--service-path <path>] [--python-path <path>]")
            return 2
        }

        var servicePath = "Python/jsp_speech_service.py"
        // Default to the homebrew python we found, or fallback to /usr/bin/python3
        var pythonPath = "/opt/homebrew/opt/python@3.14/bin/python3.14" 
        
        if !FileManager.default.fileExists(atPath: pythonPath) {
             pythonPath = "/usr/bin/python3"
        }

        var idx = 0
        while idx < args.count {
            if args[idx] == "--service-path", idx + 1 < args.count {
                servicePath = args[idx + 1]
                idx += 2
                continue
            }
            if args[idx] == "--python-path", idx + 1 < args.count {
                pythonPath = args[idx + 1]
                idx += 2
                continue
            }
            break
        }

        let remaining = Array(args.suffix(from: idx))
        guard let command = remaining.first else {
            log("Missing command")
            return 2
        }
        if command != "ping" && command != "capabilities" {
            log("Unknown command: \(command)")
            return 2
        }
        
        // Resolve absolute path for service script
        let currentDir = FileManager.default.currentDirectoryPath
        let absServicePath = servicePath.hasPrefix("/") ? servicePath : currentDir + "/" + servicePath
        
        log("Using Python: \(pythonPath)")
        log("Using Script: \(absServicePath)")

        do {
            let config = PythonSpeechService.Config(pythonPath: pythonPath, scriptPath: absServicePath)
            let service = PythonSpeechService(config: config)
            if command == "ping" {
                log("Sending ping...")
                let message = try service.ping(timeoutSeconds: 5)
                print("pong: \(message)")
            } else if command == "capabilities" {
                log("Fetching capabilities...")
                let caps = try service.capabilities(timeoutSeconds: 5)
                let data = try JSONSerialization.data(withJSONObject: caps, options: [.prettyPrinted, .sortedKeys])
                print(String(data: data, encoding: .utf8) ?? "{}")
            }
            service.stop()
            return 0
        } catch {
            fputs("Error: \(error)\n", stderr)
            return 1
        }
    }
}

exit(CLI.run())
