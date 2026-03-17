// Bend Fly Shop

import CoreData

final class PersistenceController {
  static let shared = PersistenceController()
  let container: NSPersistentContainer

  /// Shared model instance to prevent "Failed to find a unique match for an NSEntityDescription"
  /// errors when multiple in-memory containers are created in tests.
  private static let model: NSManagedObjectModel = {
    guard let modelURL = Bundle(for: PersistenceController.self).url(forResource: "SkeenaSystem", withExtension: "momd"),
          let model = NSManagedObjectModel(contentsOf: modelURL) else {
      fatalError("Failed to load Core Data model")
    }
    return model
  }()

  init(inMemory: Bool = false) {
    // Use the shared model to avoid entity description conflicts in tests
    container = NSPersistentContainer(name: "SkeenaSystem", managedObjectModel: Self.model)
    if inMemory {
      container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
    }
    container.loadPersistentStores { _, error in
      if let error = error as NSError? {
        AppLogging.log({ "Core Data loadPersistentStores failed: \(error), \(error.userInfo)" }, level: .error, category: .persistence)
        #if DEBUG
        fatalError("Unresolved error: \(error), \(error.userInfo)")
        #else
        // In release, consider surfacing an error UI or retry strategy instead of crashing.
        #endif
      }
    }
    container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    container.viewContext.automaticallyMergesChangesFromParent = true

    // Ensure the community and its Lodges exist before
    // any trip sync or catch-recording flow tries to look them up.
    seedCommunityIfNeeded(context: container.viewContext)
  }

  // MARK: - Seed data

  /// Creates the community and its associated Lodge
  /// records if they don't already exist. Safe to call multiple times;
  /// it only inserts missing rows.
  func seedCommunityIfNeeded(context: NSManagedObjectContext) {
    context.performAndWait {
      let communityFetch: NSFetchRequest<Community> = Community.fetchRequest()
      communityFetch.predicate = NSPredicate(format: "name == %@", AppEnvironment.shared.communityName)
      communityFetch.fetchLimit = 1

      let community: Community
      do {
        if let found = try context.fetch(communityFetch).first {
          community = found
        } else {
          let c = Community(context: context)
          c.communityId = UUID()
          c.name = AppEnvironment.shared.communityName
          c.createdAt = Date()
          community = c
        }
      } catch {
        AppLogging.log({ "seedCommunityIfNeeded: Community lookup failed: \(error.localizedDescription)" }, level: .error, category: .persistence)
        return
      }

      let desired: [String] = [
        "Bend Fly Shop"
      ]

      let lodgeFetch: NSFetchRequest<Lodge> = Lodge.fetchRequest()
      lodgeFetch.predicate = NSPredicate(format: "community == %@", community)
      let existing: [Lodge]
      do {
        existing = try context.fetch(lodgeFetch)
      } catch {
        AppLogging.log({ "seedCommunityIfNeeded: Lodge lookup failed: \(error.localizedDescription)" }, level: .error, category: .persistence)
        return
      }

      let existingNames = Set(existing.compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) })

      // Also fix any existing Lodges that match by name but are missing
      // their Community relationship (e.g. created by SynchTrips before
      // the seed ran on this device).
      let orphanFetch: NSFetchRequest<Lodge> = Lodge.fetchRequest()
      orphanFetch.predicate = NSPredicate(format: "name IN %@ AND community == nil", desired)
      if let orphans = try? context.fetch(orphanFetch) {
        for lodge in orphans {
          lodge.community = community
          AppLogging.log({ "seedCommunityIfNeeded: linked orphan lodge '\(lodge.name ?? "")' to \(AppEnvironment.shared.communityName)" }, level: .info, category: .persistence)
        }
      }

      var createdAny = false
      for name in desired where !existingNames.contains(name) {
        // Check if a Lodge with this name already exists (without a community)
        // before creating a duplicate.
        let nameCheck: NSFetchRequest<Lodge> = Lodge.fetchRequest()
        nameCheck.predicate = NSPredicate(format: "name ==[c] %@", name)
        nameCheck.fetchLimit = 1
        if let existingLodge = try? context.fetch(nameCheck).first {
          if existingLodge.community == nil {
            existingLodge.community = community
            createdAny = true
          }
          continue
        }

        let l = Lodge(context: context)
        l.lodgeId = UUID()
        l.name = name
        l.createdAt = Date()
        l.community = community
        createdAny = true
      }

      if createdAny || context.hasChanges {
        do { try context.save() } catch {
          AppLogging.log({ "seedCommunityIfNeeded: Failed to save: \(error.localizedDescription)" }, level: .error, category: .persistence)
        }
      }
    }
  }
}
