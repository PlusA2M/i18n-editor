//
//  FileSystemManager.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import Foundation
import Combine
import os.log

/// Manages file system operations including directory scanning, file watching, and file operations
class FileSystemManager: ObservableObject {
    private let fileManager = FileManager.default
    private var fileSystemWatcher: FileSystemWatcher?
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.plusa.i18n-editor", category: "FileSystemManager")

    @Published var isScanning = false
    @Published var scanProgress: Double = 0.0
    @Published var lastScanDate: Date?
    @Published var lastScanError: String?

    // MARK: - Directory Scanning

    /// Recursively scan directory for Svelte files with permission handling
    func scanSvelteFiles(in projectPath: String) -> [SvelteFile] {
        logger.info("Starting Svelte file scan in project: \(projectPath)")
        let srcPath = URL(fileURLWithPath: projectPath).appendingPathComponent("src")

        // Clear previous error
        lastScanError = nil

        // Check if we can access the project directory
        guard canAccessPath(projectPath) else {
            let errorMessage = "Unable to access project directory. Please check permissions."
            lastScanError = errorMessage
            logger.error("Permission denied for project path: \(projectPath)")
            return []
        }

        logger.info("Project path access verified: \(projectPath)")

        guard fileManager.fileExists(atPath: srcPath.path) else {
            let errorMessage = "Source directory not found: \(srcPath.path)"
            lastScanError = errorMessage
            logger.error("Source directory not found: \(srcPath.path)")
            return []
        }

        logger.info("Source directory found: \(srcPath.path)")

        isScanning = true
        scanProgress = 0.0

        defer {
            isScanning = false
            lastScanDate = Date()
        }

        var svelteFiles: [SvelteFile] = []

        do {
            logger.info("Enumerating .svelte files...")
            let allFiles = try getAllFiles(in: srcPath, withExtension: "svelte")
            let totalFiles = allFiles.count

            logger.info("Found \(totalFiles) .svelte files to process")

            for (index, fileURL) in allFiles.enumerated() {
                logger.debug("Processing file \(index + 1)/\(totalFiles): \(fileURL.lastPathComponent)")

                if let svelteFile = processSvelteFile(at: fileURL, projectPath: projectPath) {
                    svelteFiles.append(svelteFile)
                    logger.debug("Successfully processed: \(svelteFile.relativePath) (\(svelteFile.fileSize) bytes)")
                } else {
                    logger.warning("Failed to process file: \(fileURL.path)")
                }

                // Update progress
                DispatchQueue.main.async {
                    self.scanProgress = Double(index + 1) / Double(totalFiles)
                }
            }

            logger.info("Scan completed: \(svelteFiles.count)/\(totalFiles) files processed successfully")

        } catch {
            let errorMessage = "Error scanning Svelte files: \(error.localizedDescription)"
            lastScanError = errorMessage
            logger.error("Error scanning Svelte files: \(error.localizedDescription)")
        }

        return svelteFiles
    }

