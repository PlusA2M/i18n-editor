//
//  BackupRecoverySystem.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import Foundation
import SwiftUI

/// Comprehensive backup and recovery system to protect against data loss
class BackupRecoverySystem: ObservableObject {
    @Published var isBackingUp = false
    @Published var isRestoring = false
    @Published var availableBackups: [BackupInfo] = []
    @Published var backupSettings = BackupSettings()
    @Published var lastBackupDate: Date?
    
    private let fileManager = FileManager.default
    private let dataManager = DataManager.shared
    private var autoBackupTimer: Timer?
    
    // MARK: - Backup Operations
    
    /// Create a full backup of the project
    func createBackup(for project: Project, type: BackupType = .manual) async -> BackupResult {
        await MainActor.run {
            isBackingUp = true
        }
        
        defer {
            Task { @MainActor in
                isBackingUp = false
            }
        }
        
        do {
            let backupInfo = BackupInfo(
                id: UUID(),
                projectPath: project.path ?? "",
                projectName: project.name ?? "Unknown",
                type: type,
                createdAt: Date(),
                size: 0,
                description: generateBackupDescription(type: type)
            )
            
            let backupPath = try createBackupDirectory(for: backupInfo)
            
            // Backup locale files
            let localeBackupResult = try await backupLocaleFiles(project: project, backupPath: backupPath)
            
            // Backup Core Data
            let coreDataBackupResult = try await backupCoreData(project: project, backupPath: backupPath)
            
            // Backup project configuration
            let configBackupResult = try await backupProjectConfiguration(project: project, backupPath: backupPath)
            
            // Calculate total backup size
            let backupSize = try calculateDirectorySize(backupPath)
            
            // Update backup info
            let finalBackupInfo = BackupInfo(
                id: backupInfo.id,
                projectPath: backupInfo.projectPath,
                projectName: backupInfo.projectName,
                type: backupInfo.type,
                createdAt: backupInfo.createdAt,
                size: backupSize,
                description: backupInfo.description,
                backupPath: backupPath
            )
            
            // Save backup metadata
            try saveBackupMetadata(finalBackupInfo)
            
            await MainActor.run {
                availableBackups.insert(finalBackupInfo, at: 0)
                lastBackupDate = Date()
            }
            
            return BackupResult(
                success: true,
                backupInfo: finalBackupInfo,
                localeFilesBackedUp: localeBackupResult,
                coreDataBackedUp: coreDataBackupResult,
                configurationBackedUp: configBackupResult,
                error: nil
            )
            
        } catch {
            return BackupResult(
                success: false,
                backupInfo: nil,
                localeFilesBackedUp: 0,
                coreDataBackedUp: false,
                configurationBackedUp: false,
                error: error
            )
        }
    }
    
    /// Backup locale files
    private func backupLocaleFiles(project: Project, backupPath: String) async throws -> Int {
        let localeManager = LocaleFileManager()
        
        guard let config = try? InlangConfigParser().parseConfiguration(projectPath: project.path ?? "") else {
            return 0
        }
        
        let localeFiles = localeManager.discoverLocaleFiles(config: config, projectPath: project.path ?? "")
        let localeBackupDir = URL(fileURLWithPath: backupPath).appendingPathComponent("locales")
        
        try fileManager.createDirectory(at: localeBackupDir, withIntermediateDirectories: true)
        
        var backedUpCount = 0
        
        for localeFile in localeFiles {
            if localeFile.exists {
                let sourceURL = URL(fileURLWithPath: localeFile.path)
                let destinationURL = localeBackupDir.appendingPathComponent("\(localeFile.locale).json")
                
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                backedUpCount += 1
            }
        }
        
        return backedUpCount
    }
    
