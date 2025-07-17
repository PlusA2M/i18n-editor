//
//  LocaleFileManager.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import Foundation

/// Manages locale file discovery, parsing, and manipulation with support for flat and nested JSON structures
class LocaleFileManager: ObservableObject {
    private let fileManager = FileManager.default
    
    @Published var isLoading = false
    @Published var lastError: LocaleFileError?
    @Published var discoveredFiles: [LocaleFileInfo] = []
    
    // MARK: - File Discovery
    
    /// Discover locale files using path pattern from inlang configuration
    func discoverLocaleFiles(config: InlangConfiguration, projectPath: String) -> [LocaleFileInfo] {
        isLoading = true
        lastError = nil
        
        defer { 
            isLoading = false 
            DispatchQueue.main.async {
                self.discoveredFiles = self.discoveredFiles
            }
        }
        
        guard let pathPattern = config.pathPattern else {
            lastError = .noPathPattern
            return []
        }
        
        var localeFiles: [LocaleFileInfo] = []
        
        for locale in config.locales {
            let filePath = resolvePathPattern(pathPattern, locale: locale, projectPath: projectPath)
            let fileInfo = analyzeLocaleFile(path: filePath, locale: locale, config: config)
            localeFiles.append(fileInfo)
        }
        
        discoveredFiles = localeFiles
        return localeFiles
    }
    
    /// Resolve path pattern with locale placeholder
    private func resolvePathPattern(_ pattern: String, locale: String, projectPath: String) -> String {
        let projectURL = URL(fileURLWithPath: projectPath)
        var resolvedPattern = pattern.replacingOccurrences(of: "{locale}", with: locale)
        
        // Handle different path formats
        if resolvedPattern.hasPrefix("./") {
            // Relative to project root
            resolvedPattern = String(resolvedPattern.dropFirst(2))
            return projectURL.appendingPathComponent(resolvedPattern).path
        } else if resolvedPattern.hasPrefix("/") {
            // Absolute path
            return resolvedPattern
        } else {
            // Relative to project root (no ./ prefix)
            return projectURL.appendingPathComponent(resolvedPattern).path
        }
    }
    
    /// Analyze a locale file and extract information
    private func analyzeLocaleFile(path: String, locale: String, config: InlangConfiguration) -> LocaleFileInfo {
        let url = URL(fileURLWithPath: path)
        let exists = fileManager.fileExists(atPath: path)
        
        var content: [String: Any] = [:]
        var structure: LocaleFileStructure = .flat
        var keyCount = 0
        var fileSize: Int64 = 0
        var lastModified = Date.distantPast
        var parseError: String?
        
        if exists {
            do {
                let data = try Data(contentsOf: url)
                content = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                
                // Analyze structure
                structure = analyzeStructure(content)
                keyCount = countKeys(in: content)
                
                // Get file attributes
                let attributes = try fileManager.attributesOfItem(atPath: path)
                fileSize = attributes[.size] as? Int64 ?? 0
                lastModified = attributes[.modificationDate] as? Date ?? Date.distantPast
                
            } catch {
                parseError = error.localizedDescription
            }
        }
        
        return LocaleFileInfo(
            locale: locale,
            path: path,
            relativePath: getRelativePath(path, projectPath: extractProjectPath(from: path)),
            exists: exists,
            content: content,
            structure: structure,
            keyCount: keyCount,
            fileSize: fileSize,
            lastModified: lastModified,
            parseError: parseError
        )
    }
    
    /// Analyze the structure of locale file content
    private func analyzeStructure(_ content: [String: Any]) -> LocaleFileStructure {
        var hasNestedObjects = false
        var maxDepth = 1
        
        func checkDepth(_ obj: Any, currentDepth: Int) -> Int {
            var depth = currentDepth
            
            if let dict = obj as? [String: Any] {
                hasNestedObjects = true
                for value in dict.values {
                    depth = max(depth, checkDepth(value, currentDepth: currentDepth + 1))
                }
            }
            
            return depth
        }
        
        for value in content.values {
            maxDepth = max(maxDepth, checkDepth(value, currentDepth: 1))
        }
        
        if !hasNestedObjects {
            return .flat
        } else if maxDepth <= 2 {
            return .shallow
        } else {
            return .deep
        }
    }
    
