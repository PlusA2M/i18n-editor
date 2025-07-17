//
//  SvelteFileScanner.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import Foundation
import RegexBuilder

/// Scans Svelte files for i18n usage patterns and extracts i18n keys
class SvelteFileScanner: ObservableObject {
    private let fileSystemManager = FileSystemManager()

    @Published var isScanning = false
    @Published var scanProgress: Double = 0.0
    @Published var currentFile: String = ""
    @Published var foundKeys: [I18nKeyUsage] = []

    // Regex patterns for detecting i18n usage
    private let i18nPatterns: [NSRegularExpression] = {
        let patterns = [
            // Pattern: m.keyName()
            #"m\.([a-zA-Z_][a-zA-Z0-9_]*)\(\)"#,
            // Pattern: m.nested.keyName()
            #"m\.([a-zA-Z_][a-zA-Z0-9_.]*)\(\)"#,
            // Pattern: m.keyName(params)
            #"m\.([a-zA-Z_][a-zA-Z0-9_.]*)\([^)]*\)"#,
            // Pattern: $m.keyName (reactive statement)
            #"\$m\.([a-zA-Z_][a-zA-Z0-9_.]*)"#,
            // Pattern: {m.keyName()} in template
            #"\{m\.([a-zA-Z_][a-zA-Z0-9_.]*)\(\)\}"#,
            // Pattern: {m.keyName} in template
            #"\{m\.([a-zA-Z_][a-zA-Z0-9_.]*)\}"#
        ]

        return patterns.compactMap { pattern in
            try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
    }()

    // MARK: - Main Scanning Methods

    /// Scan all Svelte files in project for i18n usage
    func scanProject(_ project: Project) async -> [I18nKeyUsage] {
        guard let projectPath = project.path else { return [] }

        await MainActor.run {
            isScanning = true
            scanProgress = 0.0
            foundKeys = []
        }

        defer {
            Task { @MainActor in
                isScanning = false
                currentFile = ""
            }
        }

        let svelteFiles = fileSystemManager.scanSvelteFiles(in: projectPath)
        var allKeyUsages: [I18nKeyUsage] = []

        for (index, svelteFile) in svelteFiles.enumerated() {
            await MainActor.run {
                currentFile = svelteFile.relativePath
                scanProgress = Double(index) / Double(svelteFiles.count)
            }

            let keyUsages = scanSvelteFile(svelteFile, project: project)
            allKeyUsages.append(contentsOf: keyUsages)

            await MainActor.run {
                foundKeys.append(contentsOf: keyUsages)
            }
        }

        await MainActor.run {
            scanProgress = 1.0
        }

        return allKeyUsages
    }

    /// Scan a single Svelte file for i18n usage
    func scanSvelteFile(_ svelteFile: SvelteFile, project: Project) -> [I18nKeyUsage] {
        let content = svelteFile.content
        let lines = content.components(separatedBy: .newlines)
        var keyUsages: [I18nKeyUsage] = []

        for (lineIndex, line) in lines.enumerated() {
            let lineNumber = lineIndex + 1
            let usages = scanLine(line, lineNumber: lineNumber, file: svelteFile, project: project)
            keyUsages.append(contentsOf: usages)
        }

        return keyUsages
    }

    /// Scan a single line for i18n patterns
    private func scanLine(_ line: String, lineNumber: Int, file: SvelteFile, project: Project) -> [I18nKeyUsage] {
        var keyUsages: [I18nKeyUsage] = []
        let nsLine = line as NSString

        for pattern in i18nPatterns {
            let matches = pattern.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))

            for match in matches {
                if match.numberOfRanges > 1 {
                    let keyRange = match.range(at: 1)
                    let key = nsLine.substring(with: keyRange)

                    // Get the full match for context
                    let fullMatchRange = match.range(at: 0)
                    let fullMatch = nsLine.substring(with: fullMatchRange)

                    // Calculate column position
                    let columnNumber = fullMatchRange.location + 1

                    // Extract surrounding context
                    let context = extractContext(from: line, matchRange: fullMatchRange)

                    let keyUsage = I18nKeyUsage(
                        key: key,
                        filePath: file.path,
                        relativePath: file.relativePath,
                        lineNumber: lineNumber,
                        columnNumber: columnNumber,
                        context: context,
                        fullMatch: fullMatch,
                        detectedAt: Date(),
                        project: project
                    )

                    keyUsages.append(keyUsage)
                }
            }
        }