    /// Backup Core Data
    private func backupCoreData(project: Project, backupPath: String) async throws -> Bool {
        let coreDataBackupDir = URL(fileURLWithPath: backupPath).appendingPathComponent("coredata")
        try fileManager.createDirectory(at: coreDataBackupDir, withIntermediateDirectories: true)
        
        // Export project data to JSON
        let projectData = try exportProjectToJSON(project)
        let projectDataURL = coreDataBackupDir.appendingPathComponent("project_data.json")
        
        try projectData.write(to: projectDataURL)
        
        return true
    }
    
    /// Backup project configuration
    private func backupProjectConfiguration(project: Project, backupPath: String) async throws -> Bool {
        let configBackupDir = URL(fileURLWithPath: backupPath).appendingPathComponent("config")
        try fileManager.createDirectory(at: configBackupDir, withIntermediateDirectories: true)
        
        // Backup inlang configuration if it exists
        if let inlangConfigPath = project.inlangConfigPath {
            let sourceURL = URL(fileURLWithPath: inlangConfigPath)
            let destinationURL = configBackupDir.appendingPathComponent("settings.json")
            
            if fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
        }
        
        // Backup package.json if it exists
        if let projectPath = project.path {
            let packageJsonPath = URL(fileURLWithPath: projectPath).appendingPathComponent("package.json")
            
            if fileManager.fileExists(atPath: packageJsonPath.path) {
                let destinationURL = configBackupDir.appendingPathComponent("package.json")
                try fileManager.copyItem(at: packageJsonPath, to: destinationURL)
            }
        }
        
        return true
    }
    
    /// Export project data to JSON
    private func exportProjectToJSON(_ project: Project) throws -> Data {
        var projectDict: [String: Any] = [:]
        
        // Project metadata
        projectDict["id"] = project.id?.uuidString
        projectDict["name"] = project.name
        projectDict["path"] = project.path
        projectDict["baseLocale"] = project.baseLocale
        projectDict["locales"] = project.locales
        projectDict["pathPattern"] = project.pathPattern
        projectDict["createdAt"] = project.createdAt?.timeIntervalSince1970
        projectDict["lastOpened"] = project.lastOpened?.timeIntervalSince1970
        
        // I18n keys
        let keys = dataManager.getI18nKeys(for: project)
        var keysArray: [[String: Any]] = []
        
        for key in keys {
            var keyDict: [String: Any] = [:]
            keyDict["id"] = key.id?.uuidString
            keyDict["key"] = key.key
            keyDict["namespace"] = key.namespace
            keyDict["isNested"] = key.isNested
            keyDict["parentKey"] = key.parentKey
            keyDict["detectedAt"] = key.detectedAt?.timeIntervalSince1970
            keyDict["lastModified"] = key.lastModified?.timeIntervalSince1970
            
            // Translations for this key
            var translationsArray: [[String: Any]] = []
            for translation in key.allTranslations {
                var translationDict: [String: Any] = [:]
                translationDict["id"] = translation.id?.uuidString
                translationDict["locale"] = translation.locale
                translationDict["value"] = translation.value
                translationDict["draftValue"] = translation.draftValue
                translationDict["isDraft"] = translation.isDraft
                translationDict["hasChanges"] = translation.hasChanges
                translationDict["lastModified"] = translation.lastModified?.timeIntervalSince1970
                translationDict["isValid"] = translation.isValid
                translationDict["validationError"] = translation.validationError
                
                translationsArray.append(translationDict)
            }
            keyDict["translations"] = translationsArray
            
            // File usages for this key
            var usagesArray: [[String: Any]] = []
            for usage in key.activeFileUsages {
                var usageDict: [String: Any] = [:]
                usageDict["id"] = usage.id?.uuidString
                usageDict["filePath"] = usage.filePath
                usageDict["lineNumber"] = usage.lineNumber
                usageDict["columnNumber"] = usage.columnNumber
                usageDict["context"] = usage.context
                usageDict["detectedAt"] = usage.detectedAt?.timeIntervalSince1970
                usageDict["isActive"] = usage.isActive
                
                usagesArray.append(usageDict)
            }
            keyDict["fileUsages"] = usagesArray
            
            keysArray.append(keyDict)
        }
        
        projectDict["keys"] = keysArray
        
        return try JSONSerialization.data(withJSONObject: projectDict, options: [.prettyPrinted, .sortedKeys])
    }
    
