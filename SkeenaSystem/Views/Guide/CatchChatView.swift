// Bend Fly Shop

import SwiftUI

struct CatchChatView: View {
  @ObservedObject var viewModel: CatchChatViewModel

  @State private var showSourceActionSheet = false
  @State private var showImagePicker = false
  @State private var imagePickerSource: ImagePicker.Source = .library

  // Voice memo sheet
  @State private var showVoiceNoteSheet = false

  var body: some View {
    VStack(spacing: 0) {
      // Messages + inline capture options
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { idx, msg in
              messageRow(msg, index: idx)
            }

            // Typing / analyzing indicator
            if viewModel.isAssistantTyping {
              HStack(spacing: 8) {
                Image(AppEnvironment.shared.appLogoAsset)
                  .resizable()
                  .scaledToFit()
                  .frame(width: 24, height: 24)
                  .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                HStack(spacing: 6) {
                  ProgressView()
                    .scaleEffect(0.8)
                  Text("Analyzing…")
                    .font(.footnote)
                }
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.12))
                .cornerRadius(16)

                Spacer(minLength: 40)
              }
              .padding(.top, 4)
            }
          }
          .padding(.horizontal, 4)
          .padding(.top, 4)
        }
        .modifier(ScrollIndicatorModifier())
        .onChange(of: viewModel.messages.count) { newCount in
          // Only auto-scroll when there is more than one message.
          // This keeps the very first message near the top, under the header.
          guard newCount > 1, let lastID = viewModel.messages.last?.id else { return }

          DispatchQueue.main.async {
            proxy.scrollTo(lastID, anchor: .bottom)
          }
        }
      }

      // Subtle separator between messages and input
      Divider()
        .background(Color.white.opacity(0.15))

      inputBar
    }
    .background(Color.clear)
    .onChange(of: showSourceActionSheet) { presented in
      AppLogging.log("ShowSourceActionSheet changed: \(presented)", level: .debug, category: .angler)
    }
    // Modern photo source dialog
    .confirmationDialog(
      "Add Photo",
      isPresented: $showSourceActionSheet,
      titleVisibility: .visible
    ) {
      Button("Camera") {
        AppLogging.log("Photo source selected: camera", level: .debug, category: .angler)
        imagePickerSource = .camera
        showImagePicker = true
      }
      Button("Photo Library") {
        AppLogging.log("Photo source selected: library", level: .debug, category: .angler)
        imagePickerSource = .library
        showImagePicker = true
      }
      Button("Cancel", role: .cancel) {}
    }

    .sheet(isPresented: $showImagePicker) {
      VStack {
        ImagePicker(source: imagePickerSource) { picked in
          let image = picked.image
          AppLogging.log("ImagePicker returned image: size=\(Int(image.size.width))x\(Int(image.size.height))", level: .debug, category: .angler)
          viewModel.handlePhotoSelected(picked)
        }
      }
      .onAppear {
        let src = (imagePickerSource == .camera) ? "camera" : "library"
        AppLogging.log("ImagePicker sheet appeared with source: \(src)", level: .debug, category: .angler)
      }
      .onDisappear {
        AppLogging.log("ImagePicker sheet disappeared", level: .debug, category: .angler)
      }
    }
    .sheet(isPresented: $showVoiceNoteSheet) {
      ChatVoiceNoteSheet { note in
        viewModel.attachVoiceNote(note)
      }
    }
  }

  // MARK: - Input bar

  private var inputBar: some View {
    HStack(spacing: 8) {
      TextField("Type your message…", text: $viewModel.userInput)
        .submitLabel(.send)
        .onSubmit {
          viewModel.sendCurrentInput()
          hideKeyboard()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.08))
        .cornerRadius(16)
        .foregroundColor(.white)

      Button(action: {
        viewModel.sendCurrentInput()
        hideKeyboard()
      }) {
        Image(systemName: "paperplane.fill")
          .font(.system(size: 16, weight: .semibold))
          .padding(8)
      }
      .foregroundColor(.white)
      .background(
        viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? Color.white.opacity(0.15)
          : Color.blue
      )
      .cornerRadius(16)
      .disabled(
        viewModel.userInput
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .isEmpty
      )
    }
    .padding(.top, 6)
    .padding(.horizontal, 4)
  }

  private func hideKeyboard() {
    #if canImport(UIKit)
    UIApplication.shared.endEditing(true)
    #endif
  }

  // MARK: - Message rows

  @ViewBuilder
  private func messageRow(_ message: ChatMessage, index: Int) -> some View {
    HStack(alignment: .center, spacing: 8) {
      if message.sender == .assistant {
        Image(AppEnvironment.shared.appLogoAsset)
          .resizable()
          .scaledToFit()
          .frame(width: 24, height: 24)
          .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

        bubble(message, isUser: false)

        Spacer(minLength: 16)

        let showPhotoButton = viewModel.showCaptureOptions && index == 0
        let showVoiceButton = (viewModel.voiceMemoAnchorMessageID == message.id)
        let showConfirmButton = (viewModel.confirmAnalysisMessageID == message.id)

        if showPhotoButton || showVoiceButton || showConfirmButton {
          HStack(spacing: 16) {
            if showPhotoButton {
              Button {
                AppLogging.log("Upload button tapped for photo source selection", level: .debug, category: .angler)
                showSourceActionSheet = true
              } label: {
                VStack(spacing: 4) {
                  Image(systemName: "photo.on.rectangle")
                    .font(.title2)
                  Text("Upload")
                    .font(.footnote)
                }
              }
            }

            if showVoiceButton {
              Button {
                showVoiceNoteSheet = true
              } label: {
                VStack(spacing: 4) {
                  Image(systemName: "mic.fill")
                    .font(.title2)
                  Text("Memo")
                    .font(.footnote)
                }
              }

              Button {
                viewModel.deferVoiceMemoToLater()
              } label: {
                VStack(spacing: 4) {
                  Image(systemName: "clock.arrow.circlepath")
                    .font(.title2)
                  Text("Later")
                    .font(.footnote)
                }
              }
            }

            if showConfirmButton {
              Button {
                viewModel.confirmAnalysisFromButton()
              } label: {
                VStack(spacing: 4) {
                  Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                  Text("Confirm")
                    .font(.footnote)
                }
              }
            }
          }
          .foregroundColor(.white)
        } else {
          Spacer(minLength: 24)
        }

      } else {
        Spacer(minLength: 40)
        bubble(message, isUser: true)
      }
    }
  }

  @ViewBuilder
  private func bubble(_ message: ChatMessage, isUser: Bool) -> some View {
    if let img = message.image {
      Image(uiImage: img)
        .resizable()
        .scaledToFit()
        .frame(maxWidth: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.4), lineWidth: 1)
        )
        .padding(2)
    } else if let text = message.text {
      Text(text)
        .font(.subheadline)
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isUser ? Color.blue : Color.white.opacity(0.12))
        .cornerRadius(16)
    }
  }
}

