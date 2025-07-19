//
//  SmartRefactoringSystem.swift
//  i18n editor
//
//  Created by PlusA on 19/07/2025.
//

import Foundation
import CoreData
import os.log

/// Smart refactoring system for automatic key nesting based on SvelteKit route patterns
class SmartRefactoringSystem: ObservableObject {
    private let dataManager = DataManager.shared
    private let logger = Logger(subsystem: "com.plusa.i18n-editor", category: "SmartRefactoring")

    @Published var isAnalyzing = false
    @Published var refactoringSuggestions: [SmartRefactoringSuggestion] = []
    @Published var analysisProgress: Double = 0.0
    @Published var currentOperation = ""

    /// Analyze project and generate refactoring suggestions
    func analyzeProject(_ project: Project) async -> [SmartRefactoringSuggestion] {
        await MainActor.run {
            isAnalyzing = true
            analysisProgress = 0.0
            currentOperation = "Analyzing project structure..."
            refactoringSuggestions = []
        }

        logger.info("Starting smart refactoring analysis for project: \(project.name ?? "Unknown")")

        // Get all i18n keys with file usages
        let i18nKeys = await MainActor.run {
            dataManager.getI18nKeys(for: project).filter { $0.isUsedInFiles }
        }

        await MainActor.run {
            analysisProgress = 0.2
            currentOperation = "Processing \(i18nKeys.count) keys..."
        }

        var suggestions: [SmartRefactoringSuggestion] = []

        for (index, key) in i18nKeys.enumerated() {
            // Update progress
            await MainActor.run {
                analysisProgress = 0.2 + (0.6 * Double(index) / Double(i18nKeys.count))
                if index % 10 == 0 {
                    currentOperation = "Analyzing key \(index + 1) of \(i18nKeys.count)..."
                }
            }

            // Analyze each key's file usages
            let keyUsages = key.activeFileUsages
            let suggestedNamespaces = analyzeKeyUsages(keyUsages, currentKey: key.key ?? "")

            if let bestNamespace = selectBestNamespace(from: suggestedNamespaces, currentKey: key.key ?? "") {
                let suggestion = SmartRefactoringSuggestion(
                    originalKey: key.key ?? "",
                    suggestedKey: "\(bestNamespace).\(key.key ?? "")",
                    namespace: bestNamespace,
                    affectedFiles: keyUsages.compactMap { $0.filePath },
                    confidence: calculateConfidence(for: suggestedNamespaces),
                    reason: buildReason(for: bestNamespace, usages: keyUsages)
                )
                suggestions.append(suggestion)
            }
        }

        await MainActor.run {
            analysisProgress = 0.9
            currentOperation = "Finalizing suggestions..."
        }

        // Sort suggestions by confidence and group similar ones
        let finalSuggestions = optimizeSuggestions(suggestions)

        await MainActor.run {
            analysisProgress = 1.0
            currentOperation = "Analysis complete"
            refactoringSuggestions = finalSuggestions
            isAnalyzing = false
        }

        logger.info("Smart refactoring analysis completed: \(finalSuggestions.count) suggestions generated")
        return finalSuggestions
    }

    /// Analyze file usages to determine suggested namespaces
    private func analyzeKeyUsages(_ usages: [FileUsage], currentKey: String) -> [String: Int] {
        var namespaceCounts: [String: Int] = [:]

        for usage in usages {
            guard let filePath = usage.filePath else { continue }

            if let namespace = extractNamespaceFromPath(filePath) {
                namespaceCounts[namespace, default: 0] += 1
            }
        }

        return namespaceCounts
    }

