//
//  SmartRefactorer.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import Foundation

// MARK: - Supporting Types

enum RefactoringOption: String, CaseIterable {
    case sortKeys = "sort_keys"
    case removeEmpty = "remove_empty"
    case formatJSON = "format_json"
    case mergeDuplicates = "merge_duplicates"
    case optimizeNesting = "optimize_nesting"

    var title: String {
        switch self {
        case .sortKeys:
            return "Sort Keys Alphabetically"
        case .removeEmpty:
            return "Remove Empty Translations"
        case .formatJSON:
            return "Format JSON Files"
        case .mergeDuplicates:
            return "Merge Duplicate Keys"
        case .optimizeNesting:
            return "Optimize Key Nesting"
        }
    }

    var description: String {
        switch self {
        case .sortKeys:
            return "Sort all translation keys in alphabetical order"
        case .removeEmpty:
            return "Remove keys with empty or null values"
        case .formatJSON:
            return "Format JSON files with consistent indentation"
        case .mergeDuplicates:
            return "Merge duplicate keys and resolve conflicts"
        case .optimizeNesting:
            return "Optimize nested key structure for better organization"
        }
    }
}

struct RefactoringResults {
    let filesProcessed: Int
    let keysReorganized: Int
    let emptyKeysRemoved: Int
    let duplicatesMerged: Int
    let errors: [String]
}

/// Handles smart refactoring operations for translation files
class SmartRefactorer {
    private let fileManager = FileManager.default
    private let fileSystemManager = FileSystemManager()
    
    /// Refactor a project with the specified options
    func refactorProject(
        project: Project,
        options: Set<RefactoringOption>,
        progressCallback: @escaping (Double, String) -> Void
    ) async -> RefactoringResults {
        
        var filesProcessed = 0
        var keysReorganized = 0
        var emptyKeysRemoved = 0
        var duplicatesMerged = 0
        var errors: [String] = []
        
        // Get locale files
        let localeFiles = fileSystemManager.getLocaleFiles(for: project)
        let totalFiles = localeFiles.count
        
        progressCallback(0.1, "Analyzing locale files...")
        
        for (index, localeFile) in localeFiles.enumerated() {
            guard localeFile.exists else {
                errors.append("Locale file not found: \(localeFile.path)")
                continue
            }
            
            progressCallback(
                0.1 + (0.8 * Double(index) / Double(totalFiles)),
                "Processing \(localeFile.locale)..."
            )
            
            do {
                var content = localeFile.content
                let originalKeyCount = countKeys(in: content)
                
                // Apply selected refactoring options
                if options.contains(.removeEmpty) {
                    let removed = removeEmptyKeys(&content)
                    emptyKeysRemoved += removed
                }
                
                if options.contains(.mergeDuplicates) {
                    let merged = mergeDuplicateKeys(&content)
                    duplicatesMerged += merged
                }
                
                if options.contains(.optimizeNesting) {
                    content = optimizeNesting(content)
                }
                
                if options.contains(.sortKeys) {
                    content = sortKeys(content)
                }
                
                let finalKeyCount = countKeys(in: content)
                keysReorganized += abs(finalKeyCount - originalKeyCount)
                
                // Save the refactored content with security-scoped access
                try saveRefactoredContent(content, to: localeFile.path, formatJSON: options.contains(.formatJSON), projectPath: project.path ?? "")
                filesProcessed += 1
                
            } catch {
                errors.append("Failed to process \(localeFile.locale): \(error.localizedDescription)")
            }
        }
        
        progressCallback(0.9, "Updating database...")
        
        // Reload translation data into Core Data
        await reloadTranslationData(for: project)
        
        progressCallback(1.0, "Refactoring completed")
        
        return RefactoringResults(
            filesProcessed: filesProcessed,
            keysReorganized: keysReorganized,
            emptyKeysRemoved: emptyKeysRemoved,
            duplicatesMerged: duplicatesMerged,
            errors: errors
        )
    }
    
    // MARK: - Refactoring Operations
    
    /// Remove empty or null values from the content
    private func removeEmptyKeys(_ content: inout [String: Any]) -> Int {
        var removedCount = 0
        
        func removeEmptyRecursive(_ dict: inout [String: Any]) {
            var keysToRemove: [String] = []
            
            for (key, value) in dict {
                if var nestedDict = value as? [String: Any] {
                    removeEmptyRecursive(&nestedDict)
                    if nestedDict.isEmpty {
                        keysToRemove.append(key)
                    } else {
                        dict[key] = nestedDict
                    }
                } else if let stringValue = value as? String, stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    keysToRemove.append(key)
                } else if value is NSNull {
                    keysToRemove.append(key)
                }
            }
            
            for key in keysToRemove {
                dict.removeValue(forKey: key)
                removedCount += 1
            }
        }
        
