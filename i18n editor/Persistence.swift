//
//  Persistence.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext

        // Create sample project for preview
        let sampleProject = Project(context: viewContext)
        sampleProject.id = UUID()
        sampleProject.name = "Sample Project"
        sampleProject.path = "/path/to/sample/project"
        sampleProject.baseLocale = "en"
        sampleProject.locales = ["en", "fr", "de"]
        sampleProject.pathPattern = "./messages/{locale}.json"
        sampleProject.createdAt = Date()
        sampleProject.lastOpened = Date()

        // Create sample i18n keys
        for i in 0..<5 {
            let key = I18nKey(context: viewContext)
            key.id = UUID()
            key.key = "sample.key.\(i)"
            key.detectedAt = Date()
            key.project = sampleProject
        }

        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "i18n_editor")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
