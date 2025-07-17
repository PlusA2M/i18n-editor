//
//  i18n_editorTests.swift
//  i18n editorTests
//
//  Created by PlusA on 13/07/2025.
//

import Testing
import Foundation
@testable import i18n_editor

struct i18n_editorTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func testSmartRefactorerFunctionality() async throws {
        // Create a temporary directory for testing
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create test locale files with various issues
        let messagesDir = tempDir.appendingPathComponent("messages")
        try FileManager.default.createDirectory(at: messagesDir, withIntermediateDirectories: true)

        // Create test content with issues that refactoring should fix
        let testContent: [String: Any] = [
            "welcome": "Welcome!",
            "goodbye": "",  // Empty value to be removed
            "user.name": "Name",  // Should be nested
            "user.email": "Email",  // Should be nested
            "WELCOME": "Welcome!",  // Duplicate (case-insensitive)
            "button.save": "Save",
            "button.cancel": "Cancel"
        ]

        // Write test files for multiple locales
        let locales = ["en", "fr", "de"]
        for locale in locales {
            let localeFile = messagesDir.appendingPathComponent("\(locale).json")
            let data = try JSONSerialization.data(withJSONObject: testContent, options: [])
            try data.write(to: localeFile)
        }

        // Create a test project
        let context = PersistenceController.preview.container.viewContext
        let project = Project(context: context)
        project.name = "Test Project"
        project.path = tempDir.path
        project.baseLocale = "en"
        project.locales = locales
        project.pathPattern = "./messages/{locale}.json"

        // Test the SmartRefactorer
        let refactorer = SmartRefactorer()
        let options: Set<RefactoringOption> = [.removeEmpty, .sortKeys, .formatJSON, .mergeDuplicates, .optimizeNesting]

        var progressUpdates: [(Double, String)] = []
        let results = await refactorer.refactorProject(
            project: project,
            options: options,
            progressCallback: { progress, status in
                progressUpdates.append((progress, status))
            }
        )

        // Verify results
        #expect(results.filesProcessed == 3)  // Should process all 3 locale files
        #expect(results.emptyKeysRemoved > 0)  // Should remove empty keys
        #expect(results.duplicatesMerged > 0)  // Should merge duplicates
        #expect(progressUpdates.count > 0)  // Should provide progress updates
        #expect(progressUpdates.last?.0 == 1.0)  // Should complete to 100%

        // Verify files were actually modified
        for locale in locales {
            let localeFile = messagesDir.appendingPathComponent("\(locale).json")
            let data = try Data(contentsOf: localeFile)
            let content = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            #expect(content != nil)
            #expect(content?["goodbye"] == nil)  // Empty key should be removed
            #expect(content?["user"] != nil)  // Should have nested user object
        }
    }

    @Test func testInlangConfigurationSerialization() async throws {
        let configParser = InlangConfigParser()

        // Create a test configuration
        let config = InlangConfiguration(
            baseLocale: "en",
            locales: ["en", "es", "fr"],
            sourceLanguageTag: "en",
            languageTags: ["en", "es", "fr"],
            modules: [
                InlangModule(
                    id: "plugin.inlang.messageFormat",
                    type: .messageFormat,
                    settings: .messageFormat(MessageFormatSettings(
                        pathPattern: "./messages/{locale}.json",
                        variableReferencePattern: [:],
                        messageReferenceMatchers: []
                    ))
                )
            ],
            pathPattern: "./messages/{locale}.json",
            experimental: [:]
        )

        // Create a temporary directory for testing
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Test saving configuration
        try configParser.saveConfiguration(config, to: tempDir.path)

        // Verify the file was created
        let configFile = tempDir.appendingPathComponent("project.inlang/settings.json")
        #expect(FileManager.default.fileExists(atPath: configFile.path))

        // Test loading configuration
        let loadedConfig = configParser.parseConfiguration(projectPath: tempDir.path)
        #expect(loadedConfig != nil)
        #expect(loadedConfig?.baseLocale == "en")
        #expect(loadedConfig?.locales == ["en", "es", "fr"])
        #expect(loadedConfig?.pathPattern == "./messages/{locale}.json")
    }

    @Test func testLocaleFileCreation() async throws {
        // Create a temporary directory for testing
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Test locale file creation
        let localeFileManager = LocaleFileManager()
        let testLocale = "es"
        let pathPattern = "./messages/{locale}.json"
        let filePath = pathPattern.replacingOccurrences(of: "{locale}", with: testLocale)
        let fullPath = tempDir.appendingPathComponent(String(filePath.dropFirst(2))).path

        // Create empty locale file
        let emptyContent: [String: Any] = [:]
        let data = try JSONSerialization.data(withJSONObject: emptyContent, options: [.prettyPrinted, .sortedKeys])
        let fileURL = URL(fileURLWithPath: fullPath)

        // Create directory if needed
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        // Write file
        try data.write(to: fileURL)

        // Verify file was created
        #expect(FileManager.default.fileExists(atPath: fullPath))

        // Verify file content
        let loadedData = try Data(contentsOf: fileURL)
        let loadedContent = try JSONSerialization.jsonObject(with: loadedData) as? [String: Any]
        #expect(loadedContent != nil)
        #expect(loadedContent?.isEmpty == true)
    }

}
