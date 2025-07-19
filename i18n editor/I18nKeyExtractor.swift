//
//  I18nKeyExtractor.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import Foundation
import CoreData
import os.log

/// Extracts and processes i18n keys from scan results, managing Core Data persistence
class I18nKeyExtractor: ObservableObject {
    private let dataManager = DataManager.shared
    private let svelteScanner = SvelteFileScanner()
    private let logger = Logger(subsystem: "com.plusa.i18n-editor", category: "I18nKeyExtractor")

    @Published var isExtracting = false
    @Published var extractionProgress: Double = 0.0
    @Published var currentOperation: String = ""
    @Published var extractedKeysCount: Int = 0
    @Published var updatedKeysCount: Int = 0
    @Published var lastExtractionError: String?

    // MARK: - Main Extraction Methods

    /// Extract all i18n keys from project and update database
    func extractKeysFromProject(_ project: Project) async -> ExtractionResult {
        logger.info("Starting key extraction for project: \(project.name ?? "Unknown")")

        await MainActor.run {
            isExtracting = true
            extractionProgress = 0.0
            currentOperation = "Scanning Svelte files..."
            extractedKeysCount = 0
            updatedKeysCount = 0
            lastExtractionError = nil
        }

        defer {
            Task { @MainActor in
                isExtracting = false
                currentOperation = ""
            }
        }

        // Step 1: Scan for key usages
        await MainActor.run {
            extractionProgress = 0.1
            currentOperation = "Scanning for i18n usage patterns..."
        }

        logger.info("Starting Svelte file scan...")
        let keyUsages = await svelteScanner.scanProject(project)

        if let scanError = svelteScanner.lastScanError {
            logger.error("Svelte scanner error: \(scanError)")
            await MainActor.run {
                lastExtractionError = scanError
            }
            // Continue with extraction even if there are scan errors
        }

        logger.info("Scan completed: found \(keyUsages.count) key usages")

        // Step 2: Process and extract unique keys
        await MainActor.run {
            extractionProgress = 0.4
            currentOperation = "Processing detected keys..."
        }

        let processedKeys = processKeyUsages(keyUsages, project: project)

        // Step 3: Update database
        await MainActor.run {
            extractionProgress = 0.6
            currentOperation = "Updating database..."
        }

        logger.info("Updating database with \(processedKeys.count) processed keys...")
        let databaseResult = await updateDatabase(with: processedKeys, project: project)
        logger.info("Database update completed: \(databaseResult.newKeys) new, \(databaseResult.updatedKeys) updated")

        // Step 4: Analyze key structure
        await MainActor.run {
            extractionProgress = 0.8
            currentOperation = "Analyzing key structure..."
        }

        let analysisResult = svelteScanner.analyzeKeyStructure(keyUsages)

        // Step 5: Clean up inactive usages
        await MainActor.run {
            extractionProgress = 0.9
            currentOperation = "Cleaning up inactive usages..."
        }

        await cleanupInactiveUsages(project: project, activeUsages: keyUsages)

        await MainActor.run {
            extractionProgress = 1.0
            currentOperation = "Extraction complete"
            extractedKeysCount = databaseResult.newKeys
            updatedKeysCount = databaseResult.updatedKeys
        }

        return ExtractionResult(
            totalKeysFound: processedKeys.count,
            newKeysCreated: databaseResult.newKeys,
            existingKeysUpdated: databaseResult.updatedKeys,
            totalUsages: keyUsages.count,
            analysisResult: analysisResult,
            extractionDate: Date()
        )
    }

    /// Process key usages and group by unique keys
    private func processKeyUsages(_ keyUsages: [I18nKeyUsage], project: Project) -> [ProcessedKey] {
        var keyMap: [String: ProcessedKey] = [:]

        for usage in keyUsages {
            let keyString = usage.key

            if keyMap[keyString] == nil {
                keyMap[keyString] = ProcessedKey(
                    key: keyString,
                    namespace: extractNamespace(from: keyString),
                    isNested: keyString.contains("."),
                    parentKey: extractParentKey(from: keyString),
                    usages: [],
                    project: project
                )
            }

            keyMap[keyString]?.usages.append(usage)
        }

        return Array(keyMap.values)
    }

    /// Extract namespace from key
    private func extractNamespace(from key: String) -> String? {
        let components = key.components(separatedBy: ".")
        return components.count > 1 ? components.first : nil
    }

    /// Extract parent key from nested key
    private func extractParentKey(from key: String) -> String? {
        let components = key.components(separatedBy: ".")
        return components.count > 1 ? components.dropLast().joined(separator: ".") : nil
    }

