import CloudKit
import CoreData
import Foundation

nonisolated enum ICloudError {
    static func message(for error: Error) -> String {
        let errors = nestedErrors(error as NSError, depth: 0)
        for error in errors {
            if error.domain == CKErrorDomain, let code = CKError.Code(rawValue: error.code) {
                switch code {
                case .quotaExceeded:
                    return "Your iCloud storage is full. Free up iCloud space to resume syncing."
                case .notAuthenticated:
                    return "Sign in to your Apple Account in System Settings to resume syncing."
                case .networkFailure, .networkUnavailable:
                    return "Cannot reach iCloud. Check your internet connection; transfers will retry automatically."
                case .serviceUnavailable, .requestRateLimited, .zoneBusy:
                    return "iCloud is temporarily busy or unavailable. Transfers will retry automatically."
                case .badContainer, .missingEntitlement, .permissionFailure:
                    return "This build is not authorized to use the iCloud container. Check its signing profile and iCloud capabilities."
                default:
                    break
                }
            }
            if error.domain == NSURLErrorDomain {
                return "Cannot reach iCloud. Check your internet connection; transfers will retry automatically."
            }
        }
        let useful = errors.first { $0.localizedFailureReason != nil } ?? (error as NSError)
        return useful.localizedFailureReason ?? useful.localizedDescription
    }

    private static func nestedErrors(_ error: NSError, depth: Int) -> [NSError] {
        guard depth < 8 else { return [error] }
        var children: [NSError] = []
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { children.append(underlying) }
        for key in [NSDetailedErrorsKey, "encounteredErrors"] {
            if let errors = error.userInfo[key] as? [NSError] { children.append(contentsOf: errors) }
        }
        if let errors = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: NSError] {
            children.append(contentsOf: errors.values)
        }
        return children.flatMap { nestedErrors($0, depth: depth + 1) } + [error]
    }
}
