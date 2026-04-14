// Bend Fly Shop
//
// ActivitiesObservationsTab.swift — "Observations" tab inside ActivitiesView.
// Two sections:
//   • Marks  — non-catch activity reports (active, farmed, promising, passed)
//   • Notes  — voice memo observations with transcripts
//
// Uploads are handled by the parent ActivitiesView's unified Upload button
// via UploadCoordinator. This tab only manages display and deletion.

import SwiftUI

struct ActivitiesObservationsTab: View {
  @ObservedObject private var farmedStore = FarmedReportStore.shared
  @ObservedObject private var observationStore = ObservationStore.shared

  // MARK: - Body

  var body: some View {
    List {
      // ── Marks section ──────────────────────────────────────────
      Section {
        if farmedStore.reports.isEmpty {
          Text("No activity marks yet")
            .font(.subheadline)
            .foregroundColor(.gray)
            .listRowBackground(Color.black)
        } else {
          ForEach(farmedStore.reports) { report in
            MarkRow(report: report)
              .listRowBackground(Color.black)
          }
          .onDelete(perform: deleteMarks)
        }
      } header: {
        Text("Marks")
          .font(.headline)
          .foregroundColor(.white)
      }

      // ── Notes section ──────────────────────────────────────────
      Section {
        if observationStore.observations.isEmpty {
          Text("No observations yet")
            .font(.subheadline)
            .foregroundColor(.gray)
            .listRowBackground(Color.black)
        } else {
          ForEach(observationStore.observations) { obs in
            NavigationLink(destination: ObservationDetailView(observation: obs)) {
              NoteRow(observation: obs)
            }
            .listRowBackground(Color.black)
          }
          .onDelete(perform: deleteNotes)
        }
      } header: {
        Text("Notes")
          .font(.headline)
          .foregroundColor(.white)
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(Color.black)
    .onAppear {
      farmedStore.purgeOldUploaded()
      farmedStore.refresh()
    }
  }

  // MARK: - Delete

  private func deleteMarks(at offsets: IndexSet) {
    for index in offsets {
      let report = farmedStore.reports[index]
      if report.status == .savedLocally {
        farmedStore.delete(report)
      }
    }
  }

  private func deleteNotes(at offsets: IndexSet) {
    for index in offsets {
      let obs = observationStore.observations[index]
      if let noteId = obs.voiceNoteId,
         let note = VoiceNoteStore.shared.notes.first(where: { $0.id == noteId }) {
        VoiceNoteStore.shared.delete(note)
      }
      observationStore.delete(obs)
    }
  }
}

// MARK: - Mark Row (non-catch activity report)

private struct MarkRow: View {
  let report: FarmedReport

  private static let timestampFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .short
    return df
  }()

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(report.eventType.displayName)
          .font(.subheadline.weight(.semibold))
          .foregroundColor(.white)
        Spacer()
        Text(report.status.rawValue)
          .font(.caption2)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(report.status == .uploaded ? Color.green.opacity(0.12) : Color.blue.opacity(0.12))
          .foregroundColor(report.status == .uploaded ? .green : .blue)
          .clipShape(Capsule())
      }
      Text(Self.timestampFormatter.string(from: report.createdAt))
        .font(.caption)
        .foregroundColor(.gray)
      if !report.guideName.isEmpty {
        Text("Guide: \(report.guideName)")
          .font(.caption)
          .foregroundColor(.gray)
      }
    }
    .padding(.vertical, 2)
    .deleteDisabled(report.status != .savedLocally)
  }
}

// MARK: - Note Row (voice memo observation)

private struct NoteRow: View {
  let observation: Observation

  private static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()

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
        Text(observation.status.rawValue)
          .font(.caption2)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(observation.status == .uploaded ? Color.green.opacity(0.12) : Color.blue.opacity(0.12))
          .foregroundColor(observation.status == .uploaded ? .green : .blue)
          .clipShape(Capsule())
      }
    }
    .padding(.vertical, 2)
  }
}
