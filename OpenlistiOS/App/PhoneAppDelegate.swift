//
//  PhoneAppDelegate.swift
//  OpenlistiOS
//

import UIKit

/// The UIKit side of launch. A CloudKit silent push can launch the app in
/// the background with no scene, so the library bootstraps from here too,
/// not only from the first scene; and push registration reports back here.
@MainActor
final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    var sync: ICloudSyncMonitor?
    var onDidLaunch: (() -> Void)?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        onDidLaunch?()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        sync?.pushRegistrationError = nil
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        sync?.pushRegistrationError = "Changes from your other devices arrive only while Openlist is open. \(error.localizedDescription)"
    }
}