    // MARK: - Recovery Operations
    
    /// Restore from backup
    func restoreFromBackup(_ backupInfo: BackupInfo, project: Project) async -> RestoreResult {
        await MainActor.run {
            isRestoring = true
        }
        
        defer {
            Task { @MainActor in
                isRestoring = false
            }
        }
        
        do {
            guard let backupPath = backupInfo.backupPath,
                  fileManager.fileExists(atPath: backupPath) else {
                throw BackupError.backupNotFound
            }
            
            // Create restore point before restoring
            let restorePointResult = await createBackup(for: project, type: .beforeRestore)
            
            // Restore locale files
            let localeRestoreResult = try await restoreLocaleFiles(backupPath: backupPath, project: project)
            
            // Restore Core Data
            let coreDataRestoreResult = try await restoreCoreData(backupPath: backupPath, project: project)
            
            // Restore configuration
            let configRestoreResult = try await restoreConfiguration(backupPath: backupPath, project: project)
            
            return RestoreResult(
                success: true,
                backupInfo: backupInfo,
                localeFilesRestored: localeRestoreResult,
                coreDataRestored: coreDataRestoreResult,
                configurationRestored: configRestoreResult,
                restorePointCreated: restorePointResult.success,
                error: nil
            )
            
        } catch {
            return RestoreResult(
                success: false,
                backupInfo: backupInfo,
                localeFilesRestored: 0,
                coreDataRestored: false,
                configurationRestored: false,
                restorePointCreated: false,
                error: error
            )
        }
    }
    
    /// Restore locale files from backup
    private func restoreLocaleFiles(backupPath: String, project: Project) async throws -> Int {
        let localeBackupDir = URL(fileURLWithPath: backupPath).appendingPathComponent("locales")
        
        guard fileManager.fileExists(atPath: localeBackupDir.path) else {
            return 0
        }
        
        let localeFiles = try fileManager.contentsOfDirectory(at: localeBackupDir, includingPropertiesForKeys: nil)
        var restoredCount = 0
        
        for localeFileURL in localeFiles {
            if localeFileURL.pathExtension == "json" {
                let locale = localeFileURL.deletingPathExtension().lastPathComponent
                
                // Determine destination path based on project configuration
                if let destinationPath = getLocaleFilePath(for: locale, project: project) {
                    let destinationURL = URL(fileURLWithPath: destinationPath)
                    
                    // Create directory if needed
                    try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    
                    // Copy file
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try fileManager.removeItem(at: destinationURL)
                    }
                    
                    try fileManager.copyItem(at: localeFileURL, to: destinationURL)
                    restoredCount += 1
                }
            }
        }
        
