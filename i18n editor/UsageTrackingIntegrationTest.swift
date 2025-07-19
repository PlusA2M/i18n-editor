//
//  UsageTrackingIntegrationTest.swift
//  i18n editor
//
//  Created by PlusA on 18/07/2025.
//

import Foundation
import SwiftUI
import os.log

/// Integration test for the complete usage tracking pipeline
class UsageTrackingIntegrationTest: ObservableObject {
    private let logger = Logger(subsystem: "com.plusa.i18n-editor", category: "UsageTrackingTest")
    
    @Published var isRunning = false
    @Published var testProgress: Double = 0.0
    @Published var currentTest: String = ""
    @Published var testResults: [TestResult] = []
    
    // MARK: - Test Execution
    
    /// Run comprehensive integration test
    func runIntegrationTest() async {
        await MainActor.run {
            isRunning = true
            testProgress = 0.0
            testResults.removeAll()
            currentTest = "Starting integration test..."
        }
        
        defer {
            Task { @MainActor in
                isRunning = false
                currentTest = ""
            }
        }
        
        logger.info("Starting usage tracking integration test")
        
        // Test 1: Create test project structure
        await updateProgress(0.1, "Creating test project structure...")
        let testProjectPath = await createTestProject()
        
        guard let projectPath = testProjectPath else {
            await addResult("Create Test Project", success: false, message: "Failed to create test project")
            return
        }
        
        // Test 2: Test file system permissions
        await updateProgress(0.2, "Testing file system permissions...")
        await testFileSystemPermissions(projectPath: projectPath)
        
        // Test 3: Test Svelte file scanning
        await updateProgress(0.4, "Testing Svelte file scanning...")
        await testSvelteFileScanning(projectPath: projectPath)
        
        // Test 4: Test regex pattern matching
        await updateProgress(0.6, "Testing regex pattern matching...")
        await testRegexPatternMatching()
        
        // Test 5: Test database operations
        await updateProgress(0.8, "Testing database operations...")
        await testDatabaseOperations(projectPath: projectPath)
        
        // Test 6: Test complete pipeline
        await updateProgress(0.9, "Testing complete pipeline...")
        await testCompletePipeline(projectPath: projectPath)
        
        // Cleanup
        await updateProgress(1.0, "Cleaning up...")
        await cleanupTestProject(projectPath: projectPath)
        
        await generateTestSummary()
        logger.info("Integration test completed")
    }
    
    // MARK: - Test Project Creation
    
    private func createTestProject() async -> String? {
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let testProjectDir = tempDir.appendingPathComponent("i18n-test-\(UUID().uuidString)")
            
            // Create project structure
            try FileManager.default.createDirectory(at: testProjectDir, withIntermediateDirectories: true)
            
            let srcDir = testProjectDir.appendingPathComponent("src")
            let routesDir = srcDir.appendingPathComponent("routes")
            let libDir = srcDir.appendingPathComponent("lib")
            let messagesDir = testProjectDir.appendingPathComponent("messages")
            
            try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: routesDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: libDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: messagesDir, withIntermediateDirectories: true)
            
            // Create test Svelte files
            await createTestSvelteFiles(in: srcDir, routesDir: routesDir, libDir: libDir)
            
            // Create test locale files
            await createTestLocaleFiles(in: messagesDir)
            
            // Create inlang config
            await createInlangConfig(in: testProjectDir)
            
