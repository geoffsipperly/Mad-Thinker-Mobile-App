// Bend Fly Shop

import CoreData

extension CatchReport {
  @discardableResult
  static func create(
    in context: NSManagedObjectContext,
    reportId: UUID = .init(),
    river: String,
    species: String,
    sex: String,
    origin: String,
    tagId: String?,
    lengthInches: Int,
    quality: String,
    tactic: String, // 👈 New field
    notes: String?,
    photoPath: String?,
    latitude: Double?,
    longitude: Double?,
    createdAt: Date = Date(),
    guideName: String,
    clientName: String?,
    status: String = "Saved locally"
  ) throws -> CatchReport {
    let report = CatchReport(context: context)
    report.reportId = reportId
    report.river = river
    report.species = species
    report.sex = sex
    report.origin = origin
    report.tagId = tagId
    report.lengthInches = Int16(lengthInches)
    report.quality = quality
    report.tactic = tactic // 👈 assign new field
    report.notes = notes
    report.photoPath = photoPath
    report.guideName = guideName
    report.clientName = clientName
    if let lat = latitude { report.latitude = lat }
    if let lon = longitude { report.longitude = lon }
    report.createdAt = createdAt
    report.status = status

    try context.save()
    return report
  }
}