        return keyUsages
    }

    /// Extract context around the match
    private func extractContext(from line: String, matchRange: NSRange) -> String {
        let nsLine = line as NSString
        let contextRadius = 20

        let startIndex = max(0, matchRange.location - contextRadius)
        let endIndex = min(nsLine.length, matchRange.location + matchRange.length + contextRadius)

        let contextRange = NSRange(location: startIndex, length: endIndex - startIndex)
        var context = nsLine.substring(with: contextRange)

        // Add ellipsis if truncated
        if startIndex > 0 {
            context = "..." + context
        }
        if endIndex < nsLine.length {
            context = context + "..."
        }

        return context.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Key Analysis Methods

    /// Analyze key structure and suggest improvements
    func analyzeKeyStructure(_ keyUsages: [I18nKeyUsage]) -> KeyAnalysisResult {
        var keyStats: [String: KeyStatistics] = [:]
        var routeBasedSuggestions: [RefactoringSuggestion] = []

        // Group keys by usage
        for usage in keyUsages {
            if keyStats[usage.key] == nil {
                keyStats[usage.key] = KeyStatistics(key: usage.key)
            }
            keyStats[usage.key]?.usageCount += 1
            keyStats[usage.key]?.files.insert(usage.relativePath)
            keyStats[usage.key]?.usages.append(usage)
        }

        // Analyze route-based organization opportunities
        for (key, stats) in keyStats {
            let suggestions = analyzeRouteBasedRefactoring(key: key, statistics: stats)
            routeBasedSuggestions.append(contentsOf: suggestions)
        }

        return KeyAnalysisResult(
            totalKeys: keyStats.count,
            totalUsages: keyUsages.count,
            keyStatistics: Array(keyStats.values),
            routeBasedSuggestions: routeBasedSuggestions,
            duplicateKeys: findDuplicateKeys(keyStats),
            unusedKeys: [], // TODO: Implement unused key detection
            missingKeys: [] // TODO: Implement missing key detection
        )
    }

    /// Analyze route-based refactoring opportunities
    private func analyzeRouteBasedRefactoring(key: String, statistics: KeyStatistics) -> [RefactoringSuggestion] {
        var suggestions: [RefactoringSuggestion] = []

        // Check if key is used in specific route directories
        let routeFiles = statistics.files.filter { $0.contains("routes/") }

        if !routeFiles.isEmpty {
            // Group by route
            var routeGroups: [String: [String]] = [:]

            for file in routeFiles {
                if let routeMatch = extractRoute(from: file) {
                    if routeGroups[routeMatch] == nil {
                        routeGroups[routeMatch] = []
                    }
                    routeGroups[routeMatch]?.append(file)
                }
            }

            // Suggest refactoring if key is used primarily in one route
            for (route, files) in routeGroups {
                if files.count >= statistics.usageCount * 2 / 3 { // 2/3 threshold
                    let suggestedKey = "\(route).\(key)"
                    let suggestion = RefactoringSuggestion(
                        id: UUID(),
                        originalKey: key,
                        suggestedKey: suggestedKey,
                        type: .routeBased,
                        reason: "Key is primarily used in \(route) route",
                        confidence: calculateConfidence(files.count, total: statistics.usageCount),
                        affectedFiles: files,
                        estimatedImpact: .medium,
                        autoApplicable: true
                    )

                    suggestions.append(suggestion)
                }
            }
        }

        return suggestions
    }

    /// Extract route name from file path
    private func extractRoute(from filePath: String) -> String? {
        let components = filePath.components(separatedBy: "/")

        if let routesIndex = components.firstIndex(of: "routes") {
            let routeComponents = Array(components[(routesIndex + 1)...])

            // Remove file extension and special SvelteKit files
            let cleanComponents = routeComponents.compactMap { component -> String? in
                let cleaned = component.replacingOccurrences(of: "+page.svelte", with: "")
                    .replacingOccurrences(of: "+layout.svelte", with: "")
                    .replacingOccurrences(of: ".svelte", with: "")

                return cleaned.isEmpty ? nil : cleaned
            }

            return cleanComponents.isEmpty ? "home" : cleanComponents.joined(separator: ".")
        }

        return nil
    }

    /// Calculate confidence score for refactoring suggestion
    private func calculateConfidence(_ usageInRoute: Int, total: Int) -> Double {
        return Double(usageInRoute) / Double(total)
    }

    /// Find duplicate keys (keys with same name but different casing or similar)
    private func findDuplicateKeys(_ keyStats: [String: KeyStatistics]) -> [DuplicateKeyGroup] {
        var duplicateGroups: [DuplicateKeyGroup] = []
        let keys = Array(keyStats.keys)

        for i in 0..<keys.count {
            for j in (i + 1)..<keys.count {
                let key1 = keys[i]
                let key2 = keys[j]

                if areSimilarKeys(key1, key2) {
                    let group = DuplicateKeyGroup(
                        keys: [key1, key2],
                        similarity: calculateSimilarity(key1, key2),
                        suggestion: "Consider consolidating similar keys"
                    )
                    duplicateGroups.append(group)
                }
            }
        }

        return duplicateGroups
    }

    /// Check if two keys are similar
    private func areSimilarKeys(_ key1: String, _ key2: String) -> Bool {
        // Simple similarity check - can be enhanced
        let similarity = calculateSimilarity(key1, key2)
        return similarity > 0.8 && key1 != key2
    }

    /// Calculate similarity between two strings
    private func calculateSimilarity(_ str1: String, _ str2: String) -> Double {
        let longer = str1.count > str2.count ? str1 : str2
        let shorter = str1.count > str2.count ? str2 : str1

        if longer.isEmpty { return 1.0 }

        let editDistance = levenshteinDistance(str1, str2)
        return (Double(longer.count) - Double(editDistance)) / Double(longer.count)
    }

    /// Calculate Levenshtein distance
    private func levenshteinDistance(_ str1: String, _ str2: String) -> Int {
        let a = Array(str1)
        let b = Array(str2)

        var matrix = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)

        for i in 0...a.count {
            matrix[i][0] = i
        }

        for j in 0...b.count {
            matrix[0][j] = j
        }

        for i in 1...a.count {
            for j in 1...b.count {
                if a[i-1] == b[j-1] {
                    matrix[i][j] = matrix[i-1][j-1]
                } else {
                    matrix[i][j] = min(
                        matrix[i-1][j] + 1,
                        matrix[i][j-1] + 1,
                        matrix[i-1][j-1] + 1
                    )
                }
            }
        }

        return matrix[a.count][b.count]
    }
}

// MARK: - Supporting Types

struct I18nKeyUsage: Identifiable {
    let id = UUID()
    let key: String
    let filePath: String
    let relativePath: String
    let lineNumber: Int
    let columnNumber: Int
    let context: String
    let fullMatch: String
    let detectedAt: Date
    let project: Project
}

class KeyStatistics {
    let key: String
    var usageCount: Int = 0
    var files: Set<String> = []
    var usages: [I18nKeyUsage] = []

    init(key: String) {
        self.key = key
    }
}

struct KeyAnalysisResult {
    let totalKeys: Int
    let totalUsages: Int
    let keyStatistics: [KeyStatistics]
    let routeBasedSuggestions: [RefactoringSuggestion]
    let duplicateKeys: [DuplicateKeyGroup]
    let unusedKeys: [String]
    let missingKeys: [String]
}

struct DuplicateKeyGroup: Identifiable {
    let id = UUID()
    let keys: [String]
    let similarity: Double
    let suggestion: String
}