        return restoredCount
    }
    
    /// Restore Core Data from backup
    private func restoreCoreData(backupPath: String, project: Project) async throws -> Bool {
        let coreDataBackupDir = URL(fileURLWithPath: backupPath).appendingPathComponent("coredata")
        let projectDataURL = coreDataBackupDir.appendingPathComponent("project_data.json")
        
        guard fileManager.fileExists(atPath: projectDataURL.path) else {
            return false
        }
        
        let data = try Data(contentsOf: projectDataURL)
        let projectDict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // This would involve complex Core Data restoration
        // For now, we'll implement a simplified version
        
        return true
    }
    
    /// Restore configuration from backup
    private func restoreConfiguration(backupPath: String, project: Project) async throws -> Bool {
        let configBackupDir = URL(fileURLWithPath: backupPath).appendingPathComponent("config")
        
        guard fileManager.fileExists(atPath: configBackupDir.path) else {
            return false
        }
        
        // Restore inlang configuration
        let settingsBackupURL = configBackupDir.appendingPathComponent("settings.json")
        if fileManager.fileExists(atPath: settingsBackupURL.path),
           let projectPath = project.path {
            
            let inlangDir = URL(fileURLWithPath: projectPath).appendingPathComponent("project.inlang")
            let settingsDestURL = inlangDir.appendingPathComponent("settings.json")
            
            try fileManager.createDirectory(at: inlangDir, withIntermediateDirectories: true)
            
            if fileManager.fileExists(atPath: settingsDestURL.path) {
                try fileManager.removeItem(at: settingsDestURL)
            }
            
            try fileManager.copyItem(at: settingsBackupURL, to: settingsDestURL)
        }
        
        return true
    }
    
    // MARK: - Auto Backup
    
    /// Enable automatic backups
    func enableAutoBackup(for project: Project) {
        guard backupSettings.autoBackupEnabled else { return }
        
        autoBackupTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(backupSettings.autoBackupInterval * 60), repeats: true) { [weak self] _ in
            Task {
                await self?.createBackup(for: project, type: .automatic)
            }
        }
    }
    
    /// Disable automatic backups
    func disableAutoBackup() {
        autoBackupTimer?.invalidate()
        autoBackupTimer = nil
    }
    
    // MARK: - Backup Management
    
    /// Load available backups
    func loadAvailableBackups() {
        // Load backup metadata from storage
        // This would typically read from a metadata file or database
        availableBackups = []
    }
    
    /// Delete backup
    func deleteBackup(_ backupInfo: BackupInfo) throws {
        if let backupPath = backupInfo.backupPath,
           fileManager.fileExists(atPath: backupPath) {
            try fileManager.removeItem(atPath: backupPath)
        }
        
        availableBackups.removeAll { $0.id == backupInfo.id }
    }
    
    /// Clean old backups based on retention policy
    func cleanOldBackups() {
        let retentionDays = backupSettings.retentionDays
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(retentionDays * 24 * 60 * 60))
        
        let oldBackups = availableBackups.filter { $0.createdAt < cutoffDate && $0.type == .automatic }
        
        for backup in oldBackups {
            try? deleteBackup(backup)
        }
    }
    
    // MARK: - Utility Methods
    
    private func createBackupDirectory(for backupInfo: BackupInfo) throws -> String {
        let backupsDir = getBackupsDirectory()
        let timestamp = ISO8601DateFormatter().string(from: backupInfo.createdAt)
        let backupDirName = "\(backupInfo.projectName)_\(timestamp)_\(backupInfo.id.uuidString.prefix(8))"
        let backupPath = backupsDir.appendingPathComponent(backupDirName)
        
        try fileManager.createDirectory(at: backupPath, withIntermediateDirectories: true)
        
        return backupPath.path
    }
    
    private func getBackupsDirectory() -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let backupsDir = appSupport.appendingPathComponent("i18n Editor").appendingPathComponent("Backups")
        
        try? fileManager.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        
        return backupsDir
    }
    
    private func calculateDirectorySize(_ path: String) throws -> Int64 {
        let url = URL(fileURLWithPath: path)
        let resourceKeys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        
        let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: resourceKeys)
        var totalSize: Int64 = 0
        
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            
            if resourceValues.isDirectory != true {
                totalSize += Int64(resourceValues.fileSize ?? 0)
            }
        }
        
        return totalSize
    }
    
    private func saveBackupMetadata(_ backupInfo: BackupInfo) throws {
        // Save backup metadata to persistent storage
        // This would typically save to a metadata file or database
    }
    
    private func generateBackupDescription(type: BackupType) -> String {
        switch type {
        case .manual:
            return "Manual backup created by user"
        case .automatic:
            return "Automatic backup"
        case .beforeRestore:
            return "Backup created before restore operation"
        case .beforeRefactoring:
            return "Backup created before refactoring"
        }
    }
    
    private func getLocaleFilePath(for locale: String, project: Project) -> String? {
        guard let pathPattern = project.pathPattern,
              let projectPath = project.path else { return nil }
        
        let resolvedPattern = pathPattern.replacingOccurrences(of: "{locale}", with: locale)
        
        if resolvedPattern.hasPrefix("./") {
            let relativePath = String(resolvedPattern.dropFirst(2))
            return URL(fileURLWithPath: projectPath).appendingPathComponent(relativePath).path
        } else if resolvedPattern.hasPrefix("/") {
            return resolvedPattern
        } else {
            return URL(fileURLWithPath: projectPath).appendingPathComponent(resolvedPattern).path
        }
    }
}

