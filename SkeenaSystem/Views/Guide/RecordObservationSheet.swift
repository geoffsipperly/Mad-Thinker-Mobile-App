// Bend Fly Shop

import CoreLocation
import SwiftUI

// MARK: - DarkTextEditor (UIViewRepresentable for reliable dark background)

private struct DarkTextEditor: UIViewRepresentable {
  @Binding var text: String

  func makeUIView(context: Context) -> UITextView {
    let tv = UITextView()
    tv.backgroundColor = UIColor.white.withAlphaComponent(0.08)
    tv.textColor = .white
    tv.font = UIFont.preferredFont(forTextStyle: .body)
    tv.isEditable = true
    tv.isScrollEnabled = true
    tv.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
    tv.delegate = context.coordinator
    tv.layer.cornerRadius = 12
    tv.clipsToBounds = true
    return tv
  }

  func updateUIView(_ uiView: UITextView, context: Context) {
    if uiView.text != text {
      uiView.text = text
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

  final class Coordinator: NSObject, UITextViewDelegate {
    var text: Binding<String>
    init(text: Binding<String>) { self.text = text }
    func textViewDidChange(_ textView: UITextView) {
      text.wrappedValue = textView.text
    }
  }
}

// MARK: - RecordObservationSheet

struct RecordObservationSheet: View {
  @Environment(\.dismiss) private var dismiss
  let onSaved: (Observation) -> Void

  @StateObject private var recorder = SpeechRecorder(maxDuration: 60)

  init(onSaved: @escaping (Observation) -> Void) {
    self.onSaved = onSaved
  }

  @State private var isStarting = false
  @State private var errorMessage: String?

  @State private var remainingSeconds: Int = 60
  @State private var countdownTimer: Timer?
  @State private var isFlashingWarning: Bool = false
  @State private var transcriptSnapshot: String = ""
  @State private var hasRecordedAudio: Bool = false

  var body: some View {
    NavigationView {
      VStack(spacing: 16) {
        Text("Record a field observation")
          .font(.headline)
          .foregroundColor(.white)
          .multilineTextAlignment(.center)
          .padding(.top, 8)

        // MARK: Recording controls

        HStack(spacing: 24) {
          // Main record / pause / resume button
          ZStack {
            Circle()
              .strokeBorder(Color.white.opacity(0.35), lineWidth: 2)
              .frame(width: 120, height: 120)

            Circle()
              .fill(recorder.isRecording && !recorder.isPaused
                ? Color.red.opacity(0.7)
                : Color.white.opacity(0.15))
              .frame(width: 100, height: 100)

            Image(systemName: micButtonIcon)
              .font(.system(size: 36, weight: .bold))
              .foregroundColor(.white)
          }
          .onTapGesture { toggleRecording() }

          // Stop button – visible while recording (active or paused)
          if recorder.isRecording {
            ZStack {
              Circle()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 2)
                .frame(width: 64, height: 64)

              Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 52, height: 52)

              Image(systemName: "stop.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.red)
            }
            .onTapGesture { stopRecording() }
          }
        }
        .padding(.vertical, 8)

        // Countdown
        Text(String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60))
          .font(.headline)
          .foregroundColor(timerColor)
          .opacity(timerOpacity)

        // MARK: Transcript area

        ZStack {
          // Live transcript (visible while recording or before first recording)
          ScrollViewReader { proxy in
            ScrollView {
              VStack(alignment: .leading, spacing: 0) {
                Text(
                  transcriptSnapshot.isEmpty
                    ? "Transcript will appear here as you speak…"
                    : transcriptSnapshot
                )
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)

                Color.clear
                  .frame(height: 1)
                  .id("TranscriptBottom")
              }
            }
            .onChange(of: recorder.partialTranscript) { newValue in
              if !newValue.isEmpty {
                transcriptSnapshot = newValue
              }
              withAnimation {
                proxy.scrollTo("TranscriptBottom", anchor: .bottom)
              }
            }
            .frame(maxHeight: 360)
          }
          .opacity(!recorder.isRecording && hasRecordedAudio ? 0 : 1)

          // Editable transcript after recording stops
          if !recorder.isRecording && hasRecordedAudio {
            VStack(alignment: .leading, spacing: 4) {
              Text("Tap to edit transcript")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
              DarkTextEditor(text: $transcriptSnapshot)
                .frame(maxHeight: 340)
            }
            .frame(maxHeight: 360)
          }
        }

        if let error = errorMessage {
          Text(error)
            .font(.footnote)
            .foregroundColor(.red)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }

        Spacer()

        // MARK: Action buttons

        HStack {
          Button("Cancel") {
            stopRecording()
            dismiss()
          }
          .frame(maxWidth: .infinity)
          .padding()
          .background(Color.white.opacity(0.12))
          .cornerRadius(12)
          .foregroundColor(.white)

          Button("Save") {
            saveObservation()
          }
          .frame(maxWidth: .infinity)
          .padding()
          .background(Color.blue)
          .cornerRadius(12)
          .foregroundColor(.white)
          .disabled(recorder.currentTempURL() == nil)
        }
      }
      .padding()
      .background(Color.black.ignoresSafeArea())
      .navigationBarHidden(true)
    }
    .onAppear {
      LocationHelper.shared.request()
    }
  }

  // MARK: - Helpers

  private var micButtonIcon: String {
    if !recorder.isRecording {
      return "mic.fill"
    } else if recorder.isPaused {
      return "play.fill"
    } else {
      return "pause.fill"
    }
  }

  private var timerColor: Color {
    recorder.isRecording && remainingSeconds <= 10 ? .red : .white
  }

  private var timerOpacity: Double {
    (recorder.isRecording && remainingSeconds <= 10 && isFlashingWarning) ? 0.3 : 1.0
  }

  // MARK: - Recording controls

  private func toggleRecording() {
    if recorder.isRecording {
      if recorder.isPaused {
        recorder.resume()
        startCountdown()
      } else {
        recorder.pause()
        pauseCountdown()
      }
    } else {
      isStarting = true
      errorMessage = nil

      Task {
        do {
          try await recorder.start()

          await MainActor.run {
            hasRecordedAudio = true
            remainingSeconds = 60
            startCountdown()
          }
        } catch {
          await MainActor.run {
            errorMessage = error.localizedDescription
            stopCountdown()
          }
        }

        await MainActor.run {
          isStarting = false
        }
      }
    }
  }

  private func stopRecording() {
    recorder.stop()
    stopCountdown()
  }

  // MARK: - Timer

  private func startCountdown() {
    countdownTimer?.invalidate()
    isFlashingWarning = false

    countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
      if !recorder.isRecording {
        stopCountdown()
        return
      }

      if remainingSeconds > 0 {
        remainingSeconds -= 1
      }

      if remainingSeconds <= 10 && remainingSeconds > 0 {
        isFlashingWarning.toggle()
      } else {
        isFlashingWarning = false
      }

      if remainingSeconds <= 0 {
        stopCountdown()
        recorder.stop()
      }
    }

    RunLoop.main.add(countdownTimer!, forMode: .common)
  }

  private func pauseCountdown() {
    countdownTimer?.invalidate()
    countdownTimer = nil
    isFlashingWarning = false
  }

  private func stopCountdown() {
    countdownTimer?.invalidate()
    countdownTimer = nil
    remainingSeconds = 60
    isFlashingWarning = false
  }

  // MARK: - Save

  private func saveObservation() {
    stopRecording()

    guard let tempURL = recorder.currentTempURL() else {
      errorMessage = "No audio recorded"
      return
    }

    let duration = recorder.totalDurationSec()
    let location = LocationHelper.shared.latestLocation

    // Persist audio via VoiceNoteStore (reuses existing storage)
    let note = VoiceNoteStore.shared.addNew(
      audioTempURL: tempURL,
      transcript: transcriptSnapshot,
      language: recorder.languageCode,
      onDevice: recorder.onDeviceRecognition,
      sampleRate: recorder.sampleRate,
      location: location,
      duration: duration
    )

    // Create observation record
    let observation = Observation(
      id: UUID(),
      clientId: UUID(),
      createdAt: Date(),
      uploadedAt: nil,
      status: .savedLocally,
      voiceNoteId: note.id,
      transcript: transcriptSnapshot,
      voiceLanguage: note.language,
      voiceOnDevice: note.onDevice,
      voiceSampleRate: Int(note.sampleRate),
      voiceFormat: note.format,
      lat: location?.coordinate.latitude,
      lon: location?.coordinate.longitude,
      horizontalAccuracy: location?.horizontalAccuracy
    )

    ObservationStore.shared.add(observation)
    onSaved(observation)
    dismiss()
  }
}
