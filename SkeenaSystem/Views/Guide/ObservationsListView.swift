// Bend Fly Shop

import AVFoundation
import SwiftUI

// MARK: - DarkDetailTextEditor (UIViewRepresentable for reliable dark background)

private struct DarkDetailTextEditor: UIViewRepresentable {
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

// MARK: - ObservationsListView

struct ObservationsListView: View {
  @ObservedObject private var store = ObservationStore.shared
  @Environment(\.dismiss) private var dismiss

  @State private var isUploading = false
  @State private var uploadProgress: Double = 0
  @State private var uploadError: String?
  @State private var showUploadAlert = false
  @State private var uploadResultMessage = ""

  private let uploader = UploadObservations()

  private static let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .long
    f.timeStyle = .none
    return f
  }()

  private static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .none
    f.timeStyle = .short
    return f
  }()

  // MARK: - Filtering

  private func isArchived(_ obs: Observation) -> Bool {
    let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date.distantPast
    return obs.createdAt < twoWeeksAgo
  }

  private var activeObservations: [Observation] {
    store.observations.filter { !isArchived($0) }
  }

  private var archivedObservations: [Observation] {
    store.observations.filter { isArchived($0) }
  }

  private var pendingObservations: [Observation] {
    activeObservations.filter { $0.status == .savedLocally }
  }

  private var uploadedObservations: [Observation] {
    activeObservations.filter { $0.status == .uploaded }
  }

  private func grouped(_ observations: [Observation]) -> [(date: String, items: [Observation])] {
    let dict = Dictionary(grouping: observations) { obs in
      Self.dayFormatter.string(from: obs.createdAt)
    }
    return dict
      .map { (date: $0.key, items: $0.value) }
      .sorted { $0.items.first!.createdAt > $1.items.first!.createdAt }
  }

  // MARK: - Body

  var body: some View {
    DarkPageTemplate(bottomToolbar: {
      RoleAwareToolbar(activeTab: "observations")
    }) {
      ZStack {
        if store.observations.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "waveform")
              .font(.system(size: 48))
              .foregroundColor(.gray)
            Text("No observations yet")
              .font(.headline)
              .foregroundColor(.gray)
            Text("Record a field observation to get started.")
              .font(.subheadline)
              .foregroundColor(.gray.opacity(0.7))
          }
        } else {
          List {
            // MARK: Pending Upload
            if !pendingObservations.isEmpty {
              Section {
                ForEach(grouped(pendingObservations), id: \.date) { group in
                  Text(group.date)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .listRowBackground(Color.black)

                  ForEach(group.items) { obs in
                    NavigationLink(destination: ObservationDetailView(observation: obs)) {
                      ObservationRow(observation: obs)
                    }
                    .listRowBackground(Color.black)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                      Button(role: .destructive) {
                        // Delete audio too
                        if let noteId = obs.voiceNoteId,
                           let note = VoiceNoteStore.shared.notes.first(where: { $0.id == noteId }) {
                          VoiceNoteStore.shared.delete(note)
                        }
                        store.delete(obs)
                      } label: {
                        Label("Delete", systemImage: "trash")
                      }
                    }
                  }
                }
              } header: {
                HStack {
                  Text("Pending Upload")
                  Spacer()
                  statusPill("Saved locally", color: .blue)
                }
              }
            }

            // MARK: Uploaded
            if !uploadedObservations.isEmpty {
              Section {
                ForEach(grouped(uploadedObservations), id: \.date) { group in
                  Text(group.date)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .listRowBackground(Color.black)

                  ForEach(group.items) { obs in
                    NavigationLink(destination: ObservationDetailView(observation: obs)) {
                      ObservationRow(observation: obs)
                    }
                    .listRowBackground(Color.black)
                  }
                }
              } header: {
                HStack {
                  Text("Uploaded")
                  Spacer()
                  statusPill("Uploaded", color: .green)
                }
              }
            }

            // MARK: Archive link
            if !archivedObservations.isEmpty {
              Section {
                NavigationLink(destination: ObservationArchiveListView(observations: archivedObservations)) {
                  HStack {
                    Image(systemName: "archivebox")
                      .foregroundColor(.gray)
                    Text("Archived observations")
                      .foregroundColor(.white)
                    Spacer()
                    Text("\(archivedObservations.count)")
                      .foregroundColor(.gray)
                  }
                }
                .listRowBackground(Color.black)
              }
            }
          }
          .listStyle(.plain)
          .onAppear { UITableView.appearance().backgroundColor = .clear }
        }

        // Upload progress overlay
        if isUploading {
          VStack {
            Spacer()
            HStack(spacing: 12) {
              ProgressView()
                .tint(.white)
              Text("Uploading… \(Int(uploadProgress * 100))%")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white)
              Spacer()
            }
            .padding()
            .background(Color.blue.opacity(0.9))
            .cornerRadius(12)
            .padding()
          }
        }
      }
    }
    .navigationTitle("Observations")
    .navigationBarBackButtonHidden(true)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          startUpload()
        } label: {
          Image(systemName: "arrow.up.circle")
            .font(.title3)
        }
        .disabled(pendingObservations.isEmpty || isUploading)
      }
    }
    .alert("Upload", isPresented: $showUploadAlert) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(uploadResultMessage)
    }
  }

  // MARK: - Status pill

  private func statusPill(_ text: String, color: Color) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(color.opacity(0.2))
      .foregroundColor(color)
      .cornerRadius(8)
  }

  // MARK: - Upload

  private func startUpload() {
    isUploading = true
    uploadProgress = 0

    Task {
      await AuthStore.shared.refreshFromSupabase()

      uploader.upload(
        observations: pendingObservations,
        progress: { p in
          DispatchQueue.main.async { self.uploadProgress = p }
        },
        completion: { result in
          DispatchQueue.main.async {
            self.isUploading = false
            switch result {
            case .success(let clientIds):
              ObservationStore.shared.markUploaded(clientIds)
              self.uploadResultMessage = "Uploaded \(clientIds.count) observation(s) successfully."
              self.showUploadAlert = true
            case .failure(let error):
              self.uploadResultMessage = error.localizedDescription
              self.showUploadAlert = true
            }
          }
        }
      )
    }
  }
}

