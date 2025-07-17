//
//  ProjectSettingsView.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import SwiftUI

struct ProjectSettingsView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss

    @State private var baseLocale: String
    @State private var locales: [String]
    @State private var pathPattern: String
    @State private var showingAddLocale = false
    @State private var newLocale = ""
    @State private var showingLocaleRemovalAlert = false
    @State private var localeToRemove: String?
    @State private var originalLocales: [String]
    @State private var showingPermissionAlert = false
    @State private var permissionErrorMessage = ""

    init(project: Project) {
        self.project = project
        let currentLocales = project.locales ?? ["en"]
        self._baseLocale = State(initialValue: project.baseLocale ?? "en")
        self._locales = State(initialValue: currentLocales)
        self._pathPattern = State(initialValue: project.pathPattern ?? "./messages/{locale}.json")
        self._originalLocales = State(initialValue: currentLocales)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Project Information Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Project Information")
                            .font(.headline)
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Name:")
                                    .frame(width: 120, alignment: .leading)
                                Text(project.name ?? "Untitled Project")
                                    .foregroundColor(.secondary)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Path:")
                                        .frame(width: 120, alignment: .leading)
                                    Spacer()
                                }
                                Text(project.path ?? "Unknown")
                                    .foregroundColor(.secondary)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(.leading, 120)
                            }

                            HStack {
                                Text("Created:")
                                    .frame(width: 120, alignment: .leading)
                                Text(project.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown")
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }

                    // Localization Settings Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Localization Settings")
                            .font(.headline)
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Base Locale:")
                                    .frame(width: 120, alignment: .leading)
                                TextField("Base locale", text: $baseLocale)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Path Pattern:")
                                        .frame(width: 120, alignment: .leading)
                                    Spacer()
                                }
                                TextField("Path pattern", text: $pathPattern)
                                    .textFieldStyle(.roundedBorder)
                                    .padding(.leading, 120)
                                Text("Use {locale} as placeholder for locale code")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 120)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }

                    // Resolved Paths Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Resolved Locale File Paths")
                            .font(.headline)
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(locales, id: \.self) { locale in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("\(locale):")
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.primary)
                                            .frame(width: 60, alignment: .leading)
                                        if locale == baseLocale {
                                            Text("(Base)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    Text(resolvedPath(for: locale))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                        .padding(.leading, 60)
                                }
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }

                    // Supported Locales Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Supported Locales")
                            .font(.headline)
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(locales, id: \.self) { locale in
                                HStack {
                                    Text(locale)
                                        .font(.system(.body, design: .monospaced))

                                    if locale == baseLocale {
                                        Text("(Base)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if locale != baseLocale {
                                        Button("Remove") {
                                            localeToRemove = locale
                                            showingLocaleRemovalAlert = true
                                        }
                                        .buttonStyle(.borderless)
                                        .foregroundColor(.red)
                                    }
                                }
                            }

                            Divider()

                            HStack {
                                TextField("Add locale (e.g., fr, de, es)", text: $newLocale)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        addLocale()
                                    }

                                Button("Add") {
                                    addLocale()
                                }
                                .disabled(newLocale.isEmpty || locales.contains(newLocale))
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }

                    // Statistics Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Statistics")
                            .font(.headline)
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Total Keys:")
                                    .frame(width: 120, alignment: .leading)
                                Text("\(project.i18nKeys?.count ?? 0)")
                                    .foregroundColor(.secondary)
                                Spacer()
                            }

                            HStack {
                                Text("Total Translations:")
                                    .frame(width: 120, alignment: .leading)
                                Text("\(project.translations?.count ?? 0)")
                                    .foregroundColor(.secondary)
                                Spacer()
                            }

                            HStack {
                                Text("Last Modified:")
                                    .frame(width: 120, alignment: .leading)
                                Text(project.lastOpened?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Project Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSettings()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .alert("Remove Locale", isPresented: $showingLocaleRemovalAlert) {
            Button("Remove from Settings Only", role: .destructive) {
                if let locale = localeToRemove {
                    removeLocaleFromSettings(locale)
                }
            }
            Button("Remove and Move File to Trash", role: .destructive) {
                if let locale = localeToRemove {
                    removeLocaleAndMoveToTrash(locale)
                }
            }
            Button("Cancel", role: .cancel) {
                localeToRemove = nil
            }
        } message: {
            if let locale = localeToRemove {
                Text("How would you like to remove the locale '\(locale)'?\n\nRemove from Settings Only: Keeps the locale file but removes it from the project configuration.\n\nRemove and Move File to Trash: Removes the locale from settings and moves the corresponding file to trash.")
            }
        }
        .alert("Permission Error", isPresented: $showingPermissionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(permissionErrorMessage + "\n\nTo fix this, please close this settings window and reopen the project folder from the main menu.")
        }
    }

    private func addLocale() {
        let trimmedLocale = newLocale.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLocale.isEmpty && !locales.contains(trimmedLocale) {
            locales.append(trimmedLocale)
            newLocale = ""
        }
    }

    private func removeLocaleFromSettings(_ locale: String) {
        locales.removeAll { $0 == locale }
        localeToRemove = nil

        // Save settings to persist the change
        saveSettings()
    }

    private func removeLocaleAndMoveToTrash(_ locale: String) {
        // Remove from settings
        locales.removeAll { $0 == locale }

        // Move file to trash with security-scoped access
        guard let projectPath = project.path else {
            print("Project path not available for file deletion")
            localeToRemove = nil
            saveSettings()
            return
        }

        do {
            try withSecurityScopedAccess(to: projectPath) { projectURL in
                let filePath = resolvedPath(for: locale)
                if FileManager.default.fileExists(atPath: filePath) {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: filePath), resultingItemURL: nil)
                    print("Moved locale file to trash: \(filePath)")
                }
            }
        } catch {
            print("Failed to move locale file to trash: \(error)")
        }

        localeToRemove = nil

        // Save settings to persist the change
        saveSettings()
    }

    private func resolvedPath(for locale: String) -> String {
        guard let projectPath = project.path else {
            return "Project path not set"
        }

        let pattern = pathPattern.replacingOccurrences(of: "{locale}", with: locale)

        // If pattern starts with ./, make it relative to project path
        if pattern.hasPrefix("./") {
            let relativePath = String(pattern.dropFirst(2))
            return URL(fileURLWithPath: projectPath).appendingPathComponent(relativePath).path
        }

        // If pattern is absolute, use as is
        if pattern.hasPrefix("/") {
            return pattern
        }

        // Otherwise, make it relative to project path
        return URL(fileURLWithPath: projectPath).appendingPathComponent(pattern).path
    }

    private func saveSettings() {
        let dataManager = DataManager.shared

        // Detect locale changes
        let addedLocales = Set(locales).subtracting(Set(originalLocales))
        let removedLocales = Set(originalLocales).subtracting(Set(locales))

        // Update project settings
        project.baseLocale = baseLocale
        project.locales = locales
        project.pathPattern = pathPattern

        do {
            try dataManager.viewContext.save()

            // Save to project.inlang/settings.json
            try saveInlangConfiguration()

            // Handle locale changes
            handleLocaleChanges(added: Array(addedLocales), removed: Array(removedLocales))

            // Update original locales to reflect saved state
            originalLocales = locales

            // Reload translation data to reflect changes
            reloadTranslationData()

        } catch {
            print("Failed to save project settings: \(error)")

            // Check if this is a permission error
            if error.localizedDescription.contains("permission") ||
               error.localizedDescription.contains("access") ||
               (error as NSError).code == 513 { // NSFileWriteNoPermissionError
                permissionErrorMessage = "Unable to save settings due to file permissions. Please reopen the project folder to grant write access."
                showingPermissionAlert = true
            } else {
                permissionErrorMessage = "Failed to save project settings: \(error.localizedDescription)"
                showingPermissionAlert = true
            }
        }
    }

    private func handleLocaleChanges(added: [String], removed: [String]) {
        guard let projectPath = project.path else {
            print("Project path not available for locale changes")
            return
        }

        // Create new locale files for added locales with security-scoped access
        for locale in added {
            do {
                try withSecurityScopedAccess(to: projectPath) { projectURL in
                    let filePath = resolvedPath(for: locale)
                    let fileURL = URL(fileURLWithPath: filePath)

                    // Create directory if it doesn't exist
                    let directoryURL = fileURL.deletingLastPathComponent()
                    if !FileManager.default.fileExists(atPath: directoryURL.path) {
                        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                    }

                    // Create empty locale file if it doesn't exist
                    if !FileManager.default.fileExists(atPath: filePath) {
                        let emptyContent: [String: Any] = [:]
                        let data = try JSONSerialization.data(withJSONObject: emptyContent, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                        try data.write(to: fileURL)
                        print("Created new locale file: \(filePath)")
                    }
                }
            } catch {
                print("Failed to create locale file for \(locale): \(error)")
            }
        }

        // Remove translations for removed locales from Core Data
        let dataManager = DataManager.shared
        for locale in removed {
            let translations = dataManager.getTranslations(for: project, locale: locale)
            for translation in translations {
                dataManager.viewContext.delete(translation)
            }
        }

        // Save Core Data changes
        do {
            try dataManager.viewContext.save()
        } catch {
            print("Failed to save Core Data changes after locale updates: \(error)")
        }
    }

    private func saveInlangConfiguration() throws {
        guard let projectPath = project.path else {
            throw NSError(domain: "ProjectSettingsError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Project path is not available"])
        }

        // Try to get security-scoped access to the project directory
        try withSecurityScopedAccess(to: projectPath) { projectURL in
            let configDir = URL(fileURLWithPath: projectPath).appendingPathComponent("project.inlang")
            let configFile = configDir.appendingPathComponent("settings.json")

            // Create directory if it doesn't exist
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

            var existingJson: [String: Any] = [:]

            // Load existing configuration if it exists
            if FileManager.default.fileExists(atPath: configFile.path) {
                let existingData = try Data(contentsOf: configFile)
                existingJson = try JSONSerialization.jsonObject(with: existingData) as? [String: Any] ?? [:]
            }

            // Update only the specific fields we care about
            existingJson["baseLocale"] = baseLocale
            existingJson["locales"] = locales

            // Update pathPattern in the plugin.inlang.messageFormat section
            existingJson["plugin.inlang.messageFormat"] = [
                "pathPattern": pathPattern
            ]

            // Ensure $schema is present
            if existingJson["$schema"] == nil {
                existingJson["$schema"] = "https://inlang.com/schema/project-settings"
            }

            // Write updated configuration back to file
            let jsonData = try JSONSerialization.data(withJSONObject: existingJson, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try jsonData.write(to: configFile)

            print("Successfully saved inlang configuration to \(projectPath)/project.inlang/settings.json")
        }
    }


    private func withSecurityScopedAccess<T>(to projectPath: String, operation: (URL) throws -> T) throws -> T {
        // Try to restore security-scoped access from bookmark
        if let bookmarkData = UserDefaults.standard.data(forKey: "bookmark_\(projectPath)") {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

                if isStale {
                    throw NSError(domain: "ProjectSettingsError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Project access permissions have expired. Please reopen the project folder."])
                }

                guard url.startAccessingSecurityScopedResource() else {
                    throw NSError(domain: "ProjectSettingsError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to access project folder. Please reopen the project."])
                }

                defer { url.stopAccessingSecurityScopedResource() }
                return try operation(url)

            } catch {
                if error.localizedDescription.contains("ProjectSettingsError") {
                    throw error
                } else {
                    throw NSError(domain: "ProjectSettingsError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unable to access project folder. Please reopen the project to grant permissions again."])
                }
            }
        } else {
            throw NSError(domain: "ProjectSettingsError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Project access permissions not found. Please reopen the project folder to grant write permissions."])
        }
    }

    private func reloadTranslationData() {
        // Post notification to reload translation data on main thread
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("ProjectSettingsChanged"),
                object: self.project
            )
        }
    }

    private func findProjectManager() -> ProjectManager? {
        // For now, we'll show a simpler message since we can't easily access ProjectManager from here
        return nil
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let project = Project(context: context)
    project.name = "Sample Project"
    project.path = "/path/to/project"
    project.baseLocale = "en"
    project.locales = ["en", "fr", "de"]
    project.pathPattern = "./messages/{locale}.json"
    project.createdAt = Date()
    project.lastOpened = Date()

    return ProjectSettingsView(project: project)
}
