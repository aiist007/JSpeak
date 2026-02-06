import Foundation
import JSpeakPythonBridge

final class SpeechTranscriber {
    private let service: PythonSpeechService

    // Built-in prompt for better domain term recognition.
    // Keep it short-ish: Whisper prompts help with biasing, not full corpus injection.
    private static let defaultPrompt: String = {
        let s = """
Transcribe accurately. Keep punctuation and casing. Keep English terms exactly as written.
When mixing Chinese and English/numbers, add a half-width space between them.

Key domains: AI/ML, IT/Product, Web3/Crypto, Tesla/EV/Auto, Finance.

AI/ML (keep exactly):
LLM, RAG, embeddings, vector database, prompt engineering, initial_prompt
fine-tuning, RLHF, DPO, LoRA, QLoRA
Transformer, attention, MoE
inference, latency, throughput, quantization, FP16, BF16, int8, int4
PyTorch, JAX, ONNX
Whisper, MLX, MLX-Whisper, mlx_whisper

IT/Product (keep exactly):
OpenClaw, openclaw
Feishu, 飞书
OpenAI, Claude, Opus, Sonnet
Claude Opus, Claude Sonnet
Perplexity, Grok

Web3/Crypto (prefer standard CN terms; keep exactly):
Blockchain, DLT(分布式账本技术)
Bitcoin(BTC, 比特币), Ethereum(ETH, 以太坊)
PoW(工作量证明), PoS(权益证明), Validator(验证者)
EVM, Solidity, smart contract(智能合约), ABI
Gas, Gwei, nonce, mempool, finality
L2(二层网络), Rollup, ZK, ZKP, zk-SNARKs, zk-STARKs
DeFi(去中心化金融), DEX, AMM, Liquidity Pool(流动性池), slippage(滑点), Impermanent Loss(无常损失)
Airdrop(空投), NFT, Mint(铸造), Rug Pull(跑路/抽地毯), HODL, FOMO, FUD, MEV

Tesla/EV/Auto (keep exactly):
Tesla, Model 3, Model Y, Cybertruck
Supercharger, NACS, CCS, J1772
FSD, Autopilot, OTA, BMS
LFP, NMC, 4680, SOC, SOH
Wh/km, regenerative braking, heat pump, V2G
CAN bus, ECU, ADAS

Finance (keep exactly):
P&L, balance sheet, cash flow, free cash flow, FCF
EBIT, EBITDA, gross margin, operating margin, net margin
ROE, ROIC, EPS, guidance
valuation, market cap, enterprise value, EV/EBITDA, P/E, DCF
yield, duration, volatility, drawdown
CPI, PPI, PMI, GDP, Fed, FOMC
options, calls, puts, strike price, expiry, implied volatility, IV
futures, leverage, margin, liquidation
limit order, market order, stop loss, take profit

Common Chinese finance terms:
资产负债表，利润表，现金流量表，自由现金流，经营现金流，资本开支
市值，估值，溢价，折价，回撤，波动率，流动性，信用利差
"""
        return s
    }()

    private static func promptForASR() -> String {
        // Defensive: keep prompt size bounded.
        let maxChars = 2000
        if defaultPrompt.count <= maxChars { return defaultPrompt }
        return String(defaultPrompt.prefix(maxChars))
    }

    init(pythonPath: String? = nil, scriptPath: String? = nil) {
        let resolvedScript = Self.resolveScriptPath(override: scriptPath)
        let requirements = Self.resolveRequirementsPath()
        let wheelhouse = Self.resolveWheelhousePath()

        let resolvedPython: String
        let pythonEnv: [String: String]
        if let pythonPath {
            resolvedPython = pythonPath
            pythonEnv = [:]
        } else {
            // Create/use a venv so beta app does not depend on system site-packages.
            let resolved = (try? PythonRuntime.resolvedPython(requirementsPath: requirements, wheelhousePath: wheelhouse))
            resolvedPython = resolved?.pythonPath ?? "/usr/bin/python3"
            pythonEnv = resolved?.environment ?? [:]
        }

        let config = PythonSpeechService.Config(pythonPath: resolvedPython, scriptPath: resolvedScript, environment: pythonEnv)
        self.service = PythonSpeechService(config: config)
    }

    private static func resolveLocalModelPath() -> String? {
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("Models/whisper-medium").path
            if FileManager.default.fileExists(atPath: bundled) { return bundled }
        }

        // Dev runs (swift run): prefer local Assets model snapshot to avoid HF fetch.
        let cwd = FileManager.default.currentDirectoryPath
        let candidates = [
            cwd + "/Assets/Models/whisper-medium",
            cwd + "/JSpeak/Assets/Models/whisper-medium",
        ]
        for p in candidates {
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return nil
    }

    private static func resolveScriptPath(override: String?) -> String {
        if let override, override.hasPrefix("/") {
            return override
        }

        // Prefer bundled python service when running as an app.
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("Python/jsp_speech_service.py").path
            if FileManager.default.fileExists(atPath: bundled) { return bundled }
        }