// MARK: - Scroll indicator helper

private struct ScrollIndicatorModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.0, *) {
      content.scrollIndicators(.visible)
    } else {
      content
    }
  }
}

// MARK: - ChatVoiceNoteSheet (unchanged except requested removals)

// MARK: - DarkChatTextEditor (UIViewRepresentable for reliable dark background)

private struct DarkChatTextEditor: UIViewRepresentable {
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

struct ChatVoiceNoteSheet: View {
  @Environment(\.dismiss) private var dismiss
  let onSaved: (LocalVoiceNote) -> Void

  @StateObject private var recorder = SpeechRecorder(maxDuration: 60)

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
        Text("Record a memo for this catch")
          .font(.headline)
          .foregroundColor(.white)
          .multilineTextAlignment(.center)
          .padding(.top, 8)

        HStack(spacing: 24) {
          // Main record / pause button
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

          // Stop button – only visible while recording (active or paused)
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
          
        Text(String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60))
          .font(.headline)
          .foregroundColor(timerColor)
          .opacity(timerOpacity)
    
        ZStack {
          // Live transcript while recording (or before recording starts)
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
              DarkChatTextEditor(text: $transcriptSnapshot)
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
            saveNote()
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
  }
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

  private func toggleRecording() {
    if recorder.isRecording {
      if recorder.isPaused {
        // Resume
        recorder.resume()
        startCountdown()
      } else {
        // Pause
        recorder.pause()
        pauseCountdown()
      }
    } else {
      // Start fresh
      isStarting = true
      errorMessage = nil

      Task {
        do {
          try await recorder.start()

          // Start countdown *after* recording is active
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

  private func startCountdown() {
    countdownTimer?.invalidate()
    isFlashingWarning = false

    countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
      // If recording stopped for any reason, stop the timer.
      if !recorder.isRecording {
        stopCountdown()
        return
      }

      if remainingSeconds > 0 {
        remainingSeconds -= 1
      }

      // Flash in last 10 seconds
      if remainingSeconds <= 10 && remainingSeconds > 0 {
        isFlashingWarning.toggle()
      } else {
        isFlashingWarning = false
      }

      // Hard stop at 0
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

  private func saveNote() {
    stopRecording()

    guard let tempURL = recorder.currentTempURL() else {
      errorMessage = "No audio recorded"
      return
    }

    let duration = recorder.totalDurationSec()
    let note = VoiceNoteStore.shared.addNew(
      audioTempURL: tempURL,
      transcript: transcriptSnapshot,
      language: recorder.languageCode,
      onDevice: recorder.onDeviceRecognition,
      sampleRate: recorder.sampleRate,
      location: nil,
      duration: duration
    )

    onSaved(note)
    dismiss()
  }
}