    /// Get all files with specific extension recursively
    func getAllFiles(in directory: URL, withExtension ext: String) throws -> [URL] {
        var files: [URL] = []

        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        let directoryEnumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        while let fileURL = directoryEnumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))

            if resourceValues.isRegularFile == true && fileURL.pathExtension == ext {
                files.append(fileURL)
            }
        }

        return files
    }

    /// Process a single Svelte file
    private func processSvelteFile(at url: URL, projectPath: String) -> SvelteFile? {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let relativePath = getRelativePath(for: url.path, projectPath: projectPath)

            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let modificationDate = attributes[.modificationDate] as? Date ?? Date()
            let fileSize = attributes[.size] as? Int64 ?? 0

            return SvelteFile(
                path: url.path,
                relativePath: relativePath,
                content: content,
                modificationDate: modificationDate,
                fileSize: fileSize
            )

        } catch {
            print("Error reading Svelte file \(url.path): \(error)")
            return nil
        }
    }

    /// Get relative path from project root
    private func getRelativePath(for filePath: String, projectPath: String) -> String {
        if filePath.hasPrefix(projectPath) {
            return String(filePath.dropFirst(projectPath.count + 1))
        }
        return filePath
    }

    // MARK: - Locale File Operations

    /// Get locale files based on path pattern
    func getLocaleFiles(for project: Project) -> [LocaleFile] {
        print("Getting locale files for project: \(project.name ?? "Unknown")")
        guard let projectPath = project.path,
              let pathPattern = project.pathPattern else {
            return []
        }

        let locales = project.allLocales
        var localeFiles: [LocaleFile] = []

        for locale in locales {
            let filePath = resolvePathPattern(pathPattern, locale: locale, projectPath: projectPath)
            let fileURL = URL(fileURLWithPath: filePath)

            var content: [String: Any] = [:]
            var exists = false
            var modificationDate = Date.distantPast

            print("Checking locale file: \(filePath)")

            if fileManager.fileExists(atPath: filePath) {
                exists = true
                print("Locale file exists: \(filePath)")
                do {
                    let data = try Data(contentsOf: fileURL)
                    content = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

                    let attributes = try fileManager.attributesOfItem(atPath: filePath)
                    modificationDate = attributes[.modificationDate] as? Date ?? Date()
                    print("Locale file loaded: \(filePath)")
                } catch {
                    print("Error reading locale file \(filePath): \(error)")
                }
            }

            let localeFile = LocaleFile(
                locale: locale,
                path: filePath,
                relativePath: getRelativePath(for: filePath, projectPath: projectPath),
                content: content,
                exists: exists,
                modificationDate: modificationDate
            )

            localeFiles.append(localeFile)
        }

        return localeFiles
    }

    /// Resolve path pattern with locale placeholder
    private func resolvePathPattern(_ pattern: String, locale: String, projectPath: String) -> String {
        let projectURL = URL(fileURLWithPath: projectPath)
        let resolvedPattern = pattern.replacingOccurrences(of: "{locale}", with: locale)

        // Handle relative paths
        if resolvedPattern.hasPrefix("./") {
            let relativePath = String(resolvedPattern.dropFirst(2))
            return projectURL.appendingPathComponent(relativePath).path
        } else if resolvedPattern.hasPrefix("/") {
            return resolvedPattern
        } else {
            return projectURL.appendingPathComponent(resolvedPattern).path
        }
    }

    /// Save locale file content
    func saveLocaleFile(_ localeFile: LocaleFile, content: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: content, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])

        // Create directory if it doesn't exist
        let fileURL = URL(fileURLWithPath: localeFile.path)
        let directoryURL = fileURL.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        try data.write(to: fileURL)
    }

    /// Create backup of locale file
    func createBackup(for localeFile: LocaleFile) throws -> String {
        let fileURL = URL(fileURLWithPath: localeFile.path)
        let backupURL = fileURL.appendingPathExtension("backup.\(Int(Date().timeIntervalSince1970))")

        if fileManager.fileExists(atPath: localeFile.path) {
            try fileManager.copyItem(at: fileURL, to: backupURL)
        }

        return backupURL.path
    }

    // MARK: - File Watching

    /// Start watching project directory for changes
    func startWatching(projectPath: String, onChange: @escaping (FileSystemEvent) -> Void) {
        stopWatching()

        fileSystemWatcher = FileSystemWatcher(path: projectPath)
        fileSystemWatcher?.onEvent = onChange
        fileSystemWatcher?.startWatching()
    }

    /// Stop watching file system changes
    func stopWatching() {
        fileSystemWatcher?.stopWatching()
        fileSystemWatcher = nil
    }

    // MARK: - Utility Methods

    /// Check if file exists
    func fileExists(at path: String) -> Bool {
        return fileManager.fileExists(atPath: path)
    }

    /// Get file modification date
    func getModificationDate(for path: String) -> Date? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            return attributes[.modificationDate] as? Date
        } catch {
            return nil
        }
    }

    /// Get file size
    func getFileSize(for path: String) -> Int64? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }

    /// Create directory if it doesn't exist
    func createDirectoryIfNeeded(at path: String) throws {
        if !fileManager.fileExists(atPath: path) {
            try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
    }

    // MARK: - Permission Checking

    /// Check if we can access a specific path using security-scoped bookmarks or Full Disk Access
    private func canAccessPath(_ path: String) -> Bool {
        logger.debug("Checking access to path: \(path)")

        // Try to restore security-scoped access from bookmark
        let bookmarkKey = "bookmark_\(path)"
        if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
            logger.debug("Found security-scoped bookmark for path")
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

                if !isStale && url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    let hasAccess = fileManager.isReadableFile(atPath: path)
                    logger.debug("Security-scoped bookmark access: \(hasAccess ? "granted" : "denied")")
                    return hasAccess
                } else {
                    logger.warning("Security-scoped bookmark is stale or failed to start accessing")
                }
            } catch {
                logger.error("Failed to resolve security-scoped bookmark: \(error.localizedDescription)")
            }
        } else {
            logger.debug("No security-scoped bookmark found for path")
        }

        // Fall back to checking direct access (works with Full Disk Access)
        let hasDirectAccess = fileManager.isReadableFile(atPath: path)
        logger.debug("Direct file access: \(hasDirectAccess ? "granted" : "denied")")
        return hasDirectAccess
    }
}

// MARK: - Supporting Types

struct SvelteFile {
    let path: String
    let relativePath: String
    let content: String
    let modificationDate: Date
    let fileSize: Int64
}

struct LocaleFile {
    let locale: String
    let path: String
    let relativePath: String
    let content: [String: Any]
    let exists: Bool
    let modificationDate: Date
}

enum FileSystemEvent {
    case fileCreated(path: String)
    case fileModified(path: String)
    case fileDeleted(path: String)
    case directoryCreated(path: String)
    case directoryDeleted(path: String)
}

// MARK: - File System Watcher

class FileSystemWatcher {
    private let path: String
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?

    var onEvent: ((FileSystemEvent) -> Void)?

    init(path: String) {
        self.path = path
    }

    func startWatching() {
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("Failed to open file descriptor for path: \(path)")
            return
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global(qos: .background)
        )

        source?.setEventHandler { [weak self] in
            self?.handleFileSystemEvent()
        }

        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }

        source?.resume()
    }

    func stopWatching() {
        source?.cancel()
        source = nil
    }

    private func handleFileSystemEvent() {
        // Simple implementation - in a real app, you'd want more sophisticated event handling
        onEvent?(.fileModified(path: path))
    }

    deinit {
        stopWatching()
    }
}
