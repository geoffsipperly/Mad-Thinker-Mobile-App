//
//  AppLogging.swift
//

import os

enum LogCategory: String, CaseIterable {
    case auth
    case network
    case ocr
    case ml
    case catch
    case persistence
    case ui
    case trip
    case audio
}

enum LogLevel: Int, Comparable {
    case debug = 1
    case info
    case warn
    case error

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

struct AppLogging {
    private static let minimumLevel: LogLevel = {
        #if DEBUG
        return .debug
        #else
        return .info
        #endif
    }()

    private static let loggers: [LogCategory: Logger] = {
        var dict = [LogCategory: Logger]()
        for category in LogCategory.allCases {
            dict[category] = Logger(subsystem: Bundle.main.bundleIdentifier ?? "App", category: category.rawValue)
        }
        return dict
    }()

    static func log(
        _ message: @autoclosure () -> String,
        level: LogLevel = .debug,
        category: LogCategory = .ui
    ) {
        log({ message() }, level: level, category: category)
    }

    static func log(
        _ message: () -> String,
        level: LogLevel = .debug,
        category: LogCategory = .ui
    ) {
        guard level >= minimumLevel else { return }
        let logger = loggers[category] ?? Logger(subsystem: Bundle.main.bundleIdentifier ?? "App", category: category.rawValue)

        switch level {
        case .debug:
            logger.debug("\(message())")
        case .info:
            logger.info("\(message())")
        case .warn:
            logger.warning("\(message())")
        case .error:
            logger.error("\(message())")
        }
    }
}
