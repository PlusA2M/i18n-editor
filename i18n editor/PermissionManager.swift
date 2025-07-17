//
//  PermissionManager.swift
//  i18n editor
//
//  Created by PlusA on 17/07/2025.
//

import Foundation
import SwiftUI
import AppKit

/// Manages app permissions including Full Disk Access and file system permissions
class PermissionManager: ObservableObject {
    @Published var hasFullDiskAccess = false
    @Published var showingPermissionAlert = false
    @Published var permissionAlertMessage = ""
    
    private let fileManager = FileManager.default
    
    // MARK: - Permission Checking
    
    /// Check permissions when app launches
    func checkPermissionsOnLaunch() {
        DispatchQueue.global(qos: .background).async {
            let hasAccess = self.checkFullDiskAccess()
            
            DispatchQueue.main.async {
                self.hasFullDiskAccess = hasAccess
                
                if !hasAccess {
                    // Show permission request after a brief delay to allow UI to settle
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.requestFullDiskAccessIfNeeded()
                    }
                }
            }
        }
    }
    
    /// Check if the app has Full Disk Access
    func checkFullDiskAccess() -> Bool {
        // Try to access files that require Full Disk Access
        let testPaths = [
            NSHomeDirectory() + "/Library/Safari/Bookmarks.plist",
            "/Library/Application Support/com.apple.TCC/TCC.db",
            "/Library/Preferences/com.apple.TimeMachine.plist",
            NSHomeDirectory() + "/Library/Preferences/com.apple.finder.plist"
        ]
        
        for path in testPaths {
            if fileManager.isReadableFile(atPath: path) {
                return true
            }
        }
        
        return false
    }
    
    /// Request Full Disk Access with user-friendly dialog
    func requestFullDiskAccessIfNeeded() {
        guard !hasFullDiskAccess else { return }
        
        DispatchQueue.main.async {
            self.showPermissionRequestDialog()
        }
    }
    
    /// Show permission request dialog
    private func showPermissionRequestDialog() {
        let alert = NSAlert()
        alert.messageText = "Full Disk Access Required"
        alert.informativeText = """
        i18n Editor needs Full Disk Access to read and write project files in any location on your system.
        
        This permission allows the app to:
        • Access SvelteKit project files
        • Read and write translation files
        • Scan project directories for Svelte files
        
        Click 'Open Settings' to grant permission in System Preferences.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Skip for Now")
        alert.addButton(withTitle: "Learn More")
        alert.alertStyle = .informational
        alert.icon = NSImage(systemSymbolName: "folder.badge.questionmark", accessibilityDescription: "Permission Required")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            openFullDiskAccessSettings()
        case .alertThirdButtonReturn:
            showPermissionHelp()
        default:
            break
        }
    }
    
    /// Open System Preferences to Full Disk Access section
    private func openFullDiskAccessSettings() {
        // First, attempt to access a protected file to trigger macOS to add our app to the list
        triggerFullDiskAccessPrompt()

        // Then open System Settings
        // Try different URLs for different macOS versions
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles", // macOS 13+
            "x-apple.systempreferences:com.apple.preferences.security.privacy?Privacy_AllFiles", // macOS 12
            "x-apple.systempreferences:com.apple.preference.security" // Fallback
        ]

        for urlString in urls {
            if let url = URL(string: urlString) {
                if NSWorkspace.shared.open(url) {
                    break
                }
            }
        }
    }

    /// Trigger macOS to add our app to Full Disk Access list by attempting to access protected files
    private func triggerFullDiskAccessPrompt() {
        // Attempt to access various protected locations to ensure our app appears in System Settings
        let protectedPaths = [
            NSHomeDirectory() + "/Library/Safari/Bookmarks.plist",
            NSHomeDirectory() + "/Library/Preferences/com.apple.finder.plist",
            "/Library/Application Support/com.apple.TCC/TCC.db",
            NSHomeDirectory() + "/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments",
            NSHomeDirectory() + "/Desktop", // Desktop access also requires Full Disk Access in some cases
            NSHomeDirectory() + "/Documents" // Documents access
        ]

        for path in protectedPaths {
            // Just attempt to check if file exists - this is enough to trigger the system prompt
            _ = fileManager.fileExists(atPath: path)

            // Also try to read the file (will fail without permission but triggers the system)
            _ = fileManager.isReadableFile(atPath: path)
        }
    }
    
    /// Show additional help about permissions
    private func showPermissionHelp() {
        let alert = NSAlert()
        alert.messageText = "How to Grant Full Disk Access"
        alert.informativeText = """
        1. Open System Preferences/Settings
        2. Go to Security & Privacy (or Privacy & Security)
        3. Click on the Privacy tab
        4. Select "Full Disk Access" from the list
        5. Click the lock icon and enter your password
        6. Click the "+" button and add "i18n Editor"
        7. Make sure the checkbox next to "i18n Editor" is checked
        8. Restart the app for changes to take effect
        
        This permission is required for the app to access project files anywhere on your system.
        """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Settings")
        alert.alertStyle = .informational
        
        if alert.runModal() == .alertSecondButtonReturn {
            openFullDiskAccessSettings()
        }
    }
    
    // MARK: - Project-Specific Permissions
    
    /// Check if we can access a specific project path
    func canAccessProject(at path: String) -> Bool {
        // First check if we have a security-scoped bookmark
        if let bookmarkData = UserDefaults.standard.data(forKey: "bookmark_\(path)") {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                if !isStale && url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    return fileManager.isReadableFile(atPath: path)
                }
            } catch {
                print("Failed to resolve security-scoped bookmark: \(error)")
            }
        }
        
        // Fall back to checking direct access (works with Full Disk Access)
        return fileManager.isReadableFile(atPath: path)
    }
    
    /// Request access to a specific project folder
    func requestProjectAccess(for path: String, completion: @escaping (Bool) -> Void) {
        if canAccessProject(at: path) {
            completion(true)
            return
        }
        
        // If we don't have Full Disk Access, suggest granting it
        if !hasFullDiskAccess {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Project Access Required"
                alert.informativeText = "Unable to access the project folder. Please grant Full Disk Access or select the project folder again."
                alert.addButton(withTitle: "Grant Full Disk Access")
                alert.addButton(withTitle: "Select Folder Again")
                alert.addButton(withTitle: "Cancel")
                alert.alertStyle = .warning
                
                let response = alert.runModal()
                
                switch response {
                case .alertFirstButtonReturn:
                    self.openFullDiskAccessSettings()
                    completion(false)
                case .alertSecondButtonReturn:
                    // Let the caller handle folder selection
                    completion(false)
                default:
                    completion(false)
                }
            }
        } else {
            completion(false)
        }
    }
    
    // MARK: - Periodic Permission Checks
    
    /// Refresh permission status (call this when app becomes active)
    func refreshPermissionStatus() {
        DispatchQueue.global(qos: .background).async {
            let hasAccess = self.checkFullDiskAccess()
            
            DispatchQueue.main.async {
                self.hasFullDiskAccess = hasAccess
            }
        }
    }
}
