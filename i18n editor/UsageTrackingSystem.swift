//
//  UsageTrackingSystem.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import Foundation
import Combine
import CoreData
import os.log

/// Real-time usage tracking system for i18n keys across the codebase
class UsageTrackingSystem: ObservableObject {
    private let dataManager = DataManager.shared
    private let fileSystemManager = FileSystemManager()
    private let keyExtractor = I18nKeyExtractor()
    private let logger = Logger(subsystem: "com.plusa.i18n-editor", category: "UsageTrackingSystem")

    @Published var isTracking = false
    @Published var trackedProject: Project?
    @Published var usageStatistics: UsageStatistics?
    @Published var recentChanges: [UsageChange] = []
    @Published var lastUpdateTime: Date?
    @Published var trackingError: String?

    private var fileWatchingCancellable: AnyCancellable?
    private var updateQueue = DispatchQueue(label: "usage-tracking", qos: .background)
    private var pendingUpdates: Set<String> = []
    private var updateTimer: Timer?

    // MARK: - Tracking Control

    /// Start tracking usage for a project
    func startTracking(project: Project) {
        guard let projectPath = project.path else {
            logger.error("Cannot start tracking: project path is nil")
            trackingError = "Project path is nil"
            return
        }

        logger.info("Starting usage tracking for project: \(project.name ?? "Unknown") at path: \(projectPath)")

        stopTracking()

        trackedProject = project
        isTracking = true
        trackingError = nil

        // Initial extraction and statistics calculation
        logger.info("Performing initial key extraction...")
        Task {
            let result = await keyExtractor.extractKeysFromProject(project)
            logger.info("Initial extraction completed: \(result.totalKeysFound) keys found")

            await MainActor.run {
                calculateUsageStatistics()
            }
        }

        // Start file system watching
        logger.info("Starting file system watching...")
        fileSystemManager.startWatching(projectPath: projectPath) { [weak self] event in
            self?.handleFileSystemEvent(event)
        }

        // Set up periodic updates
        setupPeriodicUpdates()

        logger.info("Usage tracking started successfully for project: \(project.name ?? "Unknown")")
    }

    /// Stop tracking usage
    func stopTracking() {
        isTracking = false
        trackedProject = nil

        fileSystemManager.stopWatching()
        fileWatchingCancellable?.cancel()
        updateTimer?.invalidate()
        updateTimer = nil

        pendingUpdates.removeAll()

        print("Stopped usage tracking")
    }

    /// Force refresh of usage statistics
    func refreshUsageStatistics() {
        calculateUsageStatistics()
    }

    /// Force full rescan of the project
    func forceFullRescan() async {
        guard let project = trackedProject else {
            logger.warning("Cannot rescan: no tracked project")
            return
        }

        logger.info("Starting forced full rescan...")
        let result = await keyExtractor.extractKeysFromProject(project)
        logger.info("Full rescan completed: \(result.totalKeysFound) keys found")

        await MainActor.run {
            calculateUsageStatistics()
        }
    }

    // MARK: - File System Event Handling

    private func handleFileSystemEvent(_ event: FileSystemEvent) {
        updateQueue.async { [weak self] in
            self?.processFileSystemEvent(event)
        }
    }

    private func processFileSystemEvent(_ event: FileSystemEvent) {
        switch event {
        case .fileModified(let path), .fileCreated(let path):
            if path.hasSuffix(".svelte") {
                addPendingUpdate(path)
            } else if path.contains("messages/") && path.hasSuffix(".json") {
                // Locale file changed - trigger full refresh
                DispatchQueue.main.async {
                    self.refreshUsageStatistics()
                }
            }

        case .fileDeleted(let path):
            if path.hasSuffix(".svelte") {
                handleFileDeleted(path)
            }

        case .directoryCreated(_), .directoryDeleted(_):
            // Handle directory changes if needed
            break
        }
    }

