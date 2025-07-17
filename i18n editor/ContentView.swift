//
//  ContentView.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var permissionManager: PermissionManager
    @StateObject private var projectManager = ProjectManager()

    var body: some View {
        Group {
            if projectManager.isProjectLoaded, let project = projectManager.currentProject {
                // Main translation editor
                TranslationEditorView(project: project)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button("Close Project") {
                                projectManager.confirmCloseProject { shouldClose in
                                    if shouldClose {
                                        projectManager.closeProject()
                                    }
                                }
                            }
                        }
                    }
            } else {
                // Project selection screen
                ProjectSelectionView()
                    .environmentObject(projectManager)
            }
        }
        .alert("Project Loading Error", isPresented: .constant(projectManager.projectLoadingError != nil)) {
            Button("OK") {
                projectManager.projectLoadingError = nil
            }
        } message: {
            Text(projectManager.projectLoadingError ?? "Unknown error occurred")
        }
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