    /// Count total number of translation keys
    private func countKeys(in content: [String: Any]) -> Int {
        var count = 0
        
        func countInObject(_ obj: Any) {
            if let dict = obj as? [String: Any] {
                for value in dict.values {
                    if value is String {
                        count += 1
                    } else {
                        countInObject(value)
                    }
                }
            }
        }
        
        countInObject(content)
        return count
    }
    
    // MARK: - File Operations
    
    /// Load locale file content
    func loadLocaleFile(_ fileInfo: LocaleFileInfo) -> LocaleFileContent? {
        guard fileInfo.exists else { return nil }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: fileInfo.path))
            let content = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            
            let flattenedKeys = flattenKeys(content)
            let nestedKeys = organizeKeysHierarchically(flattenedKeys)
            
            return LocaleFileContent(
                locale: fileInfo.locale,
                rawContent: content,
                flattenedKeys: flattenedKeys,
                nestedKeys: nestedKeys,
                structure: fileInfo.structure
            )
            
        } catch {
            lastError = .loadError(path: fileInfo.path, error: error)
            return nil
        }
    }
    
    /// Save locale file content
    func saveLocaleFile(_ fileInfo: LocaleFileInfo, content: [String: Any]) throws {
        let url = URL(fileURLWithPath: fileInfo.path)
        
        // Create directory if it doesn't exist
        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        // Serialize content
        let data = try JSONSerialization.data(withJSONObject: content, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])

        // Write to file
        try data.write(to: url)
    }
    
    /// Create backup of locale file
    func createBackup(_ fileInfo: LocaleFileInfo) throws -> String {
        guard fileInfo.exists else {
            throw LocaleFileError.fileNotFound(path: fileInfo.path)
        }
        
        let url = URL(fileURLWithPath: fileInfo.path)
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupURL = url.appendingPathExtension("backup.\(timestamp)")
        
        try fileManager.copyItem(at: url, to: backupURL)
        return backupURL.path
    }
    
    // MARK: - Key Manipulation
    
    /// Flatten nested keys to dot notation
    func flattenKeys(_ content: [String: Any], prefix: String = "") -> [String: String] {
        var flattened: [String: String] = [:]

        for (key, value) in content {
            // Skip $schema property as it's used for JSON schema validation
            if key == "$schema" {
                continue
            }

            let fullKey = prefix.isEmpty ? key : "\(prefix).\(key)"

            if let stringValue = value as? String {
                flattened[fullKey] = stringValue
            } else if let nestedDict = value as? [String: Any] {
                let nestedFlattened = flattenKeys(nestedDict, prefix: fullKey)
                flattened.merge(nestedFlattened) { _, new in new }
            }
        }

        return flattened
    }
    
    /// Convert flattened keys back to nested structure
    func unflattenKeys(_ flattenedKeys: [String: String]) -> [String: Any] {
        var nested: [String: Any] = [:]
        
        for (key, value) in flattenedKeys {
            setNestedValue(&nested, keyPath: key, value: value)
        }
        
        return nested
    }
    
    /// Set value in nested dictionary using dot notation
    private func setNestedValue(_ dict: inout [String: Any], keyPath: String, value: String) {
        let components = keyPath.components(separatedBy: ".")
        
        guard !components.isEmpty else { return }
        
        if components.count == 1 {
            dict[components[0]] = value
            return
        }
        
        let firstComponent = components[0]
        let remainingPath = components.dropFirst().joined(separator: ".")
        
        if dict[firstComponent] == nil {
            dict[firstComponent] = [String: Any]()
        }
        
        if var nestedDict = dict[firstComponent] as? [String: Any] {
            setNestedValue(&nestedDict, keyPath: remainingPath, value: value)
            dict[firstComponent] = nestedDict
        }
    }
    
    /// Organize keys hierarchically for UI display
    func organizeKeysHierarchically(_ flattenedKeys: [String: String]) -> [KeyNode] {
        var rootNodes: [KeyNode] = []
        var nodeMap: [String: KeyNode] = [:]
        
        // Sort keys to ensure proper hierarchy
        let sortedKeys = flattenedKeys.keys.sorted()
        
        for key in sortedKeys {
            let components = key.components(separatedBy: ".")
            let value = flattenedKeys[key] ?? ""
            
            var currentPath = ""
            var parentNode: KeyNode?
            
            for (index, component) in components.enumerated() {
                currentPath = currentPath.isEmpty ? component : "\(currentPath).\(component)"
                
                if let existingNode = nodeMap[currentPath] {
                    parentNode = existingNode
                } else {
                    let isLeaf = index == components.count - 1
                    let node = KeyNode(
                        key: component,
                        fullKey: currentPath,
                        value: isLeaf ? value : nil,
                        children: [],
                        isLeaf: isLeaf
                    )
                    
                    nodeMap[currentPath] = node
                    
                    if let parent = parentNode {
                        parent.children.append(node)
                    } else {
                        rootNodes.append(node)
                    }
                    
                    parentNode = node
                }
            }
        }
        
        return rootNodes
    }
    
    // MARK: - Validation and Analysis
    
    /// Validate locale file structure and content
    func validateLocaleFile(_ fileInfo: LocaleFileInfo) -> [LocaleValidationIssue] {
        var issues: [LocaleValidationIssue] = []
        
        // Check if file exists
        if !fileInfo.exists {
            issues.append(LocaleValidationIssue(
                type: .error,
                message: "Locale file does not exist",
                key: nil,
                suggestion: "Create the file with basic structure"
            ))
            return issues
        }
        
        // Check for parse errors
        if let parseError = fileInfo.parseError {
            issues.append(LocaleValidationIssue(
                type: .error,
                message: "Failed to parse JSON: \(parseError)",
                key: nil,
                suggestion: "Fix JSON syntax errors"
            ))
            return issues
        }
        
        // Check for empty file
        if fileInfo.keyCount == 0 {
            issues.append(LocaleValidationIssue(
                type: .warning,
                message: "Locale file is empty",
                key: nil,
                suggestion: "Add translation keys"
            ))
        }
        
        // Validate individual keys
        let flattenedKeys = flattenKeys(fileInfo.content)
        
        for (key, value) in flattenedKeys {
            // Check for empty values
            if value.isEmpty {
                issues.append(LocaleValidationIssue(
                    type: .warning,
                    message: "Translation value is empty",
                    key: key,
                    suggestion: "Provide translation for this key"
                ))
            }
            
            // Check for very long translations
            if value.count > 500 {
                issues.append(LocaleValidationIssue(
                    type: .info,
                    message: "Translation is very long (\(value.count) characters)",
                    key: key,
                    suggestion: "Consider breaking into smaller parts"
                ))
            }
            
            // Check for HTML tags
            if value.contains("<") && value.contains(">") {
                issues.append(LocaleValidationIssue(
                    type: .info,
                    message: "Translation contains HTML tags",
                    key: key,
                    suggestion: "Verify HTML is intentional"
                ))
            }
        }
        
        return issues
    }
    
    /// Compare locale files to find missing keys
    func compareLocaleFiles(_ files: [LocaleFileInfo]) -> LocaleComparisonResult {
        var allKeys: Set<String> = []
        var fileKeys: [String: Set<String>] = [:]
        
        // Collect all keys from all files
        for file in files {
            let flattenedKeys = flattenKeys(file.content)
            let keys = Set(flattenedKeys.keys)
            
            fileKeys[file.locale] = keys
            allKeys.formUnion(keys)
        }
        
        // Find missing keys for each locale
        var missingKeys: [String: [String]] = [:]
        
        for file in files {
            let keys = fileKeys[file.locale] ?? []
            let missing = allKeys.subtracting(keys)
            if !missing.isEmpty {
                missingKeys[file.locale] = Array(missing).sorted()
            }
        }
        
        return LocaleComparisonResult(
            totalKeys: allKeys.count,
            fileKeys: fileKeys,
            missingKeys: missingKeys,
            completionRates: calculateCompletionRates(fileKeys: fileKeys, totalKeys: allKeys.count)
        )
    }
    
    /// Calculate completion rates for each locale
    private func calculateCompletionRates(fileKeys: [String: Set<String>], totalKeys: Int) -> [String: Double] {
        var rates: [String: Double] = [:]
        
        for (locale, keys) in fileKeys {
            rates[locale] = totalKeys > 0 ? Double(keys.count) / Double(totalKeys) : 0.0
        }
        
        return rates
    }
    
    // MARK: - Utility Methods
    
    private func getRelativePath(_ path: String, projectPath: String) -> String {
        if path.hasPrefix(projectPath) {
            return String(path.dropFirst(projectPath.count + 1))
        }
        return path
    }
    
    private func extractProjectPath(from filePath: String) -> String {
        // Simple heuristic to extract project path
        let components = filePath.components(separatedBy: "/")
        if let messagesIndex = components.lastIndex(of: "messages") {
            return components.prefix(messagesIndex).joined(separator: "/")
        }
        return URL(fileURLWithPath: filePath).deletingLastPathComponent().path
    }
}

