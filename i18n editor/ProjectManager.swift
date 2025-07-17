//
//  ProjectManager.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Manages project operations including folder selection, validation, and project lifecycle
class ProjectManager: ObservableObject {
    @Published var currentProject: Project?
    @Published var isProjectLoaded = false
    @Published var projectLoadingError: String?

    private let dataManager = DataManager.shared
    private let fileManager = FileManager.default

    // Security-scoped bookmark storage
    private var securityScopedBookmarks: [String: Data] = [:]

    // MARK: - Initialization

    init() {
        loadStoredBookmarks()
    }

    // MARK: - Project Selection and Creation

    /// Open folder selection dialog and create/load project
    func selectProjectFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select SvelteKit Project Folder"
        panel.message = "Choose the root folder of your SvelteKit project"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        // Set allowed content types
        panel.allowedContentTypes = [UTType.folder]

        panel.begin { [weak self] response in
            DispatchQueue.main.async {
                if response == .OK, let url = panel.url {
                    self?.loadProject(from: url)
                }
            }
        }
    }

    /// Load or create project from URL
    func loadProject(from url: URL) {
        projectLoadingError = nil

        // Start accessing security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            // If we can't access the folder, suggest full disk access
            requestFullDiskAccessIfNeeded()
            projectLoadingError = "Unable to access the selected project folder. Please grant Full Disk Access in System Preferences or try selecting the folder again."
            return
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        // Validate that this is a valid SvelteKit project
        guard validateSvelteKitProject(at: url) else {
            projectLoadingError = "Selected folder is not a valid SvelteKit project. Please ensure it contains a 'src' directory and package.json file."
            return
        }

        let projectPath = url.path
        let projectName = url.lastPathComponent

        // Create and store security-scoped bookmark
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            securityScopedBookmarks[projectPath] = bookmarkData

            // Store bookmark in user defaults for persistence
            UserDefaults.standard.set(bookmarkData, forKey: "bookmark_\(projectPath)")
        } catch {
            print("Failed to create security-scoped bookmark: \(error)")
            projectLoadingError = "Failed to create security bookmark for project access. Some features may not work properly."
        }

        // Check if project already exists in database
        if let existingProject = findExistingProject(path: projectPath) {
            currentProject = existingProject
            dataManager.updateProjectLastOpened(existingProject)
        } else {
            // Create new project
            currentProject = dataManager.createProject(name: projectName, path: projectPath)
        }

        // Load project configuration with security-scoped access
        loadProjectConfiguration(with: url)

        // Load translation data from JSON files
        loadTranslationData(with: url)

        isProjectLoaded = true
    }

    /// Validate that the selected folder is a SvelteKit project
    private func validateSvelteKitProject(at url: URL) -> Bool {
        let srcPath = url.appendingPathComponent("src")
        let packageJsonPath = url.appendingPathComponent("package.json")

        // Check for src directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: srcPath.path, isDirectory: &isDirectory) && isDirectory.boolValue else {
            return false
        }

        // Check for package.json
        guard fileManager.fileExists(atPath: packageJsonPath.path) else {
            return false
        }

        // Optional: Check package.json for SvelteKit dependencies
        if let packageData = try? Data(contentsOf: packageJsonPath),
           let packageJson = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any] {

            let dependencies = packageJson["dependencies"] as? [String: Any] ?? [:]
            let devDependencies = packageJson["devDependencies"] as? [String: Any] ?? [:]

            let allDependencies = dependencies.merging(devDependencies) { _, new in new }

            // Look for SvelteKit indicators
            let svelteKitIndicators = ["@sveltejs/kit", "svelte", "@sveltejs/adapter-auto"]
            let hasSvelteKit = svelteKitIndicators.contains { allDependencies.keys.contains($0) }

            if !hasSvelteKit {
                print("Warning: No SvelteKit dependencies found in package.json")
            }
        }

        return true
    }

    /// Find existing project in database
    private func findExistingProject(path: String) -> Project? {
        let projects = dataManager.getAllProjects()
        return projects.first { $0.path == path }
    }

    /// Load project configuration from inlang settings
    private func loadProjectConfiguration(with projectURL: URL) {
        guard let project = currentProject else { return }

        let inlangConfigPath = projectURL.appendingPathComponent("project.inlang/settings.json")

        if fileManager.fileExists(atPath: inlangConfigPath.path) {
            loadInlangConfiguration(from: inlangConfigPath, for: project, projectURL: projectURL)
        } else {
            // Set default configuration
            project.baseLocale = "en"
            project.locales = ["en"]
            project.pathPattern = "./messages/{locale}.json"
            try? dataManager.viewContext.save()
        }
    }

    /// Legacy method for backward compatibility
    private func loadProjectConfiguration() {
        guard let project = currentProject,
              let projectPath = project.path else { return }

        // Try to restore security-scoped access from bookmark
        if let bookmarkData = securityScopedBookmarks[projectPath] ?? UserDefaults.standard.data(forKey: "bookmark_\(projectPath)") {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

                if isStale {
                    print("Security-scoped bookmark is stale for project: \(projectPath)")
                    requestFullDiskAccessIfNeeded()
                    projectLoadingError = "Project access permissions have expired. Please grant Full Disk Access or reopen the project folder."
                    return
                }

                guard url.startAccessingSecurityScopedResource() else {
                    requestFullDiskAccessIfNeeded()
                    projectLoadingError = "Unable to access project folder. Please grant Full Disk Access or reopen the project."
                    return
                }

                defer { url.stopAccessingSecurityScopedResource() }
                loadProjectConfiguration(with: url)
                loadTranslationData(with: url)

            } catch {
                print("Failed to resolve security-scoped bookmark: \(error)")
                projectLoadingError = "Unable to access project folder. Please reopen the project."
            }
        } else {
            projectLoadingError = "Project access permissions not found. Please reopen the project folder."
        }
    }

    /// Load inlang configuration from settings.json
    private func loadInlangConfiguration(from url: URL, for project: Project, projectURL: URL) {
        do {
            let data = try Data(contentsOf: url)
            let config = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            project.inlangConfigPath = url.path

            if let baseLocale = config?["baseLocale"] as? String {
                project.baseLocale = baseLocale
            }

            if let locales = config?["locales"] as? [String] {
                project.locales = locales
            }

            // Extract path pattern from messageFormat plugin settings
            if let messageFormat = config?["plugin.inlang.messageFormat"] as? [String: Any],
               let pathPattern = messageFormat["pathPattern"] as? String {
                project.pathPattern = pathPattern
            }

            try dataManager.viewContext.save()

        } catch {
            print("Error loading inlang configuration: \(error)")
            projectLoadingError = "Failed to load inlang configuration: \(error.localizedDescription)"
        }
    }

    /// Load translation data from JSON files into Core Data
    private func loadTranslationData(with projectURL: URL) {
        guard let project = currentProject else { return }

        print("Loading translation data for project: \(project.name ?? "Unknown")")

        // Get locale files using FileSystemManager
        let fileSystemManager = FileSystemManager()
        let localeFiles = fileSystemManager.getLocaleFiles(for: project)

        print("Found \(localeFiles.count) locale files")

        // Process each locale file
        for localeFile in localeFiles {
            guard localeFile.exists else {
                print("Locale file does not exist: \(localeFile.path)")
                continue
            }

            print("Processing locale file: \(localeFile.locale) at \(localeFile.path)")

            // Flatten the JSON content to get all keys
            let flattenedKeys = flattenJSONKeys(localeFile.content)

            print("Found \(flattenedKeys.count) keys in \(localeFile.locale)")

            // Create or update i18n keys and translations
            for (key, value) in flattenedKeys {
                // Create or update the i18n key
                let i18nKey = dataManager.createOrUpdateI18nKey(
                    key: key,
                    project: project,
                    namespace: nil
                )

                // Create or update the translation
                let stringValue = convertValueToString(value)
                _ = dataManager.createOrUpdateTranslation(
                    i18nKey: i18nKey,
                    locale: localeFile.locale,
                    value: stringValue,
                    isDraft: false
                )
            }
        }

        // Save all changes
        do {
            try dataManager.viewContext.save()
            print("Successfully loaded translation data into Core Data")
        } catch {
            print("Error saving translation data: \(error)")
            projectLoadingError = "Failed to load translation data: \(error.localizedDescription)"
        }
    }

    /// Flatten nested JSON keys into dot notation
    private func flattenJSONKeys(_ json: [String: Any], prefix: String = "") -> [String: Any] {
        var flattened: [String: Any] = [:]

        for (key, value) in json {
            let fullKey = prefix.isEmpty ? key : "\(prefix).\(key)"

            if let nestedDict = value as? [String: Any] {
                // Recursively flatten nested objects
                let nestedFlattened = flattenJSONKeys(nestedDict, prefix: fullKey)
                flattened.merge(nestedFlattened) { _, new in new }
            } else {
                // Store the value with the flattened key
                flattened[fullKey] = value
            }
        }

        return flattened
    }

    /// Convert any value to string for storage
    private func convertValueToString(_ value: Any) -> String {
        if let stringValue = value as? String {
            return stringValue
        } else if let numberValue = value as? NSNumber {
            return numberValue.stringValue
        } else if let boolValue = value as? Bool {
            return boolValue ? "true" : "false"
        } else {
            return String(describing: value)
        }
    }

    // MARK: - Project Management

    /// Close current project
    func closeProject() {
        currentProject = nil
        isProjectLoaded = false
        projectLoadingError = nil
    }

    /// Get recent projects
    func getRecentProjects() -> [RecentProject] {
        let preferences = dataManager.getUserPreferences()
        let recentPaths = preferences.recentProjects ?? []

        return recentPaths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            let name = url.lastPathComponent

            // Check if project still exists
            guard fileManager.fileExists(atPath: path) else { return nil }

            // Get last modified date
            let attributes = try? fileManager.attributesOfItem(atPath: path)
            let lastModified = attributes?[.modificationDate] as? Date ?? Date.distantPast

            return RecentProject(
                name: name,
                path: path,
                lastModified: lastModified,
                exists: true
            )
        }
    }

    /// Open recent project
    func openRecentProject(_ recentProject: RecentProject) {
        let projectPath = recentProject.path

        // Try to restore security-scoped access from bookmark
        if let bookmarkData = securityScopedBookmarks[projectPath] ?? UserDefaults.standard.data(forKey: "bookmark_\(projectPath)") {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

                if isStale {
                    print("Security-scoped bookmark is stale for recent project: \(projectPath)")
                    // Fall back to asking user to select the folder again
                    projectLoadingError = "Access to this project has expired. Please select the project folder again."
                    return
                }

                loadProject(from: url)

            } catch {
                print("Failed to resolve security-scoped bookmark for recent project: \(error)")
                // Fall back to asking user to select the folder again
                projectLoadingError = "Unable to access this project. Please select the project folder again."
            }
        } else {
            // No bookmark found, ask user to select the folder again
            projectLoadingError = "Project access permissions not found. Please select the project folder again."
        }
    }

    /// Remove project from recent list
    func removeFromRecentProjects(_ recentProject: RecentProject) {
        let preferences = dataManager.getUserPreferences()
        preferences.removeRecentProject(recentProject.path)
        try? dataManager.viewContext.save()

        // Clean up security-scoped bookmark
        cleanupSecurityScopedBookmark(for: recentProject.path)
    }

    /// Request permission renewal for current project
    func requestPermissionRenewal() {
        guard let project = currentProject, let projectPath = project.path else {
            projectLoadingError = "No current project to renew permissions for."
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Renew Project Access"
        panel.message = "Please select the project folder again to renew write permissions"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [UTType.folder]

        // Try to navigate to the project directory
        if let projectURL = URL(string: "file://\(projectPath)") {
            panel.directoryURL = projectURL.deletingLastPathComponent()
        }

        panel.begin { [weak self] response in
            DispatchQueue.main.async {
                if response == .OK, let url = panel.url {
                    // Verify this is the same project
                    if url.path == projectPath {
                        // Update the security-scoped bookmark
                        do {
                            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                            self?.securityScopedBookmarks[projectPath] = bookmarkData
                            UserDefaults.standard.set(bookmarkData, forKey: "bookmark_\(projectPath)")
                            self?.projectLoadingError = nil
                            print("Successfully renewed permissions for project: \(projectPath)")
                        } catch {
                            self?.projectLoadingError = "Failed to renew project permissions: \(error.localizedDescription)"
                        }
                    } else {
                        self?.projectLoadingError = "Selected folder does not match the current project. Please select the correct project folder."
                    }
                }
            }
        }
    }

    /// Clear all recent projects
    func clearRecentProjects() {
        let preferences = dataManager.getUserPreferences()

        // Clean up all security-scoped bookmarks for recent projects
        for projectPath in preferences.recentProjects ?? [] {
            cleanupSecurityScopedBookmark(for: projectPath)
        }

        preferences.recentProjects = []
        try? dataManager.viewContext.save()
    }

    // MARK: - Project Information

    /// Get project information for display
    func getProjectInfo() -> ProjectInfo? {
        guard let project = currentProject else { return nil }

        let statistics = project.statistics

        return ProjectInfo(
            name: project.name ?? "Unknown",
            path: project.path ?? "",
            baseLocale: project.baseLocale ?? "en",
            locales: project.allLocales,
            pathPattern: project.pathPattern ?? "./messages/{locale}.json",
            statistics: statistics,
            lastOpened: project.lastOpened ?? Date(),
            hasInlangConfig: project.inlangConfigPath != nil
        )
    }

    /// Check if project has unsaved changes
    var hasUnsavedChanges: Bool {
        return currentProject?.hasUnsavedChanges ?? false
    }

    // MARK: - Security-Scoped Bookmark Management

    /// Clean up security-scoped bookmark for a project path
    private func cleanupSecurityScopedBookmark(for projectPath: String) {
        securityScopedBookmarks.removeValue(forKey: projectPath)
        UserDefaults.standard.removeObject(forKey: "bookmark_\(projectPath)")
    }

    /// Load all stored security-scoped bookmarks on app launch
    func loadStoredBookmarks() {
        let userDefaults = UserDefaults.standard
        let allKeys = userDefaults.dictionaryRepresentation().keys

        for key in allKeys {
            if key.hasPrefix("bookmark_"),
               let bookmarkData = userDefaults.data(forKey: key) {
                let projectPath = String(key.dropFirst("bookmark_".count))
                securityScopedBookmarks[projectPath] = bookmarkData
            }
        }
    }

    /// Request Full Disk Access by opening System Preferences
    private func requestFullDiskAccessIfNeeded() {
        // Check if we already have full disk access by trying to read a protected file
        if !hasFullDiskAccess() {
            DispatchQueue.main.async {
                self.openFullDiskAccessSettings()
            }
        }
    }

    /// Check if the app has Full Disk Access
    private func hasFullDiskAccess() -> Bool {
        // Try to access a file that requires Full Disk Access
        let testPaths = [
            NSHomeDirectory() + "/Library/Safari/Bookmarks.plist",
            "/Library/Application Support/com.apple.TCC/TCC.db",
            "/Library/Preferences/com.apple.TimeMachine.plist"
        ]

        for path in testPaths {
            if FileManager.default.isReadableFile(atPath: path) {
                return true
            }
        }

        return false
    }

    /// Open System Preferences to Full Disk Access section
    private func openFullDiskAccessSettings() {
        let alert = NSAlert()
        alert.messageText = "Full Disk Access Required"
        alert.informativeText = "This app needs Full Disk Access to read and write project files. Click 'Open Settings' to grant permission in System Preferences."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            // Open System Preferences to Privacy & Security > Full Disk Access
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Get draft translations count
    var draftTranslationsCount: Int {
        return currentProject?.draftTranslationsCount ?? 0
    }
}

// MARK: - Supporting Types

struct RecentProject: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let lastModified: Date
    let exists: Bool
}

struct ProjectInfo {
    let name: String
    let path: String
    let baseLocale: String
    let locales: [String]
    let pathPattern: String
    let statistics: ProjectStatistics
    let lastOpened: Date
    let hasInlangConfig: Bool
}

// MARK: - AppKit Integration

#if canImport(AppKit)
import AppKit

extension ProjectManager {
    /// Show save dialog before closing project with unsaved changes
    func confirmCloseProject(completion: @escaping (Bool) -> Void) {
        guard hasUnsavedChanges else {
            completion(true)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Save changes before closing?"
        alert.informativeText = "You have \(draftTranslationsCount) unsaved translations. Do you want to save them before closing the project?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn: // Save
            // TODO: Implement save functionality
            completion(true)
        case .alertSecondButtonReturn: // Don't Save
            completion(true)
        default: // Cancel
            completion(false)
        }
    }
}
#endif