// MARK: - ObservationRow

private struct ObservationRow: View {
  let observation: Observation

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(observation.transcript.isEmpty ? "No transcript" : observation.transcript)
        .font(.body)
        .foregroundColor(.white)
        .lineLimit(2)

      HStack {
        Text(Self.timeFormatter.string(from: observation.createdAt))
          .font(.caption)
          .foregroundColor(.gray)

        if observation.lat != nil {
          Image(systemName: "location.fill")
            .font(.caption2)
            .foregroundColor(.gray)
        }

        Spacer()
      }
    }
    .padding(.vertical, 4)
  }

  private static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .none
    f.timeStyle = .short
    return f
  }()
}

// MARK: - ObservationDetailView

struct ObservationDetailView: View {
  @ObservedObject private var store = ObservationStore.shared
  @State private var observation: Observation
  @State private var editedTranscript: String
  @State private var showSavedAlert = false

  private var canEdit: Bool { observation.status == .savedLocally }

  init(observation: Observation) {
    _observation = State(initialValue: observation)
    _editedTranscript = State(initialValue: observation.transcript)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Status
        HStack {
          statusPill(
            observation.isUploaded ? "Uploaded" : "Saved locally",
            color: observation.isUploaded ? .green : .blue
          )
          Spacer()
          Text(Self.dateFormatter.string(from: observation.createdAt))
            .font(.caption)
            .foregroundColor(.gray)
        }

        // Transcript
        VStack(alignment: .leading, spacing: 4) {
          Text("Transcript")
            .font(.caption)
            .foregroundColor(.gray)

          if canEdit {
            DarkDetailTextEditor(text: $editedTranscript)
              .frame(minHeight: 120)
          } else {
            Text(observation.transcript.isEmpty ? "No transcript" : observation.transcript)
              .font(.body)
              .foregroundColor(.white.opacity(0.9))
              .padding()
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.white.opacity(0.08))
              .cornerRadius(12)
          }
        }

        // Voice memo playback
        if let noteId = observation.voiceNoteId {
          VStack(alignment: .leading, spacing: 4) {
            Text("Voice Memo")
              .font(.caption)
              .foregroundColor(.gray)

            Button {
              playAudio(noteId: noteId)
            } label: {
              HStack {
                Image(systemName: "play.circle.fill")
                  .font(.title2)
                Text("Play recording")
                  .font(.subheadline)
              }
              .foregroundColor(.blue)
              .padding()
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.white.opacity(0.08))
              .cornerRadius(12)
            }
          }
        }

        // Location
        if let lat = observation.lat, let lon = observation.lon {
          VStack(alignment: .leading, spacing: 4) {
            Text("Location")
              .font(.caption)
              .foregroundColor(.gray)

            HStack {
              Image(systemName: "location.fill")
                .foregroundColor(.blue)
              Text(String(format: "%.4f, %.4f", lat, lon))
                .font(.footnote)
                .foregroundColor(.white.opacity(0.8))
              if let acc = observation.horizontalAccuracy {
                Text("(±\(Int(acc))m)")
                  .font(.caption)
                  .foregroundColor(.gray)
              }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.08))
            .cornerRadius(12)
          }
        }

        // Save button (editable only)
        if canEdit && editedTranscript != observation.transcript {
          Button {
            observation.transcript = editedTranscript
            store.update(observation)
            showSavedAlert = true
          } label: {
            Text("Save Changes")
              .font(.headline)
              .frame(maxWidth: .infinity)
              .padding()
              .background(Color.blue)
              .foregroundColor(.white)
              .cornerRadius(12)
          }
        }
      }
      .padding()
    }
    .background(Color.black.ignoresSafeArea())
    .navigationTitle("Observation")
    .preferredColorScheme(.dark)
    .alert("Saved", isPresented: $showSavedAlert) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Observation updated.")
    }
  }

  // MARK: - Playback

  @StateObject private var player = NoteAudioPlayer()

  private func playAudio(noteId: UUID) {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let audioURL = docs
      .appendingPathComponent("VoiceNotes", isDirectory: true)
      .appendingPathComponent("note_\(noteId.uuidString).m4a")
    player.play(url: audioURL)
  }

  // MARK: - Helpers

  private func statusPill(_ text: String, color: Color) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(color.opacity(0.2))
      .foregroundColor(color)
      .cornerRadius(8)
  }

  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()
}

// MARK: - Archive List

private struct ObservationArchiveListView: View {
  let observations: [Observation]

  var body: some View {
    List {
      ForEach(observations) { obs in
        NavigationLink(destination: ObservationDetailView(observation: obs)) {
          ObservationRow(observation: obs)
        }
        .listRowBackground(Color.black)
      }
    }
    .listStyle(.plain)
    .onAppear { UITableView.appearance().backgroundColor = .clear }
    .background(Color.black.ignoresSafeArea())
    .navigationTitle("Archived Observations")
    .preferredColorScheme(.dark)
  }
}