// MARK: - Supporting Types

struct LocaleFileInfo: Identifiable {
    let id = UUID()
    let locale: String
    let path: String
    let relativePath: String
    let exists: Bool
    let content: [String: Any]
    let structure: LocaleFileStructure
    let keyCount: Int
    let fileSize: Int64
    let lastModified: Date
    let parseError: String?
}

struct LocaleFileContent {
    let locale: String
    let rawContent: [String: Any]
    let flattenedKeys: [String: String]
    let nestedKeys: [KeyNode]
    let structure: LocaleFileStructure
}

class KeyNode: ObservableObject, Identifiable {
    let id = UUID()
    let key: String
    let fullKey: String
    var value: String?
    var children: [KeyNode]
    let isLeaf: Bool
    
    init(key: String, fullKey: String, value: String?, children: [KeyNode], isLeaf: Bool) {
        self.key = key
        self.fullKey = fullKey
        self.value = value
        self.children = children
        self.isLeaf = isLeaf
    }
}

enum LocaleFileStructure {
    case flat       // All keys at root level
    case shallow    // 1-2 levels of nesting
    case deep       // 3+ levels of nesting
}

struct LocaleValidationIssue {
    let type: LocaleValidationIssueType
    let message: String
    let key: String?
    let suggestion: String
}

enum LocaleValidationIssueType {
    case error
    case warning
    case info
}

struct LocaleComparisonResult {
    let totalKeys: Int
    let fileKeys: [String: Set<String>]
    let missingKeys: [String: [String]]
    let completionRates: [String: Double]
}

enum LocaleFileError: Error, LocalizedError {
    case noPathPattern
    case fileNotFound(path: String)
    case loadError(path: String, error: Error)
    case saveError(path: String, error: Error)
    case invalidStructure(message: String)
    
    var errorDescription: String? {
        switch self {
        case .noPathPattern:
            return "No path pattern found in configuration"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .loadError(let path, let error):
            return "Failed to load \(path): \(error.localizedDescription)"
        case .saveError(let path, let error):
            return "Failed to save \(path): \(error.localizedDescription)"
        case .invalidStructure(let message):
            return "Invalid file structure: \(message)"
        }
    }
}
