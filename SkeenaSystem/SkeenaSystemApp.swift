// Bend Fly Shop

import CoreData
import SwiftUI

@main
struct SkeenaSystemApp: App {
  // Your Core Data stack singleton
  private let persistence = PersistenceController.shared
  @Environment(\.scenePhase) private var scenePhase
    
    /// This initializer runs before the body is evaluated.
      init() {
        // Log the current environment project URL
        print("Current environment project URL: \(AppEnvironment.shared.projectURL)")
          print("Logging set to: \(AppEnvironment.shared.logLevel)")
      }

  var body: some Scene {
    WindowGroup {
      // Switches Login ↔ Landing internally based on auth state
      AppRootView()
        .environment(\.managedObjectContext, persistence.container.viewContext)
        .onAppear {
          // Reduce merge conflicts when background tasks write to Core Data
          persistence.container.viewContext.automaticallyMergesChangesFromParent = true
          persistence.container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        }
    }
    .onChange(of: scenePhase) { phase in
      // Lightweight safety net to persist any in-flight edits
      if phase == .background || phase == .inactive {
        let context = persistence.container.viewContext
        if context.hasChanges {
          do { try context.save() } catch {
            // You can also log this if you have a logger
            // print("Core Data save on background failed: \(error)")
          }
        }
      }
    }
  }
}