        let candidates = [
            override,
            "Python/jsp_speech_service.py",
        ].compactMap { $0 }

        let cwd = FileManager.default.currentDirectoryPath
        for path in candidates {
            let abs = path.hasPrefix("/") ? path : cwd + "/" + path
            if FileManager.default.fileExists(atPath: abs) { return abs }
        }

        // Last resort
        return cwd + "/Python/jsp_speech_service.py"
    }

    private static func resolveRequirementsPath() -> String {
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("Python/requirements.txt").path
            if FileManager.default.fileExists(atPath: bundled) { return bundled }
        }
        let cwd = FileManager.default.currentDirectoryPath
        return cwd + "/Python/requirements.txt"
    }

    private static func resolveWheelhousePath() -> String? {
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("Wheelhouse").path
            if FileManager.default.fileExists(atPath: bundled) { return bundled }
        }
        return nil
    }

    func transcribePCM16(
        pcmData: Data,
        sampleRate: Int = 16000,
        mixed: Bool = true
    ) throws -> [String: Any] {
        let sessionId = UUID().uuidString
        var startParams: [String: String] = [
            "session_id": sessionId,
            "sample_rate_hz": String(sampleRate),
            "partial_interval_ms": "500",
            "model": "mlx-community/whisper-medium",
        ]

        if let modelPath = Self.resolveLocalModelPath() {
            startParams["model_path"] = modelPath
        }
        if mixed { startParams["mixed"] = "true" }
        startParams["prompt"] = Self.promptForASR()

        _ = try service.request(method: "stream_start", params: startParams, timeoutSeconds: 300)

        let b64 = pcmData.base64EncodedString()
        let pushParams: [String: String] = [
            "session_id": sessionId,
            "format": "pcm_s16le_b64",
            "audio_b64": b64,
        ]
        _ = try service.request(method: "stream_push", params: pushParams, timeoutSeconds: 300)

        let finalizeParams: [String: String] = ["session_id": sessionId]
        let finalize = try service.request(method: "stream_finalize", params: finalizeParams, timeoutSeconds: 300)
        return (finalize.result?.value as? [String: Any]) ?? [:]
    }

    func startStream(sampleRate: Int = 16000, mixed: Bool = true) throws -> String {
        let sessionId = UUID().uuidString
        var startParams: [String: String] = [
            "session_id": sessionId,
            "sample_rate_hz": String(sampleRate),
            // Keep partials responsive without starving finalize.
            "partial_interval_ms": "700",
            "max_partial_context_s": "8",
            "min_partial_speech_ms": "300",
            // Endpointing still matters if user pauses while holding Fn.
            "end_silence_ms": "260",
            "model": "mlx-community/whisper-medium",
        ]
        if let modelPath = Self.resolveLocalModelPath() {
            startParams["model_path"] = modelPath
        }
        if mixed { startParams["mixed"] = "true" }
        startParams["prompt"] = Self.promptForASR()

        _ = try service.request(method: "stream_start", params: startParams, timeoutSeconds: 300)
        return sessionId
    }

    func pushStream(sessionId: String, pcmChunk: Data) throws -> [String: Any] {
        let b64 = pcmChunk.base64EncodedString()
        let pushParams: [String: String] = [
            "session_id": sessionId,
            "format": "pcm_s16le_b64",
            "audio_b64": b64,
        ]
        let resp = try service.request(method: "stream_push", params: pushParams, timeoutSeconds: 30)
        return (resp.result?.value as? [String: Any]) ?? [:]
    }

    func finalizeStream(sessionId: String) throws -> [String: Any] {
        let finalize = try service.request(method: "stream_finalize", params: ["session_id": sessionId], timeoutSeconds: 120)
        return (finalize.result?.value as? [String: Any]) ?? [:]
    }

    // Preload python process + model so first dictation feels instant.
    func warmUp(mixed: Bool = true, sampleRate: Int = 16000) {
        DispatchQueue.global(qos: .utility).async {
            do {
                let sessionId = UUID().uuidString
                var startParams: [String: String] = [
                    "session_id": sessionId,
                    "sample_rate_hz": String(sampleRate),
                    "partial_interval_ms": "500",
                    "model": "mlx-community/whisper-medium",
                ]

                if let res = Bundle.main.resourceURL {
                    let bundled = res.appendingPathComponent("Models/whisper-medium").path
                    if FileManager.default.fileExists(atPath: bundled) {
                        startParams["model_path"] = bundled
                    }
                }
                if mixed { startParams["mixed"] = "true" }
                startParams["prompt"] = Self.promptForASR()

                _ = try self.service.request(method: "stream_start", params: startParams, timeoutSeconds: 300)
                _ = try self.service.request(method: "stream_finalize", params: ["session_id": sessionId], timeoutSeconds: 300)
            } catch {
                // Best-effort: keep startup silent.
            }
        }
    }
}
