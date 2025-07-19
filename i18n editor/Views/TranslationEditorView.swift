//
//  TranslationEditorView.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import SwiftUI



struct TranslationEditorView: View {
    @StateObject private var dataManager = DataManager.shared
    @StateObject private var usageTracker = UsageTrackingSystem()
    @StateObject private var localeManager = LocaleFileManager()

    @State private var project: Project
    @State private var selectedKeys: Set<String> = []
    @State private var searchText = ""
    @State private var showingSettings = false
    @State private var showingValidation = false
    @State private var showingSmartRefactoring = false
    @State private var showingUsageDebug = false
    @State private var sortOrder: SortOrder = .alphabetical
    @State private var filterOption: FilterOption = .all
    @State private var hasUnsavedChanges = false

    init(project: Project) {
        self._project = State(initialValue: project)
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar with project info and filters
            VStack(alignment: .leading, spacing: 16) {
                ProjectInfoSection(project: project)

                Divider()

                FilterSection(
                    searchText: $searchText,
                    sortOrder: $sortOrder,
                    filterOption: $filterOption
                )

                Divider()

                StatisticsSection(statistics: usageTracker.usageStatistics, usageTracker: usageTracker)

                Spacer()
            }
            .padding()
            .frame(minWidth: 250, maxWidth: 300)
            .background(Color(NSColor.controlBackgroundColor))
        } detail: {
            // Main translation table
            TranslationTableView(
                project: project,
                searchText: searchText,
                sortOrder: sortOrder,
                filterOption: filterOption,
                selectedKeys: $selectedKeys
            )
        }
        .navigationTitle("Translation Editor")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Smart Refactor") {
                    showingSmartRefactoring = true
                }
                .help("Automatically reorganize and optimize translation files")

                Button("Validate") {
                    showingValidation = true
                }
                .help("Validate translations")

                Button("Save All") {
                    saveAllTranslations()
                }
                .help("Save all draft translations to files")
                .disabled(!hasUnsavedChanges)

                Button("Usage") {
                    showingUsageDebug = true
                }
                .help("Usage tracking details and debugging")

                Button("Settings") {
                    showingSettings = true
                }
                .help("Project settings")
            }
        }
        .onAppear {
            usageTracker.startTracking(project: project)
            updateUnsavedChangesState()
        }
        .onDisappear {
            usageTracker.stopTracking()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ProjectSettingsChanged"))) { notification in
            if let notificationProject = notification.object as? Project,
               notificationProject.objectID == project.objectID {
                // Reload translation data when project settings change
                reloadProjectData()
                updateUnsavedChangesState()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SaveAllTranslations"))) { notification in
            if let notificationProject = notification.object as? Project,
               notificationProject.objectID == project.objectID {
                // Save all translations when requested from other views
                saveAllTranslations()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            // Update save button state when Core Data context saves
            updateUnsavedChangesState()
        }
        .sheet(isPresented: $showingSettings) {
            ProjectSettingsView(project: project)
        }
        .sheet(isPresented: $showingValidation) {
            ValidationResultsView(project: project)
        }
        .sheet(isPresented: $showingSmartRefactoring) {
            SmartRefactoringView(project: project)
        }
        .sheet(isPresented: $showingUsageDebug) {
            UsageTrackingDebugView(project: project, usageTracker: usageTracker)
        }
    }

    private func saveAllTranslations() {
        guard let projectPath = project.path else {
            print("Project path not available for saving translations")
            return
        }

        // First save draft translations to Core Data
        dataManager.saveDraftTranslations(for: project)

        // Then write all translations to locale files
        Task {
            await writeTranslationsToFiles(projectPath: projectPath)

            DispatchQueue.main.async {
                // Update the unsaved changes state
                self.updateUnsavedChangesState()
                print("Successfully saved all translations to files")
            }
        }
    }

    private func updateUnsavedChangesState() {
        hasUnsavedChanges = project.hasUnsavedChanges
    }

    /// Write all translations to locale files with security-scoped access
    private func writeTranslationsToFiles(projectPath: String) async {
        do {
            // Parse inlang configuration to get path pattern and locales
            let configParser = InlangConfigParser()
            guard let config = configParser.parseConfiguration(projectPath: projectPath) else {
                print("Failed to parse inlang configuration")
                return
            }

            // Use security-scoped access for file operations
            try await withSecurityScopedAccess(to: projectPath) { projectURL in
                // Get all translations for this project grouped by locale
                let allTranslations = project.translations?.allObjects as? [Translation] ?? []
                let translationsByLocale = Dictionary(grouping: allTranslations) { $0.locale ?? "" }

                // Process each locale
                for locale in config.locales {
                    let localeTranslations = translationsByLocale[locale] ?? []

                    // Build nested JSON structure from translations
                    var localeContent: [String: Any] = [:]

                    for translation in localeTranslations {
                        guard let key = translation.i18nKey?.key,
                              let value = translation.value else { continue }

                        // Set nested value in JSON structure
                        setNestedValue(in: &localeContent, keyPath: key, value: value)
                    }

                    // Resolve file path for this locale
                    let filePath = resolvePathPattern(config.pathPattern ?? "./messages/{locale}.json",
                                                    locale: locale,
                                                    projectPath: projectPath)

                    // Save to file
                    try await saveLocaleContentToFile(content: localeContent,
                                                    filePath: filePath,
                                                    projectPath: projectPath)

                    print("Saved \(localeTranslations.count) translations to \(filePath)")
                }
            }
        } catch {
            print("Error writing translations to files: \(error)")
        }
    }

    /// Helper method for security-scoped access
    private func withSecurityScopedAccess<T>(to projectPath: String, operation: (URL) async throws -> T) async throws -> T {
        // Try to restore security-scoped access from bookmark
        if let bookmarkData = UserDefaults.standard.data(forKey: "bookmark_\(projectPath)") {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

                if isStale {
                    throw NSError(domain: "TranslationEditorError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Project access permissions have expired. Please reopen the project folder."])
                }

                guard url.startAccessingSecurityScopedResource() else {
                    throw NSError(domain: "TranslationEditorError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to access project folder. Please reopen the project."])
                }

                defer { url.stopAccessingSecurityScopedResource() }
                return try await operation(url)

            } catch {
                throw NSError(domain: "TranslationEditorError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unable to access project folder. Please reopen the project to grant permissions again."])
            }
        } else {
            throw NSError(domain: "TranslationEditorError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Project access permissions not found. Please reopen the project folder."])
        }
    }

    /// Resolve path pattern to actual file path
    private func resolvePathPattern(_ pathPattern: String, locale: String, projectPath: String) -> String {
        let resolvedPattern = pathPattern.replacingOccurrences(of: "{locale}", with: locale)

        if resolvedPattern.hasPrefix("./") {
            return URL(fileURLWithPath: projectPath).appendingPathComponent(String(resolvedPattern.dropFirst(2))).path
        } else if resolvedPattern.hasPrefix("/") {
            return resolvedPattern
        } else {
            return URL(fileURLWithPath: projectPath).appendingPathComponent(resolvedPattern).path
        }
    }

    /// Set nested value in JSON structure using dot notation key path
    private func setNestedValue(in dict: inout [String: Any], keyPath: String, value: String) {
        let keys = keyPath.components(separatedBy: ".")

        if keys.count == 1 {
            dict[keys[0]] = value
            return
        }

        var current = dict
        for (index, key) in keys.enumerated() {
            if index == keys.count - 1 {
                // Last key, set the value
                current[key] = value
            } else {
                // Intermediate key, ensure it's a dictionary
                if current[key] == nil {
                    current[key] = [String: Any]()
                }
                if let nextDict = current[key] as? [String: Any] {
                    current = nextDict
                } else {
                    // If it's not a dictionary, create a new one
                    let newDict = [String: Any]()
                    current[key] = newDict
                    current = newDict
                }
            }
        }

        // Update the original dictionary with changes
        dict = updateNestedDict(dict, keys: keys, value: value, index: 0)
    }

    /// Helper method to update nested dictionary
    private func updateNestedDict(_ dict: [String: Any], keys: [String], value: String, index: Int) -> [String: Any] {
        var result = dict
        let key = keys[index]

        if index == keys.count - 1 {
            result[key] = value
        } else {
            if let nestedDict = result[key] as? [String: Any] {
                result[key] = updateNestedDict(nestedDict, keys: keys, value: value, index: index + 1)
            } else {
                result[key] = updateNestedDict([:], keys: keys, value: value, index: index + 1)
            }
        }

        return result
    }

    /// Save locale content to file
    private func saveLocaleContentToFile(content: [String: Any], filePath: String, projectPath: String) async throws {
        let fileURL = URL(fileURLWithPath: filePath)
        let directoryURL = fileURL.deletingLastPathComponent()

        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        // Create backup before overwriting
        if FileManager.default.fileExists(atPath: filePath) {
            let backupPath = filePath + ".backup.\(Int(Date().timeIntervalSince1970))"
            try FileManager.default.copyItem(atPath: filePath, toPath: backupPath)
        }

        // Serialize and write content
        let data = try JSONSerialization.data(withJSONObject: content, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: fileURL)
    }

    private func reloadProjectData() {
        // Reload translation data from JSON files with complete UI synchronization
        guard let projectPath = project.path else { return }

        print("Reloading translation data after settings change...")

        // Force refresh the project data from Core Data to get latest locale changes
        dataManager.viewContext.refresh(project, mergeChanges: true)

        // Use the same loading logic as when opening a project
        let fileSystemManager = FileSystemManager()
        let localeFiles = fileSystemManager.getLocaleFiles(for: project)

        print("Found \(localeFiles.count) locale files for locales: \(project.allLocales)")

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
        dataManager.saveContext()
        print("Successfully reloaded translation data")

        // Force UI refresh by posting additional notifications
        DispatchQueue.main.async {
            // Trigger a complete UI refresh
            NotificationCenter.default.post(
                name: NSNotification.Name("TranslationDataReloaded"),
                object: self.project
            )
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
}

struct ProjectInfoSection: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Project")
                .font(.headline)
                .foregroundColor(.secondary)

            HStack {
                Text(project.name ?? "Unknown Project")
                    .font(.title2)
                    .fontWeight(.semibold)

                if project.path != nil {
                    Button(action: openProjectInFinder) {
                        Image(systemName: "folder")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Open project folder in Finder")
                }
            }

            if let path = project.path {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Label("\(project.allLocales.count)", systemImage: "globe")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if project.hasUnsavedChanges {
                    Label("\(project.draftTranslationsCount)", systemImage: "pencil.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    private func openProjectInFinder() {
        guard let projectPath = project.path else { return }

        let projectURL = URL(fileURLWithPath: projectPath)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: projectURL.path)
    }
}

struct FilterSection: View {
    @Binding var searchText: String
    @Binding var sortOrder: SortOrder
    @Binding var filterOption: FilterOption

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filters")
                .font(.headline)
                .foregroundColor(.secondary)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search keys...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }

            // Sort order
            Picker("Sort", selection: $sortOrder) {
                Text("Alphabetical").tag(SortOrder.alphabetical)
                Text("Usage Count").tag(SortOrder.usage)
                Text("Last Modified").tag(SortOrder.lastModified)
                Text("Completion").tag(SortOrder.completion)
            }
            .pickerStyle(.menu)

            // Filter options
            Picker("Filter", selection: $filterOption) {
                Text("All Keys").tag(FilterOption.all)
                Text("Missing Translations").tag(FilterOption.missing)
                Text("Draft Changes").tag(FilterOption.drafts)
                Text("Unused Keys").tag(FilterOption.unused)
                Text("Recently Modified").tag(FilterOption.recent)
            }
            .pickerStyle(.menu)
        }
    }
}

