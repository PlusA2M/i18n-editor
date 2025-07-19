//
//  UsageTrackingDebugger.swift
//  i18n editor
//
//  Created by PlusA on 18/07/2025.
//

import Foundation
import SwiftUI
import os.log

/// Debug utility for diagnosing usage tracking issues
class UsageTrackingDebugger: ObservableObject {
    private let logger = Logger(subsystem: "com.plusa.i18n-editor", category: "UsageTracking")
    private let fileSystemManager = FileSystemManager()
    private let svelteScanner = SvelteFileScanner()
    private let permissionManager = PermissionManager()

    @Published var debugLog: [DebugLogEntry] = []
    @Published var isDebugging = false
    @Published var debugProgress: Double = 0.0
    @Published var currentOperation: String = ""

    // MARK: - Debug Operations

    /// Run comprehensive debug analysis of usage tracking
    func runDebugAnalysis(for project: Project) async {
        await MainActor.run {
            isDebugging = true
            debugProgress = 0.0
            debugLog.removeAll()
            currentOperation = "Starting debug analysis..."
        }

        defer {
            Task { @MainActor in
                isDebugging = false
                currentOperation = ""
            }
        }

        guard let projectPath = project.path else {
            await logError("Project path is nil")
            return
        }

        // Step 1: Check permissions
        await updateProgress(0.1, "Checking file permissions...")
        await checkPermissions(projectPath: projectPath)

        // Step 2: Verify project structure
        await updateProgress(0.2, "Verifying project structure...")
        await verifyProjectStructure(projectPath: projectPath)

        // Step 3: Test file scanning
        await updateProgress(0.4, "Testing file scanning...")
        await testFileScanning(projectPath: projectPath)

        // Step 4: Test regex patterns
        await updateProgress(0.6, "Testing regex patterns...")
        await testRegexPatterns()

        // Step 5: Test actual file scanning
        await updateProgress(0.7, "Testing actual file scanning...")
        await testActualFileScanning(projectPath: projectPath)

        // Step 5.5: Create and test sample file
        await updateProgress(0.75, "Testing with sample file...")
        await testWithSampleFile(projectPath: projectPath)

        // Step 6: Test database operations
        await updateProgress(0.8, "Testing database operations...")
        await testDatabaseOperations(project: project)

        // Step 7: Generate summary
        await updateProgress(1.0, "Generating debug summary...")
        await generateDebugSummary()

        await logInfo("Debug analysis completed")
    }

    // MARK: - Permission Checking