    private func addPendingUpdate(_ filePath: String) {
        pendingUpdates.insert(filePath)

        // Debounce updates - process after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.processPendingUpdates()
        }
    }

    private func processPendingUpdates() {
        guard !pendingUpdates.isEmpty, let project = trackedProject else { return }

        let filesToUpdate = Array(pendingUpdates)
        pendingUpdates.removeAll()

        Task {
            await processFileUpdates(filesToUpdate, project: project)
        }
    }

    private func processFileUpdates(_ filePaths: [String], project: Project) async {
        let result = await keyExtractor.extractKeysFromFiles(filePaths, project: project)

        await MainActor.run {
            // Record the changes
            let change = UsageChange(
                type: .filesUpdated,
                affectedFiles: filePaths,
                keysAffected: result.totalKeysFound,
                timestamp: Date()
            )

            recentChanges.insert(change, at: 0)

            // Keep only recent changes (last 50)
            if recentChanges.count > 50 {
                recentChanges = Array(recentChanges.prefix(50))
            }

            lastUpdateTime = Date()

            // Refresh statistics
            calculateUsageStatistics()
        }
    }

    private func handleFileDeleted(_ filePath: String) {
        guard let project = trackedProject else { return }

        // Mark all usages in this file as inactive
        dataManager.markFileUsagesInactive(for: project, filePath: filePath)

        DispatchQueue.main.async {
            let change = UsageChange(
                type: .fileDeleted,
                affectedFiles: [filePath],
                keysAffected: 0,
                timestamp: Date()
            )

            self.recentChanges.insert(change, at: 0)
            self.calculateUsageStatistics()
        }
    }

    // MARK: - Statistics Calculation

    private func calculateUsageStatistics() {
        guard let project = trackedProject else {
            logger.warning("Cannot calculate statistics: no tracked project")
            return
        }

        logger.info("Calculating usage statistics for project: \(project.name ?? "Unknown")")

        // Perform statistics calculation on background queue for better performance
        Task.detached { [weak self] in
            guard let self = self else { return }

            let i18nKeys = await MainActor.run {
                self.dataManager.getI18nKeys(for: project)
            }

            let allTranslations = await MainActor.run {
                project.translations?.allObjects as? [Translation] ?? []
            }

            let allFileUsages = await MainActor.run {
                project.fileUsages?.allObjects as? [FileUsage] ?? []
            }

            self.logger.debug("Found \(i18nKeys.count) i18n keys, \(allFileUsages.count) file usages, \(allTranslations.count) translations")

            // Calculate key usage statistics
            var keyUsageStats: [KeyUsageInfo] = []
            var fileUsageStats: [FileUsageInfo] = []

            for key in i18nKeys {
                let activeUsages = key.activeFileUsages
                let translations = key.allTranslations

                let usageInfo = KeyUsageInfo(
                    key: key.key ?? "",
                    usageCount: activeUsages.count,
                    fileCount: Set(activeUsages.map { $0.filePath ?? "" }).count,
                    translationCount: translations.count,
                    completionPercentage: key.completionPercentage,
                    lastUsed: activeUsages.map { $0.detectedAt ?? Date.distantPast }.max() ?? Date.distantPast,
                    isNested: key.isNested,
                    namespace: key.namespace
                )

                keyUsageStats.append(usageInfo)
            }

            // Calculate file usage statistics
            let fileGroups = Dictionary(grouping: allFileUsages.filter { $0.isActive }) { $0.filePath ?? "" }

            for (filePath, usages) in fileGroups {
                let uniqueKeys = Set(usages.compactMap { $0.i18nKey?.key })

                let fileInfo = FileUsageInfo(
                    filePath: filePath,
                    relativePath: self.getRelativePath(filePath, project: project),
                    keyCount: uniqueKeys.count,
                    usageCount: usages.count,
                    lastModified: usages.compactMap { $0.detectedAt }.max() ?? Date.distantPast
                )

                fileUsageStats.append(fileInfo)
            }

            // Calculate overall statistics
            let totalKeys = keyUsageStats.count
            let totalUsages = keyUsageStats.reduce(0) { $0 + $1.usageCount }
            let totalFiles = fileUsageStats.count
            let keysWithUsage = keyUsageStats.filter { $0.usageCount > 0 }.count
            let keysWithoutUsage = totalKeys - keysWithUsage
            let averageUsagePerKey = totalKeys > 0 ? Double(totalUsages) / Double(totalKeys) : 0.0

            // Translation completion statistics
            let totalTranslations = allTranslations.count
            let completedTranslations = allTranslations.filter { !($0.value?.isEmpty ?? true) }.count
            let draftTranslations = allTranslations.filter { $0.isDraft }.count
            let translationCompletionRate = totalTranslations > 0 ? Double(completedTranslations) / Double(totalTranslations) : 0.0

            // Most and least used keys
            let sortedByUsage = keyUsageStats.sorted { $0.usageCount > $1.usageCount }
            let mostUsedKeys = Array(sortedByUsage.prefix(10))
            let leastUsedKeys = Array(sortedByUsage.suffix(10).reversed())

            // Files with most keys
            let sortedFilesByKeys = fileUsageStats.sorted { $0.keyCount > $1.keyCount }
            let filesWithMostKeys = Array(sortedFilesByKeys.prefix(10))

            let statistics = UsageStatistics(
                totalKeys: totalKeys,
                totalUsages: totalUsages,
                totalFiles: totalFiles,
                keysWithUsage: keysWithUsage,
                keysWithoutUsage: keysWithoutUsage,
                averageUsagePerKey: averageUsagePerKey,
                totalTranslations: totalTranslations,
                completedTranslations: completedTranslations,
                draftTranslations: draftTranslations,
                translationCompletionRate: translationCompletionRate,
                keyUsageStats: keyUsageStats,
                fileUsageStats: fileUsageStats,
                mostUsedKeys: mostUsedKeys,
                leastUsedKeys: leastUsedKeys,
                filesWithMostKeys: filesWithMostKeys,
                lastCalculated: Date()
            )

            await MainActor.run {
                self.usageStatistics = statistics
            }
        }
    }

    private func getRelativePath(_ filePath: String, project: Project) -> String {
        guard let projectPath = project.path else { return filePath }

        if filePath.hasPrefix(projectPath) {
            return String(filePath.dropFirst(projectPath.count + 1))
        }
        return filePath
    }

    // MARK: - Periodic Updates

    private func setupPeriodicUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            // Refresh statistics every 5 minutes
            self?.calculateUsageStatistics()
        }
    }

    // MARK: - Query Methods

    /// Get usage information for a specific key
    func getUsageInfo(for key: String) -> KeyUsageInfo? {
        return usageStatistics?.keyUsageStats.first { $0.key == key }
    }

    /// Get files that use a specific key
    func getFilesUsingKey(_ key: String) -> [FileUsageInfo] {
        guard let project = trackedProject else { return [] }

        let i18nKey = dataManager.getI18nKey(key: key, project: project)
        let activeUsages = i18nKey?.activeFileUsages ?? []

        let filePaths = Set(activeUsages.map { $0.filePath ?? "" })

        return usageStatistics?.fileUsageStats.filter { filePaths.contains($0.filePath) } ?? []
    }

    /// Get keys used in a specific file
    func getKeysInFile(_ filePath: String) -> [KeyUsageInfo] {
        guard let project = trackedProject else { return [] }

        let request: NSFetchRequest<FileUsage> = FileUsage.fetchRequest()
        request.predicate = NSPredicate(format: "project == %@ AND filePath == %@ AND isActive == YES", project, filePath)

        do {
            let usages = try dataManager.viewContext.fetch(request)
            let keys = Set(usages.compactMap { $0.i18nKey?.key })

            return usageStatistics?.keyUsageStats.filter { keys.contains($0.key) } ?? []
        } catch {
            print("Error fetching keys for file: \(error)")
            return []
        }
    }

    /// Search keys by pattern
    func searchKeys(pattern: String) -> [KeyUsageInfo] {
        let lowercasePattern = pattern.lowercased()

        return usageStatistics?.keyUsageStats.filter { keyInfo in
            keyInfo.key.lowercased().contains(lowercasePattern) ||
            keyInfo.namespace?.lowercased().contains(lowercasePattern) == true
        } ?? []
    }

    /// Get unused keys
    func getUnusedKeys() -> [KeyUsageInfo] {
        return usageStatistics?.keyUsageStats.filter { $0.usageCount == 0 } ?? []
    }

    /// Get keys missing translations
    func getKeysWithMissingTranslations() -> [KeyUsageInfo] {
        return usageStatistics?.keyUsageStats.filter { $0.completionPercentage < 1.0 } ?? []
    }
}

