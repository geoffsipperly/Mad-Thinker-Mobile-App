// Bend Fly Shop

import Combine
import Foundation

final class FarmedReportStore: ObservableObject {
  static let shared = FarmedReportStore()

  @Published private(set) var reports: [FarmedReport] = []

  private let fm = FileManager.default
  private let directoryURL: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  private init() {
    let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
    self.directoryURL = docs.appendingPathComponent("FarmedReports", isDirectory: true)

    self.encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601

    self.decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    ensureDirectory()
    loadAll()
  }

  // MARK: - Public API

  func refresh() {
    loadAll()
  }

  func add(_ report: FarmedReport) {
    var new = report
    new.status = .savedLocally
    save(report: new)
    loadAll()
  }

  func update(_ report: FarmedReport) {
    save(report: report)
    loadAll()
  }

  func delete(_ report: FarmedReport) {
    let url = jsonURL(for: report.id)
    try? fm.removeItem(at: url)
    loadAll()
  }

  /// Deletes uploaded reports whose `createdAt` is older than the given number of days.
  func purgeOldUploaded(olderThanDays days: Int = 14) {
    let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    var purged = 0

    for report in reports where report.status == .uploaded && report.createdAt < cutoff {
      let url = jsonURL(for: report.id)
      try? fm.removeItem(at: url)
      purged += 1
    }

    if purged > 0 {
      #if DEBUG
      print("[FarmedReportStore] Purged \(purged) uploaded report(s) older than \(days) days")
      #endif
      loadAll()
    }
  }

  func markUploaded(_ reportIDs: [UUID]) {
    var changed = false
    var current = reports

    for idx in current.indices {
      if reportIDs.contains(current[idx].id) {
        current[idx].status = .uploaded
        save(report: current[idx])
        changed = true
      }
    }

    if changed {
      loadAll()
    }
  }

  // MARK: - Internals

  private func ensureDirectory() {
    if !fm.fileExists(atPath: directoryURL.path) {
      try? fm.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
    }
  }

  private func jsonURL(for id: UUID) -> URL {
    directoryURL.appendingPathComponent("farmed_\(id.uuidString).json")
  }

  private func save(report: FarmedReport) {
    ensureDirectory()
    let url = jsonURL(for: report.id)
    do {
      let data = try encoder.encode(report)
      try data.write(to: url, options: [.atomic])
    } catch {
      #if DEBUG
      print("[FarmedReportStore] Failed to save report \(report.id): \(error.localizedDescription)")
      #endif
    }
  }

  private func loadAll() {
    ensureDirectory()
    guard let files = try? fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
      DispatchQueue.main.async { self.reports = [] }
      return
    }

    var loaded: [FarmedReport] = []

    for file in files where file.pathExtension.lowercased() == "json" {
      do {
        let data = try Data(contentsOf: file)
        let report = try decoder.decode(FarmedReport.self, from: data)
        loaded.append(report)
      } catch {
        #if DEBUG
        print("[FarmedReportStore] Failed to decode \(file.lastPathComponent): \(error.localizedDescription)")
        #endif
      }
    }

    loaded.sort { $0.createdAt > $1.createdAt }

    DispatchQueue.main.async {
      self.reports = loaded
    }
  }
}