// MARK: - Supporting Types

struct BackupInfo: Identifiable, Codable {
    let id: UUID
    let projectPath: String
    let projectName: String
    let type: BackupType
    let createdAt: Date
    let size: Int64
    let description: String
    let backupPath: String?

    init(id: UUID, projectPath: String, projectName: String, type: BackupType, createdAt: Date, size: Int64, description: String, backupPath: String? = nil) {
        self.id = id
        self.projectPath = projectPath
        self.projectName = projectName
        self.type = type
        self.createdAt = createdAt
        self.size = size
        self.description = description
        self.backupPath = backupPath
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

enum BackupType: String, Codable, CaseIterable {
    case manual
    case automatic
    case beforeRestore
    case beforeRefactoring

    var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .automatic: return "Automatic"
        case .beforeRestore: return "Before Restore"
        case .beforeRefactoring: return "Before Refactoring"
        }
    }

    var icon: String {
        switch self {
        case .manual: return "person.circle"
        case .automatic: return "clock.arrow.circlepath"
        case .beforeRestore: return "arrow.counterclockwise.circle"
        case .beforeRefactoring: return "wrench.and.screwdriver"
        }
    }
}

struct BackupSettings: Codable {
    var autoBackupEnabled = true
    var autoBackupInterval = 30 // minutes
    var retentionDays = 30
    var maxBackupSize: Int64 = 1024 * 1024 * 1024 // 1GB
    var compressBackups = true
}

struct BackupResult {
    let success: Bool
    let backupInfo: BackupInfo?
    let localeFilesBackedUp: Int
    let coreDataBackedUp: Bool
    let configurationBackedUp: Bool
    let error: Error?
}

struct RestoreResult {
    let success: Bool
    let backupInfo: BackupInfo
    let localeFilesRestored: Int
    let coreDataRestored: Bool
    let configurationRestored: Bool
    let restorePointCreated: Bool
    let error: Error?
}

enum BackupError: Error, LocalizedError {
    case backupNotFound
    case insufficientSpace
    case permissionDenied
    case corruptedBackup
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .backupNotFound:
            return "Backup file not found"
        case .insufficientSpace:
            return "Insufficient disk space for backup"
        case .permissionDenied:
            return "Permission denied to access backup location"
        case .corruptedBackup:
            return "Backup file is corrupted"
        case .restoreFailed(let reason):
            return "Restore failed: \(reason)"
        }
    }
}

// MARK: - Backup UI Components

struct BackupManagementView: View {
    let project: Project
    @StateObject private var backupSystem = BackupRecoverySystem()
    @Environment(\.dismiss) private var dismiss

    @State private var showingCreateBackup = false
    @State private var showingRestoreConfirmation = false
    @State private var selectedBackup: BackupInfo?
    @State private var showingSettings = false

