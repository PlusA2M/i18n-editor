//
//  i18n_editorApp.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import SwiftUI

@main
struct i18n_editorApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var permissionManager = PermissionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(permissionManager)
                .onAppear {
                    permissionManager.checkPermissionsOnLaunch()
                }
        }
    }
}