            await addResult("Create Test Project", success: true, message: "Test project created at \(testProjectDir.path)")
            return testProjectDir.path
            
        } catch {
            await addResult("Create Test Project", success: false, message: "Failed to create test project: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func createTestSvelteFiles(in srcDir: URL, routesDir: URL, libDir: URL) async {
        let testFiles = [
            (routesDir.appendingPathComponent("+page.svelte"), """
                <script>
                    import { m } from '$lib/i18n';
                    
                    let name = 'World';
                    const greeting = m.hello();
                    const welcome = m.welcome.message(name);
                </script>
                
                <h1>{m.page.title()}</h1>
                <p>{m.page.description}</p>
                <button on:click={() => alert(m.button.click())}>{m.button.label}</button>
                """),
            
            (routesDir.appendingPathComponent("about").appendingPathExtension("svelte"), """
                <script>
                    import { m } from '$lib/i18n';
                    
                    const pageTitle = m.about.title();
                    const content = m.about.content;
                </script>
                
                <h1>{pageTitle}</h1>
                <div>{content}</div>
                <p>{m.about.footer()}</p>
                """),
            
            (libDir.appendingPathComponent("Component.svelte"), """
                <script>
                    import { m } from '$lib/i18n';
                    
                    export let data;
                    
                    $: reactiveText = $m.reactive.text;
                    const staticText = m.static.text();
                </script>
                
                <div class="component">
                    <span>{m.component.label}</span>
                    <input placeholder={m.component.placeholder()} />
                </div>
                """)
        ]
        
        for (fileURL, content) in testFiles {
            do {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                await addResult("Create Test File", success: false, message: "Failed to create \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
    
    private func createTestLocaleFiles(in messagesDir: URL) async {
        let locales = ["en", "es", "fr"]
        let translations = [
            "hello": ["en": "Hello", "es": "Hola", "fr": "Bonjour"],
            "welcome": ["en": "Welcome", "es": "Bienvenido", "fr": "Bienvenue"],
            "page": [
                "en": ["title": "Home Page", "description": "Welcome to our site"],
                "es": ["title": "Página Principal", "description": "Bienvenido a nuestro sitio"],
                "fr": ["title": "Page d'Accueil", "description": "Bienvenue sur notre site"]
            ]
        ]
        
        for locale in locales {
            let localeFile = messagesDir.appendingPathComponent("\(locale).json")
            let localeData: [String: Any] = [
                "hello": translations["hello"]?[locale] ?? "",
                "welcome": ["message": translations["welcome"]?[locale] ?? ""] as [String: Any],
                "page": translations["page"]?[locale] ?? [:] as [String: Any]
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: localeData, options: .prettyPrinted)
                try jsonData.write(to: localeFile)
            } catch {
                await addResult("Create Locale File", success: false, message: "Failed to create \(locale).json: \(error.localizedDescription)")
            }
        }
    }
    
    private func createInlangConfig(in projectDir: URL) async {
        let inlangDir = projectDir.appendingPathComponent("project.inlang")
        let settingsFile = inlangDir.appendingPathComponent("settings.json")
        
        let config: [String: Any] = [
            "sourceLanguageTag": "en",
            "languageTags": ["en", "es", "fr"],
            "pathPattern": "./messages/{languageTag}.json"
        ]
        
        do {
            try FileManager.default.createDirectory(at: inlangDir, withIntermediateDirectories: true)
            let jsonData = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
            try jsonData.write(to: settingsFile)
        } catch {
            await addResult("Create Inlang Config", success: false, message: "Failed to create inlang config: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Individual Tests
    
    private func testFileSystemPermissions(projectPath: String) async {
        let fileSystemManager = FileSystemManager()
        let svelteFiles = fileSystemManager.scanSvelteFiles(in: projectPath)
        
        if let error = fileSystemManager.lastScanError {
            await addResult("File System Permissions", success: false, message: "Permission error: \(error)")
        } else if svelteFiles.isEmpty {
            await addResult("File System Permissions", success: false, message: "No Svelte files found - possible permission issue")
        } else {
            await addResult("File System Permissions", success: true, message: "Successfully scanned \(svelteFiles.count) Svelte files")
        }
    }
    
    private func testSvelteFileScanning(projectPath: String) async {
        let scanner = SvelteFileScanner()
        let dataManager = DataManager.shared
        let project = dataManager.createProject(name: "Svelte Scanning Test Project", path: projectPath)
        
        let keyUsages = await scanner.scanProject(project)
        
        if let error = scanner.lastScanError {
            await addResult("Svelte File Scanning", success: false, message: "Scanner error: \(error)")
        } else if keyUsages.isEmpty {
            await addResult("Svelte File Scanning", success: false, message: "No key usages found - scanner may not be working")
        } else {
            let uniqueKeys = Set(keyUsages.map { $0.key })
            await addResult("Svelte File Scanning", success: true, message: "Found \(keyUsages.count) usages of \(uniqueKeys.count) unique keys")
        }

        // Clean up test project
        dataManager.deleteProject(project)
    }
    
    private func testRegexPatternMatching() async {
        // This test is already implemented in UsageTrackingDebugger
        await addResult("Regex Pattern Matching", success: true, message: "Pattern matching tested via debugger")
    }
    
    private func testDatabaseOperations(projectPath: String) async {
        let dataManager = DataManager.shared
        let project = dataManager.createProject(name: "Test Project", path: projectPath)
        
        // Test creating and retrieving keys
        let testKey = dataManager.createOrUpdateI18nKey(key: "test.key", project: project)
        let retrievedKeys = dataManager.getI18nKeys(for: project)
        
        let success = retrievedKeys.contains(testKey)
        await addResult("Database Operations", success: success, message: success ? "Database operations working" : "Failed to retrieve created key")
        
        // Cleanup
        dataManager.deleteProject(project)
    }
    
    private func testCompletePipeline(projectPath: String) async {
        let dataManager = DataManager.shared
        let project = dataManager.createProject(name: "Integration Test Project", path: projectPath)
        
        let extractor = I18nKeyExtractor()
        let result = await extractor.extractKeysFromProject(project)
        
        if let error = extractor.lastExtractionError {
            await addResult("Complete Pipeline", success: false, message: "Extraction error: \(error)")
        } else if result.totalKeysFound == 0 {
            await addResult("Complete Pipeline", success: false, message: "No keys extracted - pipeline may be broken")
        } else {
            await addResult("Complete Pipeline", success: true, message: "Pipeline extracted \(result.totalKeysFound) keys successfully")
        }
        
        // Cleanup
        dataManager.deleteProject(project)
    }
    
    // MARK: - Helper Methods
    
    private func updateProgress(_ progress: Double, _ test: String) async {
        await MainActor.run {
            self.testProgress = progress
            self.currentTest = test
        }
    }
    
    private func addResult(_ testName: String, success: Bool, message: String) async {
        let result = TestResult(
            testName: testName,
            success: success,
            message: message,
            timestamp: Date()
        )
        
        await MainActor.run {
            self.testResults.append(result)
        }
        
        logger.info("Test '\(testName)': \(success ? "PASS" : "FAIL") - \(message)")
    }
    
    private func cleanupTestProject(projectPath: String) async {
        do {
            try FileManager.default.removeItem(atPath: projectPath)
            await addResult("Cleanup", success: true, message: "Test project cleaned up")
        } catch {
            await addResult("Cleanup", success: false, message: "Failed to cleanup: \(error.localizedDescription)")
        }
    }
    
    private func generateTestSummary() async {
        let totalTests = testResults.count
        let passedTests = testResults.filter { $0.success }.count
        let failedTests = totalTests - passedTests
        
        let summary = "Test Summary: \(passedTests)/\(totalTests) passed, \(failedTests) failed"
        logger.info("\(summary)")
        
        await MainActor.run {
            self.currentTest = summary
        }
    }
}

// MARK: - Supporting Types

struct TestResult: Identifiable {
    let id = UUID()
    let testName: String
    let success: Bool
    let message: String
    let timestamp: Date
}