    /// Extract namespace from SvelteKit file path
    private func extractNamespaceFromPath(_ filePath: String) -> String? {
        // Convert to relative path from src/routes
        guard filePath.contains("src/routes") else { return nil }

        let components = filePath.components(separatedBy: "/")
        guard let routesIndex = components.firstIndex(of: "routes") else { return nil }

        var pathComponents = Array(components[(routesIndex + 1)...])

        // Remove file name
        if let lastComponent = pathComponents.last, lastComponent.contains(".") {
            pathComponents.removeLast()
        }

        // Filter out dynamic segments and route groups
        pathComponents = pathComponents.compactMap { component in
            // Skip dynamic segments: [slug], [id], [...rest]
            if component.hasPrefix("[") && component.hasSuffix("]") {
                return nil
            }

            // Skip route groups: (auth), (admin), (app)
            if component.hasPrefix("(") && component.hasSuffix(")") {
                return nil
            }

            return component
        }

        // Handle special cases
        if pathComponents.isEmpty {
            return "home" // Root page
        }

        return pathComponents.joined(separator: ".")
    }

    /// Select the best namespace from suggestions
    private func selectBestNamespace(from suggestions: [String: Int], currentKey: String) -> String? {
        guard !suggestions.isEmpty else { return nil }

        // Don't suggest if key already has a namespace
        if currentKey.contains(".") {
            return nil
        }

        // Find the most common namespace
        let sortedSuggestions = suggestions.sorted { $0.value > $1.value }
        let bestSuggestion = sortedSuggestions.first!

        // Only suggest if there's a clear winner (at least 60% of usages)
        let totalUsages = suggestions.values.reduce(0, +)
        let confidence = Double(bestSuggestion.value) / Double(totalUsages)

        return confidence >= 0.6 ? bestSuggestion.key : nil
    }

    /// Calculate confidence score for a suggestion
    private func calculateConfidence(for suggestions: [String: Int]) -> Double {
        guard !suggestions.isEmpty else { return 0.0 }

        let totalUsages = suggestions.values.reduce(0, +)
        let maxUsages = suggestions.values.max() ?? 0

        return Double(maxUsages) / Double(totalUsages)
    }

    /// Build human-readable reason for suggestion
    private func buildReason(for namespace: String, usages: [FileUsage]) -> String {
        let fileCount = usages.count
        let uniqueFiles = Set(usages.compactMap { $0.filePath }).count

        return "Used in \(fileCount) location(s) across \(uniqueFiles) file(s) in the '\(namespace)' route section"
    }

    /// Optimize and deduplicate suggestions
    private func optimizeSuggestions(_ suggestions: [SmartRefactoringSuggestion]) -> [SmartRefactoringSuggestion] {
        // Sort by confidence (highest first)
        let sorted = suggestions.sorted { $0.confidence > $1.confidence }

        // Group by namespace for better organization
        let grouped = Dictionary(grouping: sorted) { $0.namespace }

        // Flatten back to array, maintaining order within groups
        var optimized: [SmartRefactoringSuggestion] = []
        for (_, groupSuggestions) in grouped.sorted(by: { $0.key < $1.key }) {
            optimized.append(contentsOf: groupSuggestions)
        }

        return optimized
    }

    /// Apply refactoring suggestions
    func applyRefactoring(_ suggestions: [SmartRefactoringSuggestion], project: Project) async -> SmartRefactoringResult {
        logger.info("Applying \(suggestions.count) refactoring suggestions")

        await MainActor.run {
            isAnalyzing = true
            analysisProgress = 0.0
            currentOperation = "Applying refactoring suggestions..."
        }

        var appliedSuggestions: [SmartRefactoringSuggestion] = []
        var failedSuggestions: [SmartRefactoringSuggestion] = []
        var modifiedFiles: Set<String> = []
        var keysUpdated = 0

        for (index, suggestion) in suggestions.enumerated() {
            await MainActor.run {
                analysisProgress = Double(index) / Double(suggestions.count)
                currentOperation = "Refactoring '\(suggestion.originalKey)'..."
            }

            do {
                // Update database
                try await updateKeyInDatabase(suggestion, project: project)

                // Update source files
                let updatedSourceFiles = try await updateSourceFiles(suggestion)
                modifiedFiles.formUnion(updatedSourceFiles)

                // Update locale JSON files
                let updatedLocaleFiles = try await updateLocaleFiles(suggestion, project: project)
                modifiedFiles.formUnion(updatedLocaleFiles)

                appliedSuggestions.append(suggestion)
                keysUpdated += 1

            } catch {
                logger.error("Failed to apply refactoring for '\(suggestion.originalKey)': \(error)")
                failedSuggestions.append(suggestion)
            }
        }

        await MainActor.run {
            analysisProgress = 1.0
            currentOperation = "Refactoring complete"
            isAnalyzing = false
        }

        logger.info("Refactoring completed: \(appliedSuggestions.count) applied, \(failedSuggestions.count) failed")

        let result = SmartRefactoringResult(
            appliedSuggestions: appliedSuggestions,
            failedSuggestions: failedSuggestions,
            filesModified: Array(modifiedFiles),
            keysUpdated: keysUpdated
        )

        // Trigger automatic rescan if any suggestions were applied
        if !appliedSuggestions.isEmpty {
            await triggerPostRefactoringRescan(project: project)
        }

        return result
    }

