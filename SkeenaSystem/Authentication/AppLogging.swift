// AppLogging.swift
import Foundation
import os

public enum LogLevel: Int {
  case debug = 0
  case info
  case warn
  case error
}

public enum LogCategory: String, CaseIterable, Hashable {
  case auth = "auth"
  case ocr = "ocr"
  case network = "network"
  case trip = "trip"
  case ui = "ui"
  case `catch` = "catch" // catch-related flows (photo capture, analysis results)
  case ml = "ml"         // Core ML / Vision inference pipelines
  case persistence = "persistence" // Core Data and other storage
  case audio = "audio" // Voice memo / audio processing
  case forum = "forum" 
  case angler = "angler"
}

public struct AppLogging {
  // Global master switch
  public static var enabled: Bool = true 

  // Per-category switches (default to all enabled)
  public static var enabledCategories: Set<LogCategory> = Set(LogCategory.allCases)

  // Resolve minimum log level from Info.plist keys: prefers "LOG_LEVEL", falls back to "Log Level".
  private static func resolveMinimumLevelFromInfoPlist() -> LogLevel {
    func read(_ key: String) -> String? {
      (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let raw = (read("LOG_LEVEL") ?? read("Log Level") ?? "").lowercased()
    switch raw {
    case "error": return .error
    case "warn", "warning": return .warn
    case "info": return .info
    case "debug": return .debug
    default:
      return .debug
    }
  }

  public static var minimumLevel: LogLevel = resolveMinimumLevelFromInfoPlist()

  // Subsystem should be your bundle identifier; fallback to a generic string if not available
  private static let subsystem: String = {
    if let id = Bundle.main.bundleIdentifier { return id }
    return "com.epicwaters.app"
  }()

  // Category-specific os.Logger instances
  private static let authLogger = Logger(subsystem: subsystem, category: LogCategory.auth.rawValue)
  private static let ocrLogger = Logger(subsystem: subsystem, category: LogCategory.ocr.rawValue)
  private static let networkLogger = Logger(subsystem: subsystem, category: LogCategory.network.rawValue)
  private static let tripLogger = Logger(subsystem: subsystem, category: LogCategory.trip.rawValue)
  private static let uiLogger = Logger(subsystem: subsystem, category: LogCategory.ui.rawValue)
  private static let catchLogger = Logger(subsystem: subsystem, category: LogCategory.catch.rawValue)
  private static let mlLogger = Logger(subsystem: subsystem, category: LogCategory.ml.rawValue)
  private static let persistenceLogger = Logger(subsystem: subsystem, category: LogCategory.persistence.rawValue)
  private static let audioLogger = Logger(subsystem: subsystem, category: LogCategory.audio.rawValue)
  private static let forumLogger = Logger(subsystem: subsystem, category: LogCategory.forum.rawValue)
  private static let anglerLogger = Logger(subsystem: subsystem, category: LogCategory.angler.rawValue)

  // One-time diagnostic: log resolved LOG_LEVEL using os.Logger directly (unfiltered)
  private static let __logLevelDiagnostic: Void = {
    let raw = (Bundle.main.object(forInfoDictionaryKey: "LOG_LEVEL") as? String) ??
              (Bundle.main.object(forInfoDictionaryKey: "Log Level") as? String) ?? "<missing>"
    let logger = Logger(subsystem: subsystem, category: "system")
    logger.error("Resolved LOG_LEVEL (Info.plist): \(raw, privacy: .public). Effective minimum: \(String(describing: minimumLevel), privacy: .public)")
  }()

  // Primary logging API
  public static func log(_ message: () -> String,
                         level: LogLevel = .debug,
                         category: LogCategory = .ui) {
    _ = __logLevelDiagnostic
    guard enabled else { return }
    guard enabledCategories.contains(category) else { return }
    guard level.rawValue >= minimumLevel.rawValue else { return }

    let msg = message()

    let logger: Logger = {
      switch category {
      case .auth: return authLogger
      case .ocr: return ocrLogger
      case .network: return networkLogger
      case .trip: return tripLogger
      case .ui: return uiLogger
      case .catch: return catchLogger
      case .ml: return mlLogger
      case .persistence: return persistenceLogger
      case .audio: return audioLogger
      case .forum: return forumLogger
      case .angler: return anglerLogger
      }
    }()

    switch level {
    case .debug:
      logger.debug("\(msg)")
    case .info:
      logger.info("\(msg)")
    case .warn:
      logger.warning("\(msg)")
    case .error:
      logger.error("\(msg)")
    }
  }

  public static func log(_ message: String,
                         level: LogLevel = .debug,
                         category: LogCategory = .ui) {
    log({ message }, level: level, category: category)
  }
}