struct StatisticsSection: View {
    let statistics: UsageStatistics?
    @ObservedObject var usageTracker: UsageTrackingSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Usage Tracking")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Spacer()

                // Status indicator with refresh button
                HStack(spacing: 8) {
                    Circle()
                        .fill(usageTracker.isTracking ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)

                    Button(action: {
                        Task {
                            await usageTracker.forceFullRescan()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Force rescan project")
                    .disabled(!usageTracker.isTracking)
                }
            }

            if let stats = statistics {
                VStack(alignment: .leading, spacing: 4) {
                    StatRow(label: "Total Keys", value: "\(stats.totalKeys)")
                    StatRow(label: "Total Usages", value: "\(stats.totalUsages)")
                    StatRow(label: "Files", value: "\(stats.totalFiles)")
                    StatRow(label: "Used Keys", value: "\(stats.keysWithUsage)")
                    StatRow(label: "Unused Keys", value: "\(stats.keysWithoutUsage)")
                    StatRow(label: "Completion", value: "\(Int(stats.translationCompletionRate * 100))%")

                    StatRow(label: "Last Updated", value: DateFormatter.shortTime.string(from: stats.lastCalculated))
                }
            } else {
                Text("Loading...")
                    .foregroundColor(.secondary)
            }

            // Show tracking error if any
            if let error = usageTracker.trackingError {
                Text("Error: \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Table Editing State Manager

class TableEditingStateManager: ObservableObject {
    @Published var isInEditMode = false
    @Published var currentEditingCell: CellPosition?
    @Published var pendingChanges: [CellPosition: String] = [:]



    struct CellPosition: Hashable, Equatable {
        let keyId: UUID
        let locale: String
        let rowIndex: Int
        let columnIndex: Int
    }

    func enterEditMode(at position: CellPosition) {
        // Defer state updates to avoid publishing during view updates
        DispatchQueue.main.async {
            self.isInEditMode = true
            self.currentEditingCell = position
        }
    }

    func exitEditMode() {
        // Defer state updates to avoid publishing during view updates
        DispatchQueue.main.async {
            self.isInEditMode = false
            self.currentEditingCell = nil
        }
    }

    func navigateToCell(_ position: CellPosition) {
        // Defer state updates to avoid publishing during view updates
        DispatchQueue.main.async {
            self.currentEditingCell = position
        }
    }

    func savePendingChange(at position: CellPosition, value: String) {
        pendingChanges[position] = value
    }

    func clearPendingChange(at position: CellPosition) {
        pendingChanges.removeValue(forKey: position)
    }

    func commitAllChanges() {
        // This will be handled by individual cells
        pendingChanges.removeAll()
    }











}

struct TranslationTableView: View {
    let project: Project
    let searchText: String
    let sortOrder: SortOrder
    let filterOption: FilterOption
    @Binding var selectedKeys: Set<String>

    @State private var i18nKeys: [I18nKey] = []
    @State private var locales: [String] = []
    @StateObject private var editingStateManager = TableEditingStateManager()

    // Force view refresh when filters change
    @State private var refreshTrigger = UUID()

    var body: some View {
        VStack(spacing: 0) {
            // Table header
            TranslationTableHeader(locales: locales, project: project)

            Divider()

            // Table content
            ScrollViewReader { scrollProxy in
                GeometryReader { geometry in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredAndSortedKeys.enumerated()), id: \.element.objectID) { rowIndex, key in
                                TranslationTableRow(
                                    key: key,
                                    locales: locales,
                                    isSelected: selectedKeys.contains(key.key ?? ""),
                                    rowIndex: rowIndex,
                                    editingStateManager: editingStateManager
                                )
                                .onTapGesture {
                                    if !editingStateManager.isInEditMode {
                                        toggleSelection(for: key)
                                    }
                                }

                                Divider()
                            }
                        }
                        .id(refreshTrigger) // Force rebuild when filters change

                    }
                    .coordinateSpace(name: "scrollView")


                }
            }
        }
        .focusable()
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
        .onTapGesture {
            // Click outside table exits edit mode and saves pending changes
            if editingStateManager.isInEditMode {
                // Defer state updates to avoid publishing during view updates
                DispatchQueue.main.async {
                    self.commitPendingChanges()
                    self.editingStateManager.exitEditMode()
                }
            }
        }
        .onAppear {
            loadData()
        }
        .onChange(of: project) {
            loadData()
        }
        .onChange(of: searchText) { _, _ in
            // Force view update when search text changes
            refreshTrigger = UUID()
        }
        .onChange(of: sortOrder) { _, _ in
            // Force view update when sort order changes
            refreshTrigger = UUID()
        }
        .onChange(of: filterOption) { _, _ in
            // Force view update when filter option changes
            refreshTrigger = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ProjectSettingsChanged"))) { notification in
            if let notificationProject = notification.object as? Project,
               notificationProject.objectID == project.objectID {
                // Reload table data when project settings change
                loadData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TranslationDataReloaded"))) { notification in
            if let notificationProject = notification.object as? Project,
               notificationProject.objectID == project.objectID {
                // Force complete reload of table data including column updates
                DispatchQueue.main.async {
                    loadData()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UsageDataCleaned"))) { notification in
            if let notificationProject = notification.object as? Project,
               notificationProject.objectID == project.objectID {
                // Reload data after usage tracking cleanup
                DispatchQueue.main.async {
                    loadData()
                    refreshTrigger = UUID()
                }
            }
        }
    }

    // MARK: - Keyboard Navigation

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard editingStateManager.isInEditMode,
              let currentPosition = editingStateManager.currentEditingCell else {
            return .ignored
        }

        let totalRows = filteredAndSortedKeys.count
        let totalColumns = locales.count

        switch keyPress.key {
        case .upArrow:
            // Defer navigation to avoid publishing during view updates
            DispatchQueue.main.async {
                self.navigateVertically(from: currentPosition, direction: -1, totalRows: totalRows)
            }
            return .handled

        case .downArrow:
            // Defer navigation to avoid publishing during view updates
            DispatchQueue.main.async {
                self.navigateVertically(from: currentPosition, direction: 1, totalRows: totalRows)
            }
            return .handled

        case .leftArrow:
            // Defer navigation to avoid publishing during view updates
            DispatchQueue.main.async {
                self.navigateHorizontally(from: currentPosition, direction: -1, totalColumns: totalColumns)
            }
            return .handled

        case .rightArrow:
            // Defer navigation to avoid publishing during view updates
            DispatchQueue.main.async {
                self.navigateHorizontally(from: currentPosition, direction: 1, totalColumns: totalColumns)
            }
            return .handled

        case .tab:
            // Defer navigation to avoid publishing during view updates
            let isShiftPressed = keyPress.modifiers.contains(.shift)
            DispatchQueue.main.async {
                self.navigateSequentially(from: currentPosition, backward: isShiftPressed, totalRows: totalRows, totalColumns: totalColumns)
            }
            return .handled

        case .return:
            // Defer state updates to avoid publishing during view updates
            DispatchQueue.main.async {
                self.commitPendingChanges()
                // Move to next cell (like Tab) for continuous editing workflow
                self.navigateSequentially(from: currentPosition, backward: false, totalRows: totalRows, totalColumns: totalColumns)
            }
            return .handled

        case .escape:
            // Defer state updates to avoid publishing during view updates
            DispatchQueue.main.async {
                self.cancelPendingChanges()
                self.editingStateManager.exitEditMode()
            }
            return .handled

        default:
            return .ignored
        }
    }

    private func navigateVertically(from position: TableEditingStateManager.CellPosition, direction: Int, totalRows: Int) {
        guard totalRows > 0, !filteredAndSortedKeys.isEmpty else { return }

        let newRowIndex = max(0, min(totalRows - 1, position.rowIndex + direction))
        if newRowIndex != position.rowIndex, newRowIndex < filteredAndSortedKeys.count {
            let newKey = filteredAndSortedKeys[newRowIndex]
            let newPosition = TableEditingStateManager.CellPosition(
                keyId: newKey.id ?? UUID(),
                locale: position.locale,
                rowIndex: newRowIndex,
                columnIndex: position.columnIndex
            )
            editingStateManager.navigateToCell(newPosition)
        }
    }

    private func navigateHorizontally(from position: TableEditingStateManager.CellPosition, direction: Int, totalColumns: Int) {
        guard totalColumns > 0, !locales.isEmpty else { return }

        let newColumnIndex = max(0, min(totalColumns - 1, position.columnIndex + direction))
        if newColumnIndex != position.columnIndex, newColumnIndex < locales.count {
            let newLocale = locales[newColumnIndex]
            let newPosition = TableEditingStateManager.CellPosition(
                keyId: position.keyId,
                locale: newLocale,
                rowIndex: position.rowIndex,
                columnIndex: newColumnIndex
            )
            editingStateManager.navigateToCell(newPosition)
        }
    }

    private func navigateSequentially(from position: TableEditingStateManager.CellPosition, backward: Bool, totalRows: Int, totalColumns: Int) {
        guard totalRows > 0, totalColumns > 0, !filteredAndSortedKeys.isEmpty, !locales.isEmpty else { return }

        let currentIndex = position.rowIndex * totalColumns + position.columnIndex
        let direction = backward ? -1 : 1
        var newIndex = currentIndex + direction

        // Handle wrapping
        if newIndex < 0 {
            newIndex = totalRows * totalColumns - 1
        } else if newIndex >= totalRows * totalColumns {
            newIndex = 0
        }

        let newRowIndex = newIndex / totalColumns
        let newColumnIndex = newIndex % totalColumns

        if newRowIndex < filteredAndSortedKeys.count && newColumnIndex < locales.count {
            let newKey = filteredAndSortedKeys[newRowIndex]
            let newLocale = locales[newColumnIndex]
            let newPosition = TableEditingStateManager.CellPosition(
                keyId: newKey.id ?? UUID(),
                locale: newLocale,
                rowIndex: newRowIndex,
                columnIndex: newColumnIndex
            )
            editingStateManager.navigateToCell(newPosition)
        }
    }

    // MARK: - Save/Commit Behavior

    private func commitPendingChanges() {
        // Notify all cells to save their pending changes
        NotificationCenter.default.post(name: NSNotification.Name("CommitPendingTranslationChanges"), object: nil)
        editingStateManager.commitAllChanges()
    }

    private func cancelPendingChanges() {
        // Notify all cells to cancel their pending changes
        NotificationCenter.default.post(name: NSNotification.Name("CancelPendingTranslationChanges"), object: nil)
        editingStateManager.pendingChanges.removeAll()
    }

    private var filteredAndSortedKeys: [I18nKey] {
        var keys = i18nKeys

        // Apply search filter
        if !searchText.isEmpty {
            keys = keys.filter { key in
                (key.key ?? "").localizedCaseInsensitiveContains(searchText) ||
                (key.namespace ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }

        // Apply filter option
        switch filterOption {
        case .all:
            break
        case .missing:
            keys = keys.filter { $0.hasMissingTranslations }
        case .drafts:
            keys = keys.filter { key in
                key.allTranslations.contains { $0.isDraft }
            }
        case .unused:
            keys = keys.filter { !$0.isUsedInFiles }
        case .recent:
            let recentDate = Date().addingTimeInterval(-24 * 60 * 60) // Last 24 hours
            keys = keys.filter { ($0.lastModified ?? Date.distantPast) > recentDate }
        }

        // Apply sort order
        switch sortOrder {
        case .alphabetical:
            keys = keys.sorted { ($0.key ?? "") < ($1.key ?? "") }
        case .usage:
            keys = keys.sorted { $0.activeFileUsages.count > $1.activeFileUsages.count }
        case .lastModified:
            keys = keys.sorted { ($0.lastModified ?? Date.distantPast) > ($1.lastModified ?? Date.distantPast) }
        case .completion:
            keys = keys.sorted { $0.completionPercentage > $1.completionPercentage }
        }

        return keys
    }

    private func loadData() {
        let fetchedKeys = DataManager.shared.getI18nKeys(for: project)

        // Debug: Check for duplicates
        let keyStrings = fetchedKeys.compactMap { $0.key }
        let uniqueKeyStrings = Set(keyStrings)
        if keyStrings.count != uniqueKeyStrings.count {
            print("⚠️ WARNING: Found duplicate keys in database!")
            print("Total keys: \(keyStrings.count), Unique keys: \(uniqueKeyStrings.count)")

            // Find duplicates
            var keyCount: [String: Int] = [:]
            for keyString in keyStrings {
                keyCount[keyString, default: 0] += 1
            }
            let duplicates = keyCount.filter { $0.value > 1 }
            print("Duplicate keys: \(duplicates)")
        }

        i18nKeys = fetchedKeys
        locales = project.allLocales

        print("Loaded \(i18nKeys.count) keys for project: \(project.name ?? "Unknown")")
    }

    private func toggleSelection(for key: I18nKey) {
        let keyString = key.key ?? ""
        if selectedKeys.contains(keyString) {
            selectedKeys.remove(keyString)
        } else {
            selectedKeys.insert(keyString)
        }
    }
}

struct TranslationTableHeader: View {
    let locales: [String]
    let project: Project

    private func getMissingPercentage(for locale: String) -> Double {
        let dataManager = DataManager.shared
        let i18nKeys = dataManager.getI18nKeys(for: project)
        let usedKeys = i18nKeys.filter { $0.isUsedInFiles }

        guard !usedKeys.isEmpty else { return 0.0 }

        let missingCount = usedKeys.filter { key in
            let translation = dataManager.getTranslation(i18nKey: key, locale: locale)
            return translation?.value?.isEmpty ?? true
        }.count

        return Double(missingCount) / Double(usedKeys.count) * 100.0
    }

    var body: some View {
        HStack(spacing: 0) {
            // Key column header
            Text("Key")
                .font(.system(.body, weight: .semibold))
                .frame(width: 200, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)

            Divider()

            // Locale column headers
            ForEach(locales, id: \.self) { locale in
                VStack(alignment: .leading, spacing: 2) {
                    Text(locale.uppercased())
                        .font(.system(.body, weight: .semibold))

                    let missingPercentage = getMissingPercentage(for: locale)
                    if missingPercentage > 0 {
                        Text("(\(Int(missingPercentage))% missing)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .frame(width: 150, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)

                Divider()
            }

            // File usage column header (last column)
            Text("Used In")
                .font(.system(.body, weight: .semibold))
                .frame(width: 180, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .frame(height: 44)
    }
}

struct TranslationTableRow: View {
    let key: I18nKey
    let locales: [String]
    let isSelected: Bool
    let rowIndex: Int
    @ObservedObject var editingStateManager: TableEditingStateManager

    var body: some View {
        HStack(spacing: 0) {
            // Key column
            KeyCell(key: key, isSelected: isSelected)

            Divider()

            // Translation columns
            ForEach(Array(locales.enumerated()), id: \.element) { columnIndex, locale in
                EnhancedTranslationCell(
                    key: key,
                    locale: locale,
                    isSelected: isSelected,
                    rowIndex: rowIndex,
                    columnIndex: columnIndex,
                    editingStateManager: editingStateManager
                )
                .id("cell_\(rowIndex)_\(columnIndex)")

                Divider()
            }

            // File usage column (last column)
            FileUsageCell(key: key, isSelected: isSelected)
        }
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }
}

struct KeyCell: View {
    let key: I18nKey
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(key.key ?? "")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(isSelected ? .primary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(key.key ?? "") // Show full key on hover

                Spacer()

                if key.hasMissingTranslations {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .help("Missing translations")
                }
            }

            if let namespace = key.namespace {
                Text(namespace)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(namespace) // Show full namespace on hover
            }
        }
        .frame(width: 200, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(key.hasMissingTranslations ? Color.red.opacity(0.03) : Color.clear)
        .overlay(
            Rectangle()
                .stroke(key.hasMissingTranslations ? Color.red.opacity(0.2) : Color.clear, lineWidth: key.hasMissingTranslations ? 1 : 0)
        )
    }
}

struct FileUsageCell: View {
    let key: I18nKey
    let isSelected: Bool

    private var fileUsages: [FileUsage] {
        key.activeFileUsages.sorted { usage1, usage2 in
            (usage1.filePath ?? "") < (usage2.filePath ?? "")
        }
    }

    private func getRelativePath(_ fullPath: String) -> String {
        // Extract path relative to project root
        if let projectPath = key.project?.path {
            if fullPath.hasPrefix(projectPath) {
                let relativePath = String(fullPath.dropFirst(projectPath.count))
                return relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
            }
        }
        return fullPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if fileUsages.isEmpty {
                Text("Not used")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(Array(fileUsages.prefix(3).enumerated()), id: \.element.id) { index, usage in
                    HStack(spacing: 4) {
                        Button(action: {
                            openFileDirectory(usage.filePath ?? "")
                        }) {
                            Image(systemName: "doc.text")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Open file directory")

                        Text(getRelativePath(usage.filePath ?? ""))
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(usage.filePath ?? "") // Show full path on hover

                        Text(":\(usage.lineNumber)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if fileUsages.count > 3 {
                    Text("+ \(fileUsages.count - 3) more")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                        .help(buildAdditionalFilesTooltip())
                }
            }
        }
        .frame(width: 180, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func openFileDirectory(_ filePath: String) {
        let fileURL = URL(fileURLWithPath: filePath)
        let directoryURL = fileURL.deletingLastPathComponent()
        NSWorkspace.shared.open(directoryURL)
    }

    private func buildAdditionalFilesTooltip() -> String {
        let additionalUsages = Array(fileUsages.dropFirst(3))
        let tooltipLines = additionalUsages.map { usage in
            "\(getRelativePath(usage.filePath ?? "")):\(usage.lineNumber)"
        }
        return "Additional files:\n" + tooltipLines.joined(separator: "\n")
    }
}

struct TranslationCell: View {
    let key: I18nKey
    let locale: String
    let isSelected: Bool

    @State private var isEditing = false
    @State private var editingValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isEditing {
                TextField("Translation", text: $editingValue)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        saveTranslation()
                    }
                    .onExitCommand {
                        cancelEditing()
                    }
            } else {
                HStack {
                    Text(displayValue)
                        .foregroundColor(displayValueColor)
                        .italic(displayValue.isEmpty || isMissing)
                        .fontWeight(isMissing ? .medium : .regular)

                    Spacer()

                    if translation?.isDraft == true {
                        Image(systemName: "pencil.circle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .help("Draft changes")
                    } else if isMissing {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                            .help("Missing translation")
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    startEditing()
                }
            }
        }
        .frame(width: 150, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(cellBackgroundColor)
        .overlay(
            Rectangle()
                .stroke(cellBorderColor, lineWidth: isMissing ? 1.5 : 0)
        )
    }

    private var translation: Translation? {
        key.translation(for: locale)
    }

    private var displayValue: String {
        if let translation = translation {
            return translation.effectiveValue ?? "Empty"
        }
        return "Missing"
    }

    private var isMissing: Bool {
        return translation == nil || translation?.effectiveValue?.isEmpty == true
    }

    private var displayValueColor: Color {
        if isMissing {
            return .red
        } else if displayValue == "Empty" {
            return .secondary
        } else {
            return .primary
        }
    }

    private var cellBackgroundColor: Color {
        if isMissing {
            return Color.red.opacity(0.05)
        } else if translation?.isDraft == true {
            return Color.orange.opacity(0.05)
        } else {
            return Color.clear
        }
    }

    private var cellBorderColor: Color {
        if isMissing {
            return Color.red.opacity(0.3)
        } else {
            return Color.clear
        }
    }

    private func startEditing() {
        editingValue = translation?.effectiveValue ?? ""
        isEditing = true
    }

    private func saveTranslation() {
        let dataManager = DataManager.shared
        _ = dataManager.createOrUpdateTranslation(
            i18nKey: key,
            locale: locale,
            value: editingValue,
            isDraft: true
        )

        isEditing = false
    }

    private func cancelEditing() {
        isEditing = false
        editingValue = ""
    }
}

// MARK: - Enhanced Translation Cell with Navigation Support

struct EnhancedTranslationCell: View {
    let key: I18nKey
    let locale: String
    let isSelected: Bool
    let rowIndex: Int
    let columnIndex: Int
    @ObservedObject var editingStateManager: TableEditingStateManager

    @State private var editingValue = ""
    @State private var hasPendingChanges = false
    @FocusState private var isTextFieldFocused: Bool

    private var cellPosition: TableEditingStateManager.CellPosition {
        TableEditingStateManager.CellPosition(
            keyId: key.id ?? UUID(),
            locale: locale,
            rowIndex: rowIndex,
            columnIndex: columnIndex
        )
    }

    private var isCurrentlyEditing: Bool {
        editingStateManager.isInEditMode &&
        editingStateManager.currentEditingCell == cellPosition
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isCurrentlyEditing {
                editingView
            } else {
                displayView
            }
        }
        .frame(width: 150, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(cellBackgroundColor)
        .overlay(
            Rectangle()
                .stroke(cellBorderColor, lineWidth: borderWidth)
        )
        .onChange(of: editingStateManager.currentEditingCell) { _, newPosition in
            handleEditingStateChange(newPosition)
        }
        .onAppear {
            loadInitialValue()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CommitPendingTranslationChanges"))) { _ in
            if hasPendingChanges {
                saveTranslation()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CancelPendingTranslationChanges"))) { _ in
            if hasPendingChanges {
                cancelEditing()
            }
        }

    }

    private var editingView: some View {
        TextField("Translation", text: $editingValue)
            .textFieldStyle(.plain)
            .focused($isTextFieldFocused)
            .onSubmit {
                // Defer state updates to avoid publishing during view updates
                DispatchQueue.main.async {
                    self.saveTranslation()
                }
            }
            .onChange(of: editingValue) { _, newValue in
                handleValueChange(newValue)
            }
            .onAppear {
                // Auto-focus when entering edit mode
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isTextFieldFocused = true
                }
            }
    }

    private var displayView: some View {
        HStack {
            Text(displayValue)
                .foregroundColor(displayValueColor)
                .italic(displayValue.isEmpty || isMissing)
                .fontWeight(isMissing ? .medium : .regular)

            Spacer()

            if translation?.isDraft == true {
                Image(systemName: "pencil.circle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .help("Draft changes")
            } else if isMissing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                    .help("Missing translation")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            startEditing()
        }
        .onTapGesture(count: 1) {
            handleSingleClick()
        }
    }

    // MARK: - Computed Properties

    private var translation: Translation? {
        key.translation(for: locale)
    }

    private var displayValue: String {
        if let translation = translation {
            return translation.effectiveValue ?? "Empty"
        }
        return "Missing"
    }

    private var isMissing: Bool {
        return translation == nil || translation?.effectiveValue?.isEmpty == true
    }

    private var displayValueColor: Color {
        if isMissing {
            return .red
        } else if displayValue == "Empty" {
            return .secondary
        } else {
            return .primary
        }
    }

    private var cellBackgroundColor: Color {
        if isCurrentlyEditing {
            return Color.blue.opacity(0.1)
        } else if isMissing {
            return Color.red.opacity(0.05)
        } else if translation?.isDraft == true {
            return Color.orange.opacity(0.05)
        } else {
            return Color.clear
        }
    }

    private var cellBorderColor: Color {
        if isCurrentlyEditing {
            return Color.blue.opacity(0.6)
        } else if isMissing {
            return Color.red.opacity(0.3)
        } else {
            return Color.clear
        }
    }

    private var borderWidth: CGFloat {
        if isCurrentlyEditing {
            return 2.0
        } else if isMissing {
            return 1.5
        } else {
            return 0
        }
    }

    // MARK: - Actions

    private func startEditing() {
        loadInitialValue()
        editingStateManager.enterEditMode(at: cellPosition)
    }

    private func handleSingleClick() {
        if editingStateManager.isInEditMode {
            // If already in edit mode, focus this cell
            editingStateManager.navigateToCell(cellPosition)
        }
    }

    private func handleEditingStateChange(_ newPosition: TableEditingStateManager.CellPosition?) {
        if newPosition == cellPosition {
            // This cell is now being edited
            loadInitialValue()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        } else if editingStateManager.currentEditingCell != cellPosition && hasPendingChanges {
            // Save changes when navigating away from this cell
            saveTranslation()
        }
    }

    private func handleValueChange(_ newValue: String) {
        let originalValue = translation?.effectiveValue ?? ""
        // Defer state updates to avoid publishing during view updates
        DispatchQueue.main.async {
            self.hasPendingChanges = newValue != originalValue
            self.editingStateManager.savePendingChange(at: self.cellPosition, value: newValue)
        }
    }

    private func loadInitialValue() {
        editingValue = translation?.effectiveValue ?? ""
        hasPendingChanges = false
    }

    private func saveTranslation() {
        guard hasPendingChanges else { return }

        let dataManager = DataManager.shared
        _ = dataManager.createOrUpdateTranslation(
            i18nKey: key,
            locale: locale,
            value: editingValue,
            isDraft: true
        )

        // Defer state updates to avoid publishing during view updates
        DispatchQueue.main.async {
            self.hasPendingChanges = false
            self.editingStateManager.clearPendingChange(at: self.cellPosition)
        }
    }

    private func cancelEditing() {
        loadInitialValue() // Reset to original value
        hasPendingChanges = false
        editingStateManager.clearPendingChange(at: cellPosition)
    }
}

enum SortOrder: CaseIterable {
    case alphabetical
    case usage
    case lastModified
    case completion
}

extension DateFormatter {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

enum FilterOption: CaseIterable {
    case all
    case missing
    case drafts
    case unused
    case recent
}

#Preview {
    // Create a mock project for preview
    let context = PersistenceController.preview.container.viewContext
    let project = Project(context: context)
    project.name = "Sample Project"
    project.path = "/path/to/project"
    project.locales = ["en", "es", "fr"]

    return TranslationEditorView(project: project)
}