    private func checkPermissions(projectPath: String) async {
        await logInfo("=== PERMISSION ANALYSIS ===")

        // Check Full Disk Access
        let hasFullDiskAccess = permissionManager.checkFullDiskAccess()
        await logInfo("Full Disk Access: \(hasFullDiskAccess ? "✅ Granted" : "❌ Not granted")")

        // Check project path access
        let canAccessProject = permissionManager.canAccessProject(at: projectPath)
        await logInfo("Project path access: \(canAccessProject ? "✅ Accessible" : "❌ Not accessible")")

        // Check security-scoped bookmarks
        let bookmarkKey = "bookmark_\(projectPath)"
        let hasBookmark = UserDefaults.standard.data(forKey: bookmarkKey) != nil
        await logInfo("Security-scoped bookmark: \(hasBookmark ? "✅ Found" : "❌ Not found")")

        // Test file system access
        let fileManager = FileManager.default
        let srcPath = URL(fileURLWithPath: projectPath).appendingPathComponent("src")
        let srcExists = fileManager.fileExists(atPath: srcPath.path)
        await logInfo("Source directory exists: \(srcExists ? "✅ Yes" : "❌ No")")

        if srcExists {
            let isReadable = fileManager.isReadableFile(atPath: srcPath.path)
            await logInfo("Source directory readable: \(isReadable ? "✅ Yes" : "❌ No")")
        }

        // Test file enumeration
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: projectPath)
            await logInfo("Project directory contents: \(contents.count) items")
            await logInfo("Contents: \(contents.prefix(10).joined(separator: ", "))")
        } catch {
            await logError("Failed to enumerate project directory: \(error.localizedDescription)")
        }
    }

    // MARK: - Project Structure Verification

    private func verifyProjectStructure(projectPath: String) async {
        await logInfo("=== PROJECT STRUCTURE ANALYSIS ===")

        let fileManager = FileManager.default
        let projectURL = URL(fileURLWithPath: projectPath)

        // Check for common SvelteKit directories
        let expectedDirs = ["src", "src/routes", "src/lib", "static"]
        for dir in expectedDirs {
            let dirPath = projectURL.appendingPathComponent(dir).path
            let exists = fileManager.fileExists(atPath: dirPath)
            await logInfo("\(dir): \(exists ? "✅ Found" : "❌ Missing")")
        }

        // Check for inlang configuration
        let inlangConfigPath = projectURL.appendingPathComponent("project.inlang/settings.json").path
        let hasInlangConfig = fileManager.fileExists(atPath: inlangConfigPath)
        await logInfo("Inlang config: \(hasInlangConfig ? "✅ Found" : "❌ Missing")")

        // Check for package.json
        let packageJsonPath = projectURL.appendingPathComponent("package.json").path
        let hasPackageJson = fileManager.fileExists(atPath: packageJsonPath)
        await logInfo("package.json: \(hasPackageJson ? "✅ Found" : "❌ Missing")")
    }

    // MARK: - File Scanning Test

    private func testFileScanning(projectPath: String) async {
        await logInfo("=== FILE SCANNING TEST ===")

        // Test FileSystemManager scanning
        let svelteFiles = fileSystemManager.scanSvelteFiles(in: projectPath)
        await logInfo("Svelte files found: \(svelteFiles.count)")

        if let lastError = fileSystemManager.lastScanError {
            await logError("File scanning error: \(lastError)")
        }

        // Log first few files for verification
        for (index, file) in svelteFiles.prefix(5).enumerated() {
            await logInfo("File \(index + 1): \(file.relativePath) (\(file.fileSize) bytes)")
        }

        // Test manual file enumeration
        do {
            let srcPath = URL(fileURLWithPath: projectPath).appendingPathComponent("src")
            let allFiles = try fileSystemManager.getAllFiles(in: srcPath, withExtension: "svelte")
            await logInfo("Manual enumeration found: \(allFiles.count) .svelte files")
        } catch {
            await logError("Manual file enumeration failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Regex Pattern Testing

    private func testRegexPatterns() async {
        await logInfo("=== REGEX PATTERN TESTING ===")

        let testCases = [
            // Basic function calls
            "m.hello()",
            "m.hello( )",
            "m.nested.key()",
            "m.deeply.nested.key()",

            // Function calls with parameters
            "m.withParams({name: 'test'})",
            "m.greeting('John', 'Doe')",
            "m.complex({ user: data.user, count: items.length })",

            // Reactive statements (Svelte)
            "$m.reactive",
            "$m.nested.reactive",

            // Template expressions
            "{m.template()}",
            "{m.template( )}",
            "{ m.template() }",
            "{m.simpleTemplate}",
            "{ m.simpleTemplate }",
            "{m.withParams(data)}",
            "{ m.withParams(data) }",

            // Direct property access
            "const text = m.assignment",
            "if (condition) m.conditional",
            "return m.result",

            // Quoted strings (dynamic access)
            "const key = 'm.dynamicKey'",
            "translate(\"m.quotedKey\")",

            // Bracket notation
            "m['bracketKey']",
            "m[\"doubleQuoteKey\"]",

            // Edge cases
            "m.key_with_underscores()",
            "m.key123()",
            "m._privateKey()",
            "m.CONSTANT_KEY",

            // Should NOT match
            "notm.fake()",
            "m.()",
            "m.123invalid()",
            "// m.commented()"
        ]

        // Get patterns from SvelteFileScanner (updated patterns)
        let patterns = [
            #"m\.([a-zA-Z_][a-zA-Z0-9_]*)\(\s*\)"#,
            #"m\.([a-zA-Z_][a-zA-Z0-9_.]*[a-zA-Z0-9_])\(\s*\)"#,
            #"m\.([a-zA-Z_][a-zA-Z0-9_.]*[a-zA-Z0-9_])\([^)]*\)"#,
            #"\$m\.([a-zA-Z_][a-zA-Z0-9_.]*[a-zA-Z0-9_])"#,
            #"\{\s*m\.([a-zA-Z_][a-zA-Z0-9_.]*[a-zA-Z0-9_])\(\s*\)\s*\}"#,
            #"\{\s*m\.([a-zA-Z_][a-zA-Z0-9_.]*[a-zA-Z0-9_])\s*\}"#,
            #"\{\s*m\.([a-zA-Z_][a-zA-Z0-9_.]*[a-zA-Z0-9_])\([^)]*\)\s*\}"#,
            #"m\.([a-zA-Z_][a-zA-Z0-9_.]*[a-zA-Z0-9_])(?!\()"#,
            #"['""]m\.([a-zA-Z_][a-zA-Z0-9_.]*[a-zA-Z0-9_])['""]"#,
            #"m\[['\""]([a-zA-Z_][a-zA-Z0-9_.]*[a-zA-Z0-9_])['\"\"]\]"#
        ]

        let regexPatterns = patterns.compactMap { pattern in
            do {
                return try NSRegularExpression(pattern: pattern, options: [])
            } catch {
                print("Failed to compile pattern: \(pattern) - \(error)")
                return nil
            }
        }

        await logInfo("Compiled \(regexPatterns.count) regex patterns")

        for (index, testCase) in testCases.enumerated() {
            var matchFound = false
            for (patternIndex, regex) in regexPatterns.enumerated() {
                let range = NSRange(location: 0, length: testCase.count)
                let matches = regex.matches(in: testCase, options: [], range: range)

                if !matches.isEmpty {
                    let match = matches[0]
                    if match.numberOfRanges > 1 {
                        let keyRange = match.range(at: 1)
                        let key = (testCase as NSString).substring(with: keyRange)
                        await logInfo("Test \(index + 1): '\(testCase)' → Pattern \(patternIndex + 1) → Key: '\(key)'")
                        matchFound = true
                        break
                    }
                }
            }

            if !matchFound {
                await logWarning("Test \(index + 1): '\(testCase)' → No matches found")
            }
        }
    }

    // MARK: - Actual File Scanning Test

    private func testActualFileScanning(projectPath: String) async {
        await logInfo("=== ACTUAL FILE SCANNING TEST ===")

        // Run the actual scanner
        let scanner = SvelteFileScanner()
        let dataManager = DataManager.shared
        let project = dataManager.createProject(name: "Debug Test Project", path: projectPath)

        let keyUsages = await scanner.scanProject(project)
        await logInfo("Scanner found \(keyUsages.count) key usages")

        if let scanError = scanner.lastScanError {
            await logError("Scanner error: \(scanError)")
        }

        if let stats = scanner.scanStatistics {
            await logInfo("Scan statistics:")
            await logInfo("  Files scanned: \(stats.filesScanned)")
            await logInfo("  Files with matches: \(stats.filesWithMatches)")
            await logInfo("  Total matches: \(stats.totalMatches)")
            await logInfo("  Scan duration: \(String(format: "%.2f", stats.scanDuration))s")
            await logInfo("  Average matches per file: \(String(format: "%.2f", stats.averageMatchesPerFile))")
        }

        // Show sample results
        let sampleUsages = Array(keyUsages.prefix(10))
        for (index, usage) in sampleUsages.enumerated() {
            await logInfo("Usage \(index + 1): '\(usage.key)' in \(usage.relativePath):\(usage.lineNumber)")
            await logInfo("  Context: \(usage.context)")
        }

        if keyUsages.isEmpty {
            await logWarning("No key usages found - this indicates a problem with the scanning process")
        }

        // Clean up test project
        dataManager.deleteProject(project)
    }

    // MARK: - Sample File Test

    private func testWithSampleFile(projectPath: String) async {
        await logInfo("=== SAMPLE FILE TEST ===")

        let dataManager = DataManager.shared
        let sampleContent = """
        <script>
            import { m } from '$lib/i18n';

            // Various usage patterns
            const greeting = m.hello();
            const nested = m.user.profile.name();
            const withParams = m.greeting('John', 'Doe');
            const reactive = $m.counter;
            const directAccess = m.title;
            const dynamicKey = m['dynamic.key'];
            const quotedKey = "m.quoted.key";
        </script>

        <h1>{m.pageTitle()}</h1>
        <p>{ m.description }</p>
        <button on:click={() => alert(m.button.click())}>{m.button.label}</button>

        {#if condition}
            <span>{m.conditional.message(data)}</span>
        {/if}
        """

        // Create temporary test file
        var testFilePath: String? = nil
        do {
            let srcDir = URL(fileURLWithPath: projectPath).appendingPathComponent("src")
            let testFile = srcDir.appendingPathComponent("DebugTest.svelte")

            // Ensure src directory exists
            try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)

            try sampleContent.write(to: testFile, atomically: true, encoding: .utf8)
            testFilePath = testFile.path

            await logInfo("Created test file: \(testFile.path)")

            // Test scanning this specific file
            let scanner = SvelteFileScanner()
            let project = dataManager.createProject(name: "Sample File Test Project", path: projectPath)

            let svelteFile = SvelteFile(
                path: testFile.path,
                relativePath: "src/DebugTest.svelte",
                content: sampleContent,
                modificationDate: Date(),
                fileSize: Int64(sampleContent.count)
            )

            let keyUsages = scanner.scanSvelteFile(svelteFile, project: project)
            await logInfo("Found \(keyUsages.count) key usages in test file:")

            for usage in keyUsages {
                await logInfo("  Line \(usage.lineNumber): '\(usage.key)' - \(usage.fullMatch)")
            }

            // Expected keys
            let expectedKeys = [
                "hello", "user.profile.name", "greeting", "counter", "title",
                "dynamic.key", "quoted.key", "pageTitle", "description",
                "button.click", "button.label", "conditional.message"
            ]

            let foundKeys = Set(keyUsages.map { $0.key })
            let expectedSet = Set(expectedKeys)
            let missing = expectedSet.subtracting(foundKeys)
            let unexpected = foundKeys.subtracting(expectedSet)

            if missing.isEmpty && unexpected.isEmpty {
                await logInfo("✅ All expected keys found, no unexpected keys")
            } else {
                if !missing.isEmpty {
                    await logWarning("❌ Missing expected keys: \(missing.joined(separator: ", "))")
                }
                if !unexpected.isEmpty {
                    await logInfo("ℹ️ Unexpected keys found: \(unexpected.joined(separator: ", "))")
                }
            }

            // Clean up test project
            dataManager.deleteProject(project)

        } catch {
            await logError("Failed to create test file: \(error.localizedDescription)")
        }

        // Clean up test file
        if let testFilePath = testFilePath {
            try? FileManager.default.removeItem(atPath: testFilePath)
            await logInfo("Cleaned up test file")
        }
    }

    // MARK: - Database Operations Test

    private func testDatabaseOperations(project: Project) async {
        await logInfo("=== DATABASE OPERATIONS TEST ===")

        let dataManager = DataManager.shared

        // Test fetching existing keys
        let existingKeys = dataManager.getI18nKeys(for: project)
        await logInfo("Existing i18n keys in database: \(existingKeys.count)")

        // Test fetching file usages
        let allFileUsages = project.fileUsages?.allObjects as? [FileUsage] ?? []
        await logInfo("Existing file usages in database: \(allFileUsages.count)")

        // Log some sample data
        for (index, key) in existingKeys.prefix(5).enumerated() {
            let usageCount = key.activeFileUsages.count
            await logInfo("Key \(index + 1): '\(key.key ?? "nil")' - \(usageCount) usages")
        }
    }

    // MARK: - Debug Summary

    private func generateDebugSummary() async {
        await logInfo("=== DEBUG SUMMARY ===")

        let errorCount = debugLog.filter { $0.level == .error }.count
        let warningCount = debugLog.filter { $0.level == .warning }.count
        let infoCount = debugLog.filter { $0.level == .info }.count

        await logInfo("Total log entries: \(debugLog.count)")
        await logInfo("Errors: \(errorCount), Warnings: \(warningCount), Info: \(infoCount)")

        if errorCount > 0 {
            await logError("❌ Issues detected that may prevent usage tracking from working")
        } else if warningCount > 0 {
            await logWarning("⚠️ Some issues detected that may affect usage tracking performance")
        } else {
            await logInfo("✅ No critical issues detected")
        }
    }

    // MARK: - Logging Helpers

    private func updateProgress(_ progress: Double, _ operation: String) async {
        await MainActor.run {
            self.debugProgress = progress
            self.currentOperation = operation
        }
    }

    private func logInfo(_ message: String) async {
        logger.info("\(message)")
        await addLogEntry(message, level: .info)
    }

    private func logWarning(_ message: String) async {
        logger.warning("\(message)")
        await addLogEntry(message, level: .warning)
    }

    private func logError(_ message: String) async {
        logger.error("\(message)")
        await addLogEntry(message, level: .error)
    }

    private func addLogEntry(_ message: String, level: DebugLogLevel) async {
        let entry = DebugLogEntry(
            timestamp: Date(),
            level: level,
            message: message
        )

        await MainActor.run {
            self.debugLog.append(entry)
        }
    }
}

// MARK: - Supporting Types

struct DebugLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: DebugLogLevel
    let message: String
}

enum DebugLogLevel {
    case info
    case warning
    case error

    var icon: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}
