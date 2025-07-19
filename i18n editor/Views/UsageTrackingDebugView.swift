//
//  UsageTrackingDebugView.swift
//  i18n editor
//
//  Created by PlusA on 18/07/2025.
//

import SwiftUI

/// Debug view for diagnosing usage tracking issues
struct UsageTrackingDebugView: View {
    let project: Project
    let usageTracker: UsageTrackingSystem
    @StateObject private var debugger = UsageTrackingDebugger()
    @Environment(\.dismiss) private var dismiss
    @State private var showingIntegrationTest = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with progress
                if debugger.isDebugging {
                    DebugProgressHeader(
                        progress: debugger.debugProgress,
                        operation: debugger.currentOperation
                    )
                }
                
                // Debug log
                DebugLogView(entries: debugger.debugLog)
                
                // Action buttons
                HStack {
                    Button("Clear Log") {
                        debugger.debugLog.removeAll()
                    }
                    .disabled(debugger.isDebugging)

                    Button("Integration Test") {
                        showingIntegrationTest = true
                    }
                    .disabled(debugger.isDebugging)

                    Button("Test Patterns") {
                        Task {
                            await debugger.testNegativeLookbehind()
                        }
                    }
                    .disabled(debugger.isDebugging)
                    .help("Test negative lookbehind regex patterns")

                    Button("Force Rescan") {
                        Task {
                            await usageTracker.forceFullRescan()
                        }
                    }
                    .disabled(debugger.isDebugging)
                    .help("Clean up all data and perform a fresh scan of the project")

                    Button("Clean Up Data") {
                        Task {
                            await usageTracker.cleanupUsageData()
                        }
                    }
                    .disabled(debugger.isDebugging)
                    .help("Remove all usage tracking data without rescanning")

                    Spacer()

                    Button("Export Log") {
                        exportDebugLog()
                    }
                    .disabled(debugger.debugLog.isEmpty)

                    Button("Run Debug Analysis") {
                        Task {
                            await debugger.runDebugAnalysis(for: project)
                        }
                    }
                    .disabled(debugger.isDebugging)
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Usage Tracking Debug")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .sheet(isPresented: $showingIntegrationTest) {
            UsageTrackingTestView()
        }
    }
    
    private func exportDebugLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "usage-tracking-debug-\(Date().timeIntervalSince1970).txt"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let logContent = debugger.debugLog.map { entry in
                    let timestamp = DateFormatter.debugTimestamp.string(from: entry.timestamp)
                    let level = entry.level.description
                    return "[\(timestamp)] \(level): \(entry.message)"
                }.joined(separator: "\n")
                
                try? logContent.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

struct DebugProgressHeader: View {
    let progress: Double
    let operation: String
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "gearshape.2")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Running Debug Analysis")
                    .font(.headline)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.headline)
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                
                Text(operation)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
}

struct DebugLogView: View {
    let entries: [DebugLogEntry]
    
    var body: some View {
        List {
            ForEach(entries) { entry in
                DebugLogEntryRow(entry: entry)
            }
        }
        .listStyle(PlainListStyle())
    }
}

struct DebugLogEntryRow: View {
    let entry: DebugLogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Level icon
            Image(systemName: entry.level.icon)
                .foregroundColor(entry.level.color)
                .font(.body)
                .frame(width: 16)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.message)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                    
                    Text(DateFormatter.debugTime.string(from: entry.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Extensions

extension DebugLogLevel {
    var description: String {
        switch self {
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

extension DateFormatter {
    static let debugTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    
    static let debugTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

// MARK: - Preview

struct UsageTrackingDebugView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let project = Project(context: context)
        project.name = "Test Project"
        project.path = "/path/to/project"

        let usageTracker = UsageTrackingSystem()

        return UsageTrackingDebugView(project: project, usageTracker: usageTracker)
    }
}