    /// Update key in database
    private func updateKeyInDatabase(_ suggestion: SmartRefactoringSuggestion, project: Project) async throws {
        await MainActor.run {
            // Find the existing key
            if let existingKey = dataManager.getI18nKey(key: suggestion.originalKey, project: project) {
                // Update the key name
                existingKey.key = suggestion.suggestedKey
                existingKey.namespace = suggestion.namespace
                existingKey.isNested = true
                existingKey.lastModified = Date()

                // Update parent key if nested
                let components = suggestion.suggestedKey.components(separatedBy: ".")
                if components.count > 1 {
                    existingKey.parentKey = components.dropLast().joined(separator: ".")
                }

                dataManager.saveContext()
            }
        }
    }

    /// Update source files with new key format
    private func updateSourceFiles(_ suggestion: SmartRefactoringSuggestion) async throws -> Set<String> {
        var modifiedFiles: Set<String> = []

        for filePath in Set(suggestion.affectedFiles) {
            do {
                let originalContent = try String(contentsOfFile: filePath, encoding: .utf8)
                let updatedContent = updateFileContent(
                    originalContent,
                    originalKey: suggestion.originalKey,
                    newKey: suggestion.suggestedKey
                )

                if originalContent != updatedContent {
                    try updatedContent.write(toFile: filePath, atomically: true, encoding: .utf8)
                    modifiedFiles.insert(filePath)
                }

            } catch {
                logger.error("Failed to update file \(filePath): \(error)")
                throw error
            }
        }

        return modifiedFiles
    }

    /// Update locale JSON files with new key structure
    private func updateLocaleFiles(_ suggestion: SmartRefactoringSuggestion, project: Project) async throws -> Set<String> {
        var modifiedFiles: Set<String> = []

        guard let projectPath = project.path else {
            throw NSError(domain: "SmartRefactoringError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Project path not found"])
        }

        // Get all locale files for the project
        let localeFiles = getLocaleFiles(for: project)