        removeEmptyRecursive(&content)
        return removedCount
    }
    
    /// Merge duplicate keys (this is a simplified implementation)
    private func mergeDuplicateKeys(_ content: inout [String: Any]) -> Int {
        // For this implementation, we'll focus on case-insensitive duplicates
        var mergedCount = 0
        var lowercaseKeys: [String: String] = [:]
        var keysToMerge: [(String, String)] = []
        
        // Find case-insensitive duplicates
        for key in content.keys {
            let lowercaseKey = key.lowercased()
            if let existingKey = lowercaseKeys[lowercaseKey], existingKey != key {
                keysToMerge.append((existingKey, key))
            } else {
                lowercaseKeys[lowercaseKey] = key
            }
        }
        
        // Merge duplicates (keep the first one, remove the second)
        for (keepKey, removeKey) in keysToMerge {
            content.removeValue(forKey: removeKey)
            mergedCount += 1
        }
        
        return mergedCount
    }
    
    /// Optimize nesting structure
    private func optimizeNesting(_ content: [String: Any]) -> [String: Any] {
        // Convert flat keys with dots to nested structure
        var optimized: [String: Any] = [:]
        
        for (key, value) in content {
            if key.contains(".") {
                setNestedValue(&optimized, keyPath: key, value: value)
            } else {
                optimized[key] = value
            }
        }
        
        return optimized
    }
    
    /// Sort keys alphabetically
    private func sortKeys(_ content: [String: Any]) -> [String: Any] {
        var sorted: [String: Any] = [:]
        
        let sortedKeys = content.keys.sorted()
        for key in sortedKeys {
            if var nestedDict = content[key] as? [String: Any] {
                sorted[key] = sortKeys(nestedDict)
            } else {
                sorted[key] = content[key]
            }
        }
        
        return sorted
    }
    
    // MARK: - Helper Methods
    
    /// Count total number of keys in nested structure
    private func countKeys(in content: [String: Any]) -> Int {
        var count = 0
        
        for (_, value) in content {
            count += 1
            if let nestedDict = value as? [String: Any] {
                count += countKeys(in: nestedDict) - 1 // Subtract 1 to avoid double counting
            }
        }
        
        return count
    }
    
    /// Set nested value using dot notation key path
    private func setNestedValue(_ dict: inout [String: Any], keyPath: String, value: Any) {
        let components = keyPath.components(separatedBy: ".")
        guard !components.isEmpty else { return }
        
        if components.count == 1 {
            dict[components[0]] = value
            return
        }
        
        let firstKey = components[0]
        let remainingPath = components.dropFirst().joined(separator: ".")
        
        if var nestedDict = dict[firstKey] as? [String: Any] {
            setNestedValue(&nestedDict, keyPath: remainingPath, value: value)
            dict[firstKey] = nestedDict
        } else {
            var newDict: [String: Any] = [:]
            setNestedValue(&newDict, keyPath: remainingPath, value: value)
            dict[firstKey] = newDict
        }
    }
    
    /// Save refactored content to file with security-scoped access
    private func saveRefactoredContent(_ content: [String: Any], to path: String, formatJSON: Bool, projectPath: String) throws {
        let options: JSONSerialization.WritingOptions = formatJSON ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.withoutEscapingSlashes]
        let data = try JSONSerialization.data(withJSONObject: content, options: options)

        // Use security-scoped access for sandbox compatibility
        try withSecurityScopedAccess(to: projectPath) { projectURL in
            // Create backup before overwriting
            let backupPath = path + ".backup.\(Int(Date().timeIntervalSince1970))"
            if fileManager.fileExists(atPath: path) {
                try fileManager.copyItem(atPath: path, toPath: backupPath)
            }

            try data.write(to: URL(fileURLWithPath: path))
        }
    }

    /// Helper method for security-scoped access (similar to ProjectSettingsView)
    private func withSecurityScopedAccess<T>(to projectPath: String, operation: (URL) throws -> T) throws -> T {
        // Try to restore security-scoped access from bookmark
        if let bookmarkData = UserDefaults.standard.data(forKey: "bookmark_\(projectPath)") {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

                if isStale {
                    throw NSError(domain: "SmartRefactorerError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Project access permissions have expired. Please reopen the project folder."])
                }

                guard url.startAccessingSecurityScopedResource() else {
                    throw NSError(domain: "SmartRefactorerError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to access project folder. Please reopen the project."])
                }

                defer { url.stopAccessingSecurityScopedResource() }
                return try operation(url)

            } catch {
                if error.localizedDescription.contains("SmartRefactorerError") {
                    throw error
                } else {
                    throw NSError(domain: "SmartRefactorerError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unable to access project folder. Please reopen the project to grant permissions again."])
                }
            }
        } else {
            throw NSError(domain: "SmartRefactorerError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Project access permissions not found. Please reopen the project folder to grant write permissions."])
        }
    }
    
    /// Reload translation data into Core Data after refactoring
    private func reloadTranslationData(for project: Project) async {
        // This would trigger a reload of the translation data
        // For now, we'll just mark that the project needs to be refreshed
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("ProjectDataChanged"),
                object: project
            )
        }
    }
}
