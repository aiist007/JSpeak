@preconcurrency import AppKit
@preconcurrency import InputMethodKit

final class JSpeakInputController: IMKInputController {
    private var isRecording = false
    private let audio = AudioCapture()

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard event.type == .keyDown else {
            return super.handle(event, client: sender)
        }

        // Use F6 as a simple toggle for now.
        if event.keyCode == 107 {
            toggleRecording(client: sender)
            return true
        }

        return super.handle(event, client: sender)
    }

    private func toggleRecording(client sender: Any!) {
        if isRecording {
            isRecording = false
            let pcm = audio.stop()
            transcribeAndInsert(pcm: pcm, client: sender)
        } else {
            isRecording = true
            do {
                try audio.start()
            } catch {
                NSLog("JSpeak: failed to start audio: \(error)")
                isRecording = false
            }
        }
    }

    private func transcribeAndInsert(pcm: Data, client sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let transcriber = SpeechTranscriber()
            do {
                let result = try transcriber.transcribePCM16(pcmData: pcm, mixed: true)
                let actions = result["actions"] as? [[String: Any]] ?? []
                DispatchQueue.main.async {
                    applyActions(actions, client: client)
                }
            } catch {
                NSLog("JSpeak: transcription failed: \(error)")
            }
        }
    }
}

private func applyActions(_ actions: [[String: Any]], client: IMKTextInput) {
    for action in actions {
        guard let type = action["type"] as? String else { continue }
        switch type {
        case "insert":
            if let text = action["text"] as? String {
                client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            }
        case "delete_backward":
            let count = action["count"] as? Int ?? 1
            deleteBackward(client: client, count: count)
        case "set_composition":
            if let text = action["text"] as? String {
                client.setMarkedText(text, selectionRange: NSRange(location: text.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            }
        case "clear":
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        case "system_undo":
            break
        case "system_redo":
            break
        case "delete_backward_word":
            deleteBackwardWord(client: client)
        case "delete_backward_sentence":
            deleteBackwardSentence(client: client)
        default:
            break
        }
    }
}

private func deleteBackward(client: IMKTextInput, count: Int) {
    guard count > 0 else { return }
    let range = NSRange(location: NSNotFound, length: count)
    client.insertText("", replacementRange: range)
}

private func deleteBackwardWord(client: IMKTextInput) {
    deleteBackward(client: client, count: 1)
}

private func deleteBackwardSentence(client: IMKTextInput) {
    deleteBackward(client: client, count: 1)
}
