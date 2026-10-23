import Foundation
import Observation
import AVFoundation
import Speech

@MainActor @Observable final class DictationService {
    var transcript = ""
    var recording = false
    var preparing = false
    var finishing = false
    var status = "English (UK) · on-device dictation. Review and edit before using the text."
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var tapped = false
    private var generation = UUID()
    private var recordingLimit: Task<Void,Never>?
    private var finishTimeout: Task<Void,Never>?
    func start() async {
        guard !recording, !preparing, !finishing else { return }
        cancel(clear:false)
        let token = UUID(); generation = token; preparing = true
        defer { if generation == token { preparing = false } }
        let speech = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning:$0) } }
        guard generation == token else { return }
        guard speech == .authorized else {
            status = "Speech permission is unavailable. Enable 3PO in Privacy & Security → Speech Recognition, or keep typing."
            return
        }
        let microphone = await AVCaptureDevice.requestAccess(for:.audio)
        guard generation == token else { return }
        guard microphone else {
            status = "Microphone permission is denied. Enable 3PO in Privacy & Security → Microphone, or keep typing."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale:Locale(identifier:"en-GB")), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            status = "On-device English (UK) transcription is unavailable on this Mac. Typed input still works; no cloud transcription is used."
            return
        }
        let audio = AVAudioEngine(), input = audio.inputNode, format = audio.inputNode.outputFormat(forBus:0)
        guard format.sampleRate > 0, format.channelCount > 0 else { status = "No usable microphone input. Choose an input in Sound settings or keep typing."; return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
        self.request = request; engine = audio; transcript = ""
        input.installTap(onBus:0,bufferSize:1024,format:format) { buffer,_ in request.append(buffer) }
        tapped = true
        do { audio.prepare(); try audio.start() }
        catch { cancel(clear:false); status = "Microphone could not start. Typed input still works."; return }
        recording = true; status = "Listening on device… Up to one minute; Stop when finished. Nothing is sent automatically."
        recordingLimit = Task { [weak self] in
            do { try await Task.sleep(for:.seconds(60)) } catch { return }
            guard let self, self.generation == token, self.recording else { return }
            self.stop()
        }
        recognition = recognizer.recognitionTask(with:request) { [weak self] result,error in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if let result { self.transcript = result.bestTranscription.formattedString }
                if result?.isFinal == true || error != nil {
                    self.finishTimeout?.cancel(); self.finishTimeout = nil
                    self.releaseAudio(); self.recognition = nil; self.request = nil; self.finishing = false
                    self.generation = UUID() // Late callbacks cannot overwrite subsequent user edits.
                    self.status = error == nil ? "Review and edit the transcript, then use it as your message." : "Transcription stopped or assets were unavailable. Review any captured text, or keep typing."
                }
            }
        }
    }
    private func releaseAudio() {
        recordingLimit?.cancel(); recordingLimit = nil
        engine?.stop()
        if tapped { engine?.inputNode.removeTap(onBus:0); tapped = false }
        engine = nil; recording = false
    }
    func stop() {
        guard recording else { return }
        let token = generation
        releaseAudio(); finishing = true; request?.endAudio(); recognition?.finish()
        status = "Finishing transcription…"
        finishTimeout = Task { [weak self] in
            do { try await Task.sleep(for:.seconds(3)) } catch { return }
            guard let self, self.generation == token, self.finishing else { return }
            self.generation = UUID(); self.recognition?.cancel(); self.recognition = nil; self.request = nil; self.finishing = false
            self.status = "Final transcription did not arrive. Review and edit the captured text, or keep typing."
        }
    }
    func cancel(clear: Bool = true) {
        generation = UUID(); preparing = false; finishing = false
        finishTimeout?.cancel(); finishTimeout = nil
        releaseAudio(); recognition?.cancel(); recognition = nil; request = nil
        if clear { transcript = "" }
        status = "Dictation cancelled. Typed input still works."
    }
}