    /// Update database with processed keys
    private func updateDatabase(with processedKeys: [ProcessedKey], project: Project) async -> DatabaseUpdateResult {
        // Perform all Core Data operations on the main thread with batching
        return await MainActor.run {
            var newKeys = 0
            var updatedKeys = 0
            let batchSize = 50 // Process in batches to improve performance

            // Disable automatic saving during batch operations
            let context = dataManager.viewContext
            context.automaticallyMergesChangesFromParent = false

            defer {
                context.automaticallyMergesChangesFromParent = true
            }

            for (index, processedKey) in processedKeys.enumerated() {
                // Update progress every 10 items to reduce UI updates
                if index % 10 == 0 {
                    extractionProgress = 0.6 + (0.2 * Double(index) / Double(processedKeys.count))
                }

                // Create or update i18n key
                let i18nKey = dataManager.createOrUpdateI18nKey(
                    key: processedKey.key,
                    project: project,
                    namespace: processedKey.namespace
                )

                // Check if this is a new key
                if i18nKey.detectedAt == i18nKey.lastModified {
                    newKeys += 1
                } else {
                    updatedKeys += 1
                }

                // Update key properties
                i18nKey.isNested = processedKey.isNested
                i18nKey.parentKey = processedKey.parentKey

                // Update file usages
                updateFileUsages(for: i18nKey, with: processedKey.usages)

                // Save in batches to avoid memory buildup
                if index % batchSize == 0 && index > 0 {
                    dataManager.saveContext()
                }
            }

            // Final save
            dataManager.saveContext()

            return DatabaseUpdateResult(newKeys: newKeys, updatedKeys: updatedKeys)
        }
    }

    /// Update file usages for an i18n key
    private func updateFileUsages(for i18nKey: I18nKey, with usages: [I18nKeyUsage]) {
        // Mark all existing usages as inactive first
        let existingUsages = i18nKey.fileUsages?.allObjects as? [FileUsage] ?? []
        for usage in existingUsages {
            usage.isActive = false
        }

        // Create or update usages from scan results
        for usage in usages {
            let fileUsage = dataManager.recordFileUsage(
                i18nKey: i18nKey,
                filePath: usage.filePath,
                lineNumber: Int32(usage.lineNumber),
                columnNumber: Int32(usage.columnNumber),
                context: usage.context
            )
            fileUsage.isActive = true
        }
    }

    /// Clean up inactive file usages
    private func cleanupInactiveUsages(project: Project, activeUsages: [I18nKeyUsage]) async {
        await MainActor.run {
            let request: NSFetchRequest<FileUsage> = FileUsage.fetchRequest()
            request.predicate = NSPredicate(format: "project == %@ AND isActive == NO", project)

            do {
                let inactiveUsages = try dataManager.viewContext.fetch(request)

                // Remove usages that haven't been active for more than one scan cycle
                let cutoffDate = Date().addingTimeInterval(-3600) // 1 hour ago

                for usage in inactiveUsages {
                    if usage.detectedAt ?? Date.distantPast < cutoffDate {
                        dataManager.viewContext.delete(usage)
                    }
                }

                dataManager.saveContext()

            } catch {
                print("Error cleaning up inactive usages: \(error)")
            }
        }
    }

    // MARK: - Key Validation and Enhancement

    /// Validate extracted keys against locale files
    func validateKeysAgainstLocaleFiles(project: Project) async -> KeyValidationResult {
        await MainActor.run {
            currentOperation = "Validating keys against locale files..."
        }

        let fileSystemManager = FileSystemManager()
        let localeFiles = fileSystemManager.getLocaleFiles(for: project)
        let i18nKeys = dataManager.getI18nKeys(for: project)

        var missingKeys: [MissingKeyInfo] = []
        var orphanedKeys: [OrphanedKeyInfo] = []
        var validationErrors: [ValidationError] = []

        // Check for keys missing in locale files
        for i18nKey in i18nKeys {
            let keyString = i18nKey.key ?? ""

            for localeFile in localeFiles {
                if !keyExistsInLocaleFile(key: keyString, localeFile: localeFile) {
                    missingKeys.append(MissingKeyInfo(
                        key: keyString,
                        locale: localeFile.locale,
                        filePath: localeFile.path
                    ))
                }
            }
        }

        // Check for keys in locale files that aren't used in code
        for localeFile in localeFiles {
            let keysInFile = extractKeysFromLocaleFile(localeFile)

            for keyInFile in keysInFile {
                if !i18nKeys.contains(where: { $0.key == keyInFile }) {
                    orphanedKeys.append(OrphanedKeyInfo(
                        key: keyInFile,
                        locale: localeFile.locale,
                        filePath: localeFile.path
                    ))
                }
            }
        }

        return KeyValidationResult(
            missingKeys: missingKeys,
            orphanedKeys: orphanedKeys,
            validationErrors: validationErrors,
            validationDate: Date()
        )
    }

