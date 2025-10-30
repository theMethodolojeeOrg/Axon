//
//  ErrorHandler.swift
//  Axon
//
//  Global error handling utilities
//

import Foundation

class ErrorHandler {
    static func handle(
        _ error: Error,
        context: String = ""
    ) {
        let errorMessage: String

        if let apiError = error as? APIError {
            errorMessage = apiError.localizedDescription
        } else if let authError = error as? AuthError {
            errorMessage = authError.localizedDescription
        } else {
            errorMessage = error.localizedDescription
        }

        let logMessage = context.isEmpty
            ? "Error: \(errorMessage)"
            : "[\(context)] Error: \(errorMessage)"

        print(logMessage)

        // Send to analytics in production
        #if DEBUG
        // Log to console in debug mode
        #else
        // TODO: Send to crash reporting service (e.g., Crashlytics)
        #endif
    }

    static func handleAndReturn(_ error: Error, context: String = "") -> String {
        handle(error, context: context)
        return error.localizedDescription
    }
}