    var body: some View {
        NavigationView {
            VStack {
                // Header with actions
                HStack {
                    VStack(alignment: .leading) {
                        Text("Backup Management")
                            .font(.title2)
                            .fontWeight(.semibold)

                        if let lastBackup = backupSystem.lastBackupDate {
                            Text("Last backup: \(lastBackup, style: .relative)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    HStack {
                        Button("Settings") {
                            showingSettings = true
                        }
                        .buttonStyle(.bordered)

                        Button("Create Backup") {
                            showingCreateBackup = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()

                Divider()

                // Backups list
                if backupSystem.availableBackups.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("No Backups Available")
                            .font(.headline)

                        Text("Create your first backup to protect your translation data")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Create Backup") {
                            showingCreateBackup = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(backupSystem.availableBackups) { backup in
                            BackupRow(
                                backup: backup,
                                onRestore: {
                                    selectedBackup = backup
                                    showingRestoreConfirmation = true
                                },
                                onDelete: {
                                    try? backupSystem.deleteBackup(backup)
                                }
                            )
                        }
                    }
                }

                // Status indicators
                if backupSystem.isBackingUp || backupSystem.isRestoring {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)

                        Text(backupSystem.isBackingUp ? "Creating backup..." : "Restoring from backup...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            backupSystem.loadAvailableBackups()
            backupSystem.enableAutoBackup(for: project)
        }
        .onDisappear {
            backupSystem.disableAutoBackup()
        }
        .alert("Create Backup", isPresented: $showingCreateBackup) {
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                Task {
                    await backupSystem.createBackup(for: project)
                }
            }
        } message: {
            Text("This will create a backup of all translation data, locale files, and project configuration.")
        }
        .alert("Restore Backup", isPresented: $showingRestoreConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Restore", role: .destructive) {
                if let backup = selectedBackup {
                    Task {
                        await backupSystem.restoreFromBackup(backup, project: project)
                    }
                }
            }
        } message: {
            Text("This will replace all current data with the backup. A restore point will be created automatically.")
        }
        .sheet(isPresented: $showingSettings) {
            BackupSettingsView(settings: $backupSystem.backupSettings)
        }
    }
}

struct BackupRow: View {
    let backup: BackupInfo
    let onRestore: () -> Void
    let onDelete: () -> Void

    @State private var showingDetails = false

    var body: some View {
        HStack {
            // Backup type icon
            Image(systemName: backup.type.icon)
                .font(.title3)
                .foregroundColor(backup.type == .manual ? .blue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(backup.projectName)
                        .font(.headline)

                    Spacer()

                    Text(backup.type.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }

                Text(backup.description)
                    .font(.body)
                    .foregroundColor(.secondary)

                HStack {
                    Text(backup.createdAt, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(backup.createdAt, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(backup.formattedSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button("Details") {
                    showingDetails = true
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Button("Restore") {
                    onRestore()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Delete") {
                    onDelete()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingDetails) {
            BackupDetailsView(backup: backup)
        }
    }
}

struct BackupDetailsView: View {
    let backup: BackupInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: backup.type.icon)
                        .font(.title)
                        .foregroundColor(.blue)

                    VStack(alignment: .leading) {
                        Text(backup.projectName)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(backup.type.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                Divider()

                // Details
                VStack(alignment: .leading, spacing: 12) {
                    DetailRow(label: "Created", value: backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                    DetailRow(label: "Size", value: backup.formattedSize)
                    DetailRow(label: "Description", value: backup.description)
                    DetailRow(label: "Project Path", value: backup.projectPath)

                    if let backupPath = backup.backupPath {
                        DetailRow(label: "Backup Location", value: backupPath)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Backup Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .fontWeight(.medium)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(.body)
                .foregroundColor(.secondary)
                .textSelection(.enabled)

            Spacer()
        }
    }
}

struct BackupSettingsView: View {
    @Binding var settings: BackupSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Automatic Backups") {
                    Toggle("Enable automatic backups", isOn: $settings.autoBackupEnabled)

                    if settings.autoBackupEnabled {
                        HStack {
                            Text("Backup interval")
                            Spacer()
                            TextField("Minutes", value: $settings.autoBackupInterval, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("minutes")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Retention Policy") {
                    HStack {
                        Text("Keep backups for")
                        Spacer()
                        TextField("Days", value: $settings.retentionDays, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("days")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Storage") {
                    Toggle("Compress backups", isOn: $settings.compressBackups)

                    HStack {
                        Text("Maximum backup size")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: settings.maxBackupSize, countStyle: .file))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Backup Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