    /// Check if key exists in locale file
    private func keyExistsInLocaleFile(key: String, localeFile: LocaleFile) -> Bool {
        return getValueFromNestedDictionary(localeFile.content, keyPath: key) != nil
    }

    /// Extract all keys from locale file
    private func extractKeysFromLocaleFile(_ localeFile: LocaleFile) -> [String] {
        return extractKeysFromDictionary(localeFile.content, prefix: "")
    }

    /// Recursively extract keys from nested dictionary
    private func extractKeysFromDictionary(_ dict: [String: Any], prefix: String) -> [String] {
        var keys: [String] = []

        for (key, value) in dict {
            // Skip $schema property as it's used for JSON schema validation
            if key == "$schema" {
                continue
            }

            let fullKey = prefix.isEmpty ? key : "\(prefix).\(key)"

            if value is String {
                keys.append(fullKey)
            } else if let nestedDict = value as? [String: Any] {
                keys.append(contentsOf: extractKeysFromDictionary(nestedDict, prefix: fullKey))
            }
        }

        return keys
    }

    /// Get value from nested dictionary using dot notation
    private func getValueFromNestedDictionary(_ dict: [String: Any], keyPath: String) -> Any? {
        let components = keyPath.components(separatedBy: ".")
        var current: Any = dict

        for component in components {
            guard let currentDict = current as? [String: Any],
                  let value = currentDict[component] else {
                return nil
            }
            current = value
        }

        return current
    }

    // MARK: - Incremental Updates

    /// Extract keys from specific files (for incremental updates)
    func extractKeysFromFiles(_ filePaths: [String], project: Project) async -> ExtractionResult {
        await MainActor.run {
            isExtracting = true
            currentOperation = "Processing file changes..."
        }

        defer {
            Task { @MainActor in
                isExtracting = false
            }
        }

        let fileSystemManager = FileSystemManager()
        var allUsages: [I18nKeyUsage] = []

        for filePath in filePaths {
            if filePath.hasSuffix(".svelte") {
                // Mark existing usages for this file as inactive
                dataManager.markFileUsagesInactive(for: project, filePath: filePath)

                // Scan the file
                if let svelteFile = createSvelteFile(from: filePath, projectPath: project.path ?? "") {
                    let usages = svelteScanner.scanSvelteFile(svelteFile, project: project)
                    allUsages.append(contentsOf: usages)
                }
            }
        }

        // Process the usages
        let processedKeys = processKeyUsages(allUsages, project: project)
        let databaseResult = await updateDatabase(with: processedKeys, project: project)

        return ExtractionResult(
            totalKeysFound: processedKeys.count,
            newKeysCreated: databaseResult.newKeys,
            existingKeysUpdated: databaseResult.updatedKeys,
            totalUsages: allUsages.count,
            analysisResult: svelteScanner.analyzeKeyStructure(allUsages),
            extractionDate: Date()
        )
    }

    /// Create SvelteFile from file path
    private func createSvelteFile(from filePath: String, projectPath: String) -> SvelteFile? {
        do {
            let content = try String(contentsOf: URL(fileURLWithPath: filePath), encoding: .utf8)
            let relativePath = filePath.hasPrefix(projectPath) ?
                String(filePath.dropFirst(projectPath.count + 1)) : filePath

            let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
            let modificationDate = attributes[.modificationDate] as? Date ?? Date()
            let fileSize = attributes[.size] as? Int64 ?? 0

            return SvelteFile(
                path: filePath,
                relativePath: relativePath,
                content: content,
                modificationDate: modificationDate,
                fileSize: fileSize
            )
        } catch {
            print("Error creating SvelteFile from \(filePath): \(error)")
            return nil
        }
    }
}

// MARK: - Supporting Types

struct ProcessedKey {
    let key: String
    let namespace: String?
    let isNested: Bool
    let parentKey: String?
    var usages: [I18nKeyUsage]
    let project: Project
}

struct ExtractionResult {
    let totalKeysFound: Int
    let newKeysCreated: Int
    let existingKeysUpdated: Int
    let totalUsages: Int
    let analysisResult: KeyAnalysisResult
    let extractionDate: Date
}

struct DatabaseUpdateResult {
    let newKeys: Int
    let updatedKeys: Int
}

struct KeyValidationResult {
    let missingKeys: [MissingKeyInfo]
    let orphanedKeys: [OrphanedKeyInfo]
    let validationErrors: [ValidationError]
    let validationDate: Date
}

struct MissingKeyInfo: Identifiable {
    let id = UUID()
    let key: String
    let locale: String
    let filePath: String
}

struct OrphanedKeyInfo: Identifiable {
    let id = UUID()
    let key: String
    let locale: String
    let filePath: String
}

struct ValidationError: Identifiable {
    let id = UUID()
    let message: String
    let severity: ValidationSeverity
    let filePath: String?
    let lineNumber: Int?
}