        for localeFile in localeFiles {
            do {
                let fileURL = URL(fileURLWithPath: localeFile)
                let fileName = fileURL.lastPathComponent

                guard FileManager.default.fileExists(atPath: localeFile) else {
                    logger.info("📁 Locale file does not exist: \(fileName), skipping")
                    continue
                }

                let data = try Data(contentsOf: fileURL)
                guard var jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    logger.warning("⚠️ Could not parse JSON in \(fileName), skipping")
                    continue
                }

                logger.info("🔍 Processing locale file: \(fileName) (keys: \(jsonObject.keys.count))")

                // Check if the original key exists in this locale file
                if hasKey(suggestion.originalKey, in: jsonObject) {
                    // Get the value for the original key
                    if let value = getValue(for: suggestion.originalKey, in: jsonObject) {
                        logger.info("🔄 Transforming key '\(suggestion.originalKey)' → '\(suggestion.suggestedKey)' in \(fileName)")
                        logger.info("📝 Original value: \(String(describing: value))")

                        // Create a mutable copy for transformation
                        var transformedObject = jsonObject

                        // Remove the original key first
                        logger.info("🗑️ Removing original key '\(suggestion.originalKey)'...")
                        self.removeKey(suggestion.originalKey, from: &transformedObject)
                        logger.info("🔍 After removal, key exists: \(self.hasKey(suggestion.originalKey, in: transformedObject))")

                        // Set the new nested key with the preserved value
                        logger.info("➕ Setting new nested key '\(suggestion.suggestedKey)' with value: \(String(describing: value))")

                        // Test the transformation logic with a simple example first
                        var testDict: [String: Any] = [:]
                        self.setNestedKey(suggestion.suggestedKey, value: value, in: &testDict)
                        logger.info("🧪 Test transformation result: \(testDict)")

                        self.setNestedKey(suggestion.suggestedKey, value: value, in: &transformedObject)
                        logger.info("🔍 After setting, new key exists: \(self.hasKey(suggestion.suggestedKey, in: transformedObject))")

                        // Log the transformed object structure for debugging
                        if let debugData = try? JSONSerialization.data(withJSONObject: transformedObject, options: [.prettyPrinted]),
                           let debugString = String(data: debugData, encoding: .utf8) {
                            logger.info("📋 Transformed JSON structure:\n\(debugString)")
                        }

                        // Verify the transformation was successful
                        let newKeyExists = self.hasKey(suggestion.suggestedKey, in: transformedObject)
                        let oldKeyRemoved = !self.hasKey(suggestion.originalKey, in: transformedObject)

                        if newKeyExists && oldKeyRemoved {
                            // Check file permissions before writing
                            let fileManager = FileManager.default
                            let isWritable = fileManager.isWritableFile(atPath: localeFile)
                            logger.info("📝 File writable: \(isWritable)")

                            if !isWritable {
                                logger.error("❌ File is not writable: \(localeFile)")
                                throw NSError(domain: "SmartRefactoringError", code: 2, userInfo: [NSLocalizedDescriptionKey: "File is not writable: \(localeFile)"])
                            }

                            // Write back to file
                            logger.info("💾 Writing transformed data to file...")
                            let updatedData = try JSONSerialization.data(withJSONObject: transformedObject, options: [.prettyPrinted, .sortedKeys])
                            logger.info("📊 Data size to write: \(updatedData.count) bytes")
                            try updatedData.write(to: fileURL)

                            // Verify the file was actually written
                            let verifyData = try Data(contentsOf: fileURL)
                            if let verifyObject = try JSONSerialization.jsonObject(with: verifyData) as? [String: Any] {
                                let fileHasNewKey = self.hasKey(suggestion.suggestedKey, in: verifyObject)
                                let fileHasOldKey = self.hasKey(suggestion.originalKey, in: verifyObject)
                                logger.info("🔍 File verification - New key exists: \(fileHasNewKey), Old key exists: \(fileHasOldKey)")
                            }

                            modifiedFiles.insert(localeFile)
                            logger.info("✅ Successfully updated locale file: \(fileName)")
                        } else {
                            logger.error("❌ Key transformation verification failed for \(fileName)")
                            logger.error("   - New key exists: \(newKeyExists)")
                            logger.error("   - Old key removed: \(oldKeyRemoved)")
                        }
                    } else {
                        logger.warning("⚠️ Key '\(suggestion.originalKey)' found but value is nil in \(fileName)")
                    }
                } else {
                    logger.info("🔍 Key '\(suggestion.originalKey)' not found in \(fileName), skipping")
                    // Log some sample keys for debugging
                    let sampleKeys = Array(jsonObject.keys.prefix(5))
                    logger.info("   Sample keys in file: \(sampleKeys)")
                }

            } catch {
                logger.error("❌ Failed to update locale file \(localeFile): \(error)")
                throw error
            }
        }

        return modifiedFiles
    }

    /// Get all locale files for a project
    private func getLocaleFiles(for project: Project) -> [String] {
        guard let projectPath = project.path,
              let pathPattern = project.pathPattern else {
            logger.warning("⚠️ Project path or pathPattern is missing")
            return []
        }

        var localeFiles: [String] = []

        logger.info("🌐 Getting locale files for project with \(project.allLocales.count) locales")
        logger.info("📁 Path pattern: \(pathPattern)")

        for locale in project.allLocales {
            let localePath = pathPattern.replacingOccurrences(of: "{locale}", with: locale)
            let fullPath = URL(fileURLWithPath: projectPath).appendingPathComponent(localePath).path
            localeFiles.append(fullPath)
            logger.info("📄 Locale file for '\(locale)': \(fullPath)")
        }

        return localeFiles
    }

    /// Check if a key exists in JSON object (supports both flattened and nested formats)
    private func hasKey(_ key: String, in jsonObject: [String: Any]) -> Bool {
        // First check if the key exists as a flattened key (direct lookup)
        if jsonObject[key] != nil {
            return true
        }

        // Then check if the key exists in nested format
        let components = key.components(separatedBy: ".")
        var current: Any = jsonObject

        for component in components {
            guard let dict = current as? [String: Any],
                  let value = dict[component] else {
                return false
            }
            current = value
        }

        return true
    }

    /// Get value for a key (supports both flattened and nested formats)
    private func getValue(for key: String, in jsonObject: [String: Any]) -> Any? {
        // First check if the key exists as a flattened key (direct lookup)
        if let value = jsonObject[key] {
            return value
        }

        // Then check if the key exists in nested format
        let components = key.components(separatedBy: ".")
        var current: Any = jsonObject

        for component in components {
            guard let dict = current as? [String: Any],
                  let value = dict[component] else {
                return nil
            }
            current = value
        }

        return current
    }

    /// Remove a key from JSON object (supports both flattened and nested formats)
    private func removeKey(_ key: String, from jsonObject: inout [String: Any]) {
        // First try to remove as a flattened key (direct removal)
        if jsonObject[key] != nil {
            jsonObject.removeValue(forKey: key)
            logger.info("Removed flattened key '\(key)': ✅")
            return
        }

        // Then try to remove as nested key
        let components = key.components(separatedBy: ".")

        if components.count == 1 {
            jsonObject.removeValue(forKey: components[0])
            return
        }

        // Use recursive approach to properly handle nested removal
        removeNestedKey(components: components, from: &jsonObject)
    }

    /// Helper method to recursively remove nested keys
    private func removeNestedKey(components: [String], from dict: inout [String: Any]) {
        guard !components.isEmpty else { return }

        if components.count == 1 {
            let removedValue = dict.removeValue(forKey: components[0])
            logger.info("Removed key '\(components[0])': \(removedValue != nil ? "✅" : "❌")")
            return
        }

        let firstKey = components[0]
        let remainingComponents = Array(components.dropFirst())

        if var nestedDict = dict[firstKey] as? [String: Any] {
            removeNestedKey(components: remainingComponents, from: &nestedDict)

            // If the nested dictionary becomes empty after removal, remove the parent key too
            if nestedDict.isEmpty {
                dict.removeValue(forKey: firstKey)
                logger.info("Removed empty parent key '\(firstKey)'")
            } else {
                dict[firstKey] = nestedDict
            }
        }
    }

    /// Set a nested key in JSON object (supports dot notation)
    private func setNestedKey(_ key: String, value: Any, in jsonObject: inout [String: Any]) {
        setNestedValue(&jsonObject, keyPath: key, value: value)
    }

    /// Helper method to set nested value using key path
    private func setNestedValue(_ dict: inout [String: Any], keyPath: String, value: Any) {
        let components = keyPath.components(separatedBy: ".")
        guard !components.isEmpty else {
            logger.warning("⚠️ Empty keyPath provided to setNestedValue")
            return
        }

        logger.info("🔧 setNestedValue: keyPath='\(keyPath)', components=\(components), value=\(String(describing: value))")

        if components.count == 1 {
            dict[components[0]] = value
            logger.info("✅ Set leaf value: dict['\(components[0])'] = \(String(describing: value))")
            return
        }

        let firstKey = components[0]
        let remainingPath = components.dropFirst().joined(separator: ".")

        logger.info("🌳 Processing nested key: firstKey='\(firstKey)', remainingPath='\(remainingPath)'")

        if var nestedDict = dict[firstKey] as? [String: Any] {
            logger.info("📁 Found existing nested dict for '\(firstKey)', updating...")
            setNestedValue(&nestedDict, keyPath: remainingPath, value: value)
            dict[firstKey] = nestedDict
            logger.info("✅ Updated existing nested dict for '\(firstKey)'")
        } else {
            logger.info("🆕 Creating new nested dict for '\(firstKey)'...")
            var newDict: [String: Any] = [:]
            setNestedValue(&newDict, keyPath: remainingPath, value: value)
            dict[firstKey] = newDict
            logger.info("✅ Created new nested dict for '\(firstKey)': \(newDict)")
        }
    }

    /// Update file content with new key format
    private func updateFileContent(_ content: String, originalKey: String, newKey: String) -> String {
        var updatedContent = content

        // Pattern 1: m.originalKey() -> m["newKey"]()
        let pattern1 = #"(?<![A-Za-z0-9])m\.\#(originalKey)\(\s*\)"#
        let replacement1 = #"m["\#(newKey)"]()"#
        updatedContent = updatedContent.replacingOccurrences(
            of: pattern1,
            with: replacement1,
            options: .regularExpression
        )

        // Pattern 2: m.originalKey(params) -> m["newKey"](params)
        let pattern2 = #"(?<![A-Za-z0-9])m\.\#(originalKey)\("#
        let replacement2 = #"m["\#(newKey)"]("#
        updatedContent = updatedContent.replacingOccurrences(
            of: pattern2,
            with: replacement2,
            options: .regularExpression
        )

        // Pattern 3: {m.originalKey()} -> {m["newKey"]()}
        let pattern3 = #"\{\s*m\.\#(originalKey)\(\s*\)\s*\}"#
        let replacement3 = #"{m["\#(newKey)"]()}"#
        updatedContent = updatedContent.replacingOccurrences(
            of: pattern3,
            with: replacement3,
            options: .regularExpression
        )

        // Pattern 4: {m.originalKey(params)} -> {m["newKey"](params)}
        let pattern4 = #"\{\s*m\.\#(originalKey)\("#
        let replacement4 = #"{m["\#(newKey)"]("#
        updatedContent = updatedContent.replacingOccurrences(
            of: pattern4,
            with: replacement4,
            options: .regularExpression
        )

        return updatedContent
    }

    /// Trigger automatic usage tracking rescan after successful refactoring
    private func triggerPostRefactoringRescan(project: Project) async {
        logger.info("Triggering post-refactoring usage tracking rescan...")

        await MainActor.run {
            // Post notification to trigger rescan
            NotificationCenter.default.post(
                name: NSNotification.Name("SmartRefactoringCompleted"),
                object: project,
                userInfo: ["shouldRescan": true]
            )
        }
    }
}

// MARK: - Supporting Types

struct SmartRefactoringSuggestion: Identifiable, Hashable {
    let id = UUID()
    let originalKey: String
    let suggestedKey: String
    let namespace: String
    let affectedFiles: [String]
    let confidence: Double
    let reason: String

    var confidencePercentage: Int {
        Int(confidence * 100)
    }

    var affectedFileCount: Int {
        Set(affectedFiles).count
    }
}

struct SmartRefactoringResult {
    let appliedSuggestions: [SmartRefactoringSuggestion]
    let failedSuggestions: [SmartRefactoringSuggestion]
    let filesModified: [String]
    let keysUpdated: Int
}