// MARK: - Supporting Types

struct UsageStatistics {
    let totalKeys: Int
    let totalUsages: Int
    let totalFiles: Int
    let keysWithUsage: Int
    let keysWithoutUsage: Int
    let averageUsagePerKey: Double
    let totalTranslations: Int
    let completedTranslations: Int
    let draftTranslations: Int
    let translationCompletionRate: Double
    let keyUsageStats: [KeyUsageInfo]
    let fileUsageStats: [FileUsageInfo]
    let mostUsedKeys: [KeyUsageInfo]
    let leastUsedKeys: [KeyUsageInfo]
    let filesWithMostKeys: [FileUsageInfo]
    let lastCalculated: Date
}

struct KeyUsageInfo: Identifiable {
    let id = UUID()
    let key: String
    let usageCount: Int
    let fileCount: Int
    let translationCount: Int
    let completionPercentage: Double
    let lastUsed: Date
    let isNested: Bool
    let namespace: String?
}

struct FileUsageInfo: Identifiable {
    let id = UUID()
    let filePath: String
    let relativePath: String
    let keyCount: Int
    let usageCount: Int
    let lastModified: Date
}

struct UsageChange: Identifiable {
    let id = UUID()
    let type: UsageChangeType
    let affectedFiles: [String]
    let keysAffected: Int
    let timestamp: Date
}

enum UsageChangeType {
    case filesUpdated
    case fileDeleted
    case keyAdded
    case keyRemoved
    case translationUpdated
}
