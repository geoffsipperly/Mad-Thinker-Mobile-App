// Bend Fly Shop
//
// UploadCoordinator.swift — Sequences catch-report, no-catch-mark, and
// observation uploads behind a single "Upload All" button. Each phase
// reuses the existing per-type uploader unchanged; this class just
// orchestrates ordering and aggregates results.
//
// Explicitly `nonisolated` to avoid the iOS 26.2 deinit crash (see
// UploadObservations.swift header for the full explanation).

import Foundation

nonisolated final class UploadCoordinator {

  // MARK: - Result

  struct UploadResult {
    var catchesUploaded: Int = 0
    var marksUploaded: Int = 0
    var notesUploaded: Int = 0
    var errors: [String] = []

    var totalUploaded: Int { catchesUploaded + marksUploaded + notesUploaded }
    var hasErrors: Bool { !errors.isEmpty }

    /// Human-readable one-line summary for the post-upload alert.
    var summary: String {
      var parts: [String] = []
      if catchesUploaded > 0 { parts.append("\(catchesUploaded) report\(catchesUploaded == 1 ? "" : "s")") }
      if marksUploaded > 0 { parts.append("\(marksUploaded) mark\(marksUploaded == 1 ? "" : "s")") }
      if notesUploaded > 0 { parts.append("\(notesUploaded) note\(notesUploaded == 1 ? "" : "s")") }
      let uploaded = parts.isEmpty ? "Nothing to upload" : "Uploaded \(parts.joined(separator: ", "))"
      if errors.isEmpty { return uploaded }
      return "\(uploaded)\n\nErrors:\n• \(errors.joined(separator: "\n• "))"
    }
  }

  // MARK: - Upload All

  /// Sequentially uploads catch reports → no-catch marks → observations.
  /// Phases with 0 pending items are skipped. Progress is reported as a
  /// single 0→1.0 stream. Completion is always called on the main queue.
  func uploadAll(
    catches: [CatchReport],
    marks: [FarmedReport],
    observations: [Observation],
    memberId: String,
    catchUploader: UploadCatchReport,
    progress: @escaping (Double) -> Void,
    phaseUpdate: @escaping (String) -> Void = { _ in },
    completion: @escaping (UploadResult) -> Void
  ) {
    let hasCatches = !catches.isEmpty
    let hasMarks = !marks.isEmpty
    let hasNotes = !observations.isEmpty

    AppLogging.log("[UploadCoordinator] Starting: catches=\(catches.count) marks=\(marks.count) observations=\(observations.count)", level: .info, category: .upload)

    guard hasCatches || hasMarks || hasNotes else {
      AppLogging.log("[UploadCoordinator] Nothing to upload", level: .debug, category: .upload)
      DispatchQueue.main.async { completion(UploadResult()) }
      return
    }

    // Distribute progress weight proportionally among active phases.
    let rawWeights: [(active: Bool, base: Double)] = [
      (hasCatches, 0.4), (hasMarks, 0.3), (hasNotes, 0.3)
    ]
    let activeTotal = rawWeights.filter(\.active).map(\.base).reduce(0, +)
    let scale = activeTotal > 0 ? 1.0 / activeTotal : 0
    let wCatch = hasCatches ? rawWeights[0].base * scale : 0
    let wMark = hasMarks ? rawWeights[1].base * scale : 0
    let wNote = hasNotes ? rawWeights[2].base * scale : 0

    // Mutable result captured by all closures in the chain.
    var result = UploadResult()
    var base: Double = 0

    // ── Phase 3: Observations ─────────────────────────────────
    let runNotes: () -> Void = {
      guard hasNotes else {
        DispatchQueue.main.async {
          progress(1.0)
          completion(result)
        }
        return
      }
      DispatchQueue.main.async { phaseUpdate("Uploading observations…") }
      let noteUploader = UploadObservations()
      noteUploader.upload(
        observations: observations,
        memberId: memberId,
        progress: { p in DispatchQueue.main.async { progress(base + p * wNote) } },
        completion: { noteResult in
          switch noteResult {
          case .success(let ids):
            result.notesUploaded = ids.count
            ObservationStore.shared.markUploaded(ids)
          case .failure(let error):
            result.errors.append("Notes: \(error.localizedDescription)")
          }
          AppLogging.log("[UploadCoordinator] Complete: \(result.totalUploaded) uploaded, \(result.errors.count) error(s)", level: result.hasErrors ? .warn : .info, category: .upload)
          DispatchQueue.main.async {
            progress(1.0)
            completion(result)
          }
        }
      )
    }

    // ── Phase 2: Farmed marks ─────────────────────────────────
    let runMarks: () -> Void = {
      guard hasMarks else {
        runNotes()
        return
      }
      DispatchQueue.main.async { phaseUpdate("Uploading activity marks…") }
      let markUploader = UploadFarmedReports()
      markUploader.upload(
        reports: marks,
        progress: { p in DispatchQueue.main.async { progress(base + p * wMark) } },
        completion: { markResult in
          switch markResult {
          case .success(let ids):
            result.marksUploaded = ids.count
            FarmedReportStore.shared.markUploaded(ids)
          case .failure(let error):
            result.errors.append("Marks: \(error.localizedDescription)")
          }
          base += wMark
          runNotes()
        }
      )
    }

    // ── Phase 1: Catch reports ────────────────────────────────
    if hasCatches {
      DispatchQueue.main.async { phaseUpdate("Uploading catch reports…") }
      catchUploader.upload(
        reports: catches,
        progress: { p in DispatchQueue.main.async { progress(p * wCatch) } },
        completion: { catchResult in
          switch catchResult {
          case .success(let ids):
            result.catchesUploaded = ids.count
            CatchReportStore.shared.markUploaded(ids)
          case .failure(let error):
            result.errors.append("Reports: \(error.localizedDescription)")
          }
          base += wCatch
          runMarks()
        }
      )
    } else {
      runMarks()
    }
  }
}
