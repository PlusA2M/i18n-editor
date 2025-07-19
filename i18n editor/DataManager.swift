//
//  DataManager.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import Foundation
import CoreData
import SwiftUI

/// Main data manager for handling Core Data operations and business logic
class DataManager: ObservableObject {
    static let shared = DataManager()

    private let persistenceController = PersistenceController.shared

    var viewContext: NSManagedObjectContext {
        persistenceController.container.viewContext
    }

    private init() {}

    // MARK: - Project Management

    /// Create a new project
    func createProject(name: String, path: String) -> Project {
        let project = Project(context: viewContext)
        project.id = UUID()
        project.name = name
        project.path = path
        project.createdAt = Date()
        project.lastOpened = Date()

        saveContext()
        addToRecentProjects(path: path)

        return project
    }

    /// Get all projects
    func getAllProjects() -> [Project] {
        let request: NSFetchRequest<Project> = Project.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Project.lastOpened, ascending: false)]

        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching projects: \(error)")
            return []
        }
    }

    /// Update project's last opened date
    func updateProjectLastOpened(_ project: Project) {
        project.lastOpened = Date()
        saveContext()
        addToRecentProjects(path: project.path ?? "")
    }

    /// Delete a project and all its related data
    func deleteProject(_ project: Project) {
        viewContext.delete(project)
        saveContext()
    }

    // MARK: - I18n Key Management

    /// Create or update an i18n key (must be called from main thread)
    func createOrUpdateI18nKey(key: String, project: Project, namespace: String? = nil) -> I18nKey {
        // Assert we're on the main thread
        assert(Thread.isMainThread, "createOrUpdateI18nKey must be called from main thread")

        // Check if key already exists
        if let existingKey = getI18nKey(key: key, project: project) {
            existingKey.lastModified = Date()
            // Don't save context here - let caller handle batching
            return existingKey
        }

        // Create new key
        let i18nKey = I18nKey(context: viewContext)
        i18nKey.id = UUID()
        i18nKey.key = key
        i18nKey.namespace = namespace
        i18nKey.project = project
        i18nKey.detectedAt = Date()
        i18nKey.lastModified = Date()
        i18nKey.isNested = key.contains(".")

        if i18nKey.isNested {
            let components = key.components(separatedBy: ".")
            if components.count > 1 {
                i18nKey.parentKey = components.dropLast().joined(separator: ".")
            }
        }

        // Don't save context here - let caller handle batching
        return i18nKey
    }

    /// Get an i18n key by key string and project (must be called from main thread)
    func getI18nKey(key: String, project: Project) -> I18nKey? {
        // Assert we're on the main thread
        assert(Thread.isMainThread, "getI18nKey must be called from main thread")

        let request: NSFetchRequest<I18nKey> = I18nKey.fetchRequest()
        request.predicate = NSPredicate(format: "key == %@ AND project == %@", key, project)
        request.fetchLimit = 1

        do {
            return try viewContext.fetch(request).first
        } catch {
            print("Error fetching i18n key: \(error)")
            return nil
        }
    }

    /// Get all i18n keys for a project
    func getI18nKeys(for project: Project) -> [I18nKey] {
        let request: NSFetchRequest<I18nKey> = I18nKey.fetchRequest()
        request.predicate = NSPredicate(format: "project == %@", project)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \I18nKey.key, ascending: true)]

        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching i18n keys: \(error)")
            return []
        }
    }

    // MARK: - Translation Management

    /// Create or update a translation
    func createOrUpdateTranslation(i18nKey: I18nKey, locale: String, value: String?, isDraft: Bool = false) -> Translation {
        // Check if translation already exists
        if let existingTranslation = getTranslation(i18nKey: i18nKey, locale: locale) {
            if isDraft {
                existingTranslation.draftValue = value
                existingTranslation.isDraft = true
                existingTranslation.hasUnsavedChanges = existingTranslation.value != value
            } else {
                existingTranslation.value = value
                existingTranslation.draftValue = nil
                existingTranslation.isDraft = false
                existingTranslation.hasUnsavedChanges = false
            }
            existingTranslation.lastModified = Date()
            saveContext()
            return existingTranslation
        }

        // Create new translation
        let translation = Translation(context: viewContext)
        translation.id = UUID()
        translation.locale = locale
        translation.i18nKey = i18nKey
        translation.project = i18nKey.project
        translation.lastModified = Date()
        translation.isValid = true

        if isDraft {
            translation.draftValue = value
            translation.isDraft = true
            translation.hasUnsavedChanges = true
        } else {
            translation.value = value
            translation.isDraft = false
            translation.hasUnsavedChanges = false
        }

        saveContext()
        return translation
    }

    /// Get a translation for a specific key and locale
    func getTranslation(i18nKey: I18nKey, locale: String) -> Translation? {
        let request: NSFetchRequest<Translation> = Translation.fetchRequest()
        request.predicate = NSPredicate(format: "i18nKey == %@ AND locale == %@", i18nKey, locale)
        request.fetchLimit = 1

        do {
            return try viewContext.fetch(request).first
        } catch {
            print("Error fetching translation: \(error)")
            return nil
        }
    }

    /// Get all translations for a project and locale
    func getTranslations(for project: Project, locale: String) -> [Translation] {
        let request: NSFetchRequest<Translation> = Translation.fetchRequest()
        request.predicate = NSPredicate(format: "project == %@ AND locale == %@", project, locale)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Translation.i18nKey?.key, ascending: true)]

        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching translations: \(error)")
            return []
        }
    }

    /// Save all draft translations to actual values
    func saveDraftTranslations(for project: Project) {
        let request: NSFetchRequest<Translation> = Translation.fetchRequest()
        request.predicate = NSPredicate(format: "project == %@ AND isDraft == YES", project)

        do {
            let draftTranslations = try viewContext.fetch(request)
            for translation in draftTranslations {
                translation.value = translation.draftValue
                translation.draftValue = nil
                translation.isDraft = false
                translation.hasUnsavedChanges = false
                translation.lastModified = Date()
            }
            saveContext()
        } catch {
            print("Error saving draft translations: \(error)")
        }
    }

    // MARK: - File Usage Management

    /// Record file usage for an i18n key (must be called from main thread)
    func recordFileUsage(i18nKey: I18nKey, filePath: String, lineNumber: Int32, columnNumber: Int32? = nil, context: String? = nil) -> FileUsage {
        // Assert we're on the main thread
        assert(Thread.isMainThread, "recordFileUsage must be called from main thread")

        // Check if usage already exists
        let request: NSFetchRequest<FileUsage> = FileUsage.fetchRequest()
        request.predicate = NSPredicate(format: "i18nKey == %@ AND filePath == %@ AND lineNumber == %d", i18nKey, filePath, lineNumber)
        request.fetchLimit = 1

        if let existingUsage = try? viewContext.fetch(request).first {
            existingUsage.isActive = true
            existingUsage.detectedAt = Date()
            existingUsage.context = context
            // Don't save context here - let caller handle batching
            return existingUsage
        }

        // Create new usage record
        let fileUsage = FileUsage(context: viewContext)
        fileUsage.id = UUID()
        fileUsage.i18nKey = i18nKey
        fileUsage.project = i18nKey.project
        fileUsage.filePath = filePath
        fileUsage.lineNumber = lineNumber
        fileUsage.columnNumber = columnNumber ?? 0
        fileUsage.context = context
        fileUsage.detectedAt = Date()
        fileUsage.isActive = true

        // Don't save context here - let caller handle batching
        return fileUsage
    }

    /// Mark file usages as inactive (for cleanup)
    func markFileUsagesInactive(for project: Project, filePath: String) {
        let request: NSFetchRequest<FileUsage> = FileUsage.fetchRequest()
        request.predicate = NSPredicate(format: "project == %@ AND filePath == %@", project, filePath)

        do {
            let usages = try viewContext.fetch(request)
            for usage in usages {
                usage.isActive = false
            }
            saveContext()
        } catch {
            print("Error marking file usages inactive: \(error)")
        }
    }

    // MARK: - User Preferences

    /// Get or create user preferences
    func getUserPreferences() -> UserPreferences {
        let request: NSFetchRequest<UserPreferences> = UserPreferences.fetchRequest()
        request.fetchLimit = 1

        if let preferences = try? viewContext.fetch(request).first {
            return preferences
        }

        // Create default preferences
        let preferences = UserPreferences(context: viewContext)
        preferences.id = UUID()
        preferences.recentProjects = []
        preferences.maxRecentProjects = 10
        preferences.autoSaveInterval = 30
        preferences.enableAutoRefactoring = false
        preferences.showLineNumbers = true
        preferences.enableBackup = true

        saveContext()
        return preferences
    }

    /// Add project to recent projects list
    private func addToRecentProjects(path: String) {
        let preferences = getUserPreferences()
        var recentProjects = preferences.recentProjects ?? []

        // Remove if already exists
        recentProjects.removeAll { $0 == path }

        // Add to beginning
        recentProjects.insert(path, at: 0)

        // Limit to max recent projects
        if recentProjects.count > Int(preferences.maxRecentProjects) {
            recentProjects = Array(recentProjects.prefix(Int(preferences.maxRecentProjects)))
        }

        preferences.recentProjects = recentProjects
        saveContext()
    }

    // MARK: - Core Data Operations

    /// Save the managed object context
    func saveContext() {
        // Ensure we're on the main thread for Core Data operations
        if Thread.isMainThread {
            do {
                try viewContext.save()
            } catch {
                print("Error saving context: \(error)")
            }
        } else {
            DispatchQueue.main.async {
                do {
                    try self.viewContext.save()
                } catch {
                    print("Error saving context: \(error)")
                }
            }
        }
    }
}
