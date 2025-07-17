//
//  ChangeTrackingIndicators.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import SwiftUI

/// Visual indicators for tracking changes, draft status, and modification states
struct ChangeTrackingIndicators: View {
    let project: Project
    @StateObject private var changeTracker = ChangeTracker()
    
    var body: some View {
        VStack(spacing: 0) {
            // Global change status bar
            if project.hasUnsavedChanges {
                GlobalChangeStatusBar(
                    project: project,
                    changeTracker: changeTracker
                )
            }
            
            // Change summary panel
            ChangesSummaryPanel(
                project: project,
                changeTracker: changeTracker
            )
        }
        .onAppear {
            changeTracker.startTracking(project: project)
        }
        .onDisappear {
            changeTracker.stopTracking()
        }
    }
}

struct GlobalChangeStatusBar: View {
    let project: Project
    let changeTracker: ChangeTracker
    
    @State private var showingChangeDetails = false
    
    var body: some View {
        HStack {
            // Change indicator
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                
                Text("\(project.draftTranslationsCount) unsaved changes")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 12) {
                Button("View Changes") {
                    showingChangeDetails = true
                }
                .buttonStyle(.borderless)
                .font(.caption)
                
                Button("Save All") {
                    saveAllChanges()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Button("Discard All") {
                    discardAllChanges()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.orange.opacity(0.3)),
            alignment: .bottom
        )
        .sheet(isPresented: $showingChangeDetails) {
            ChangeDetailsView(project: project, changeTracker: changeTracker)
        }
    }
    
    private func saveAllChanges() {
        // Post notification to trigger save all in TranslationEditorView
        NotificationCenter.default.post(
            name: NSNotification.Name("SaveAllTranslations"),
            object: project
        )
    }
    
    private func discardAllChanges() {
        changeTracker.discardAllDrafts()
    }
}

struct ChangesSummaryPanel: View {
    let project: Project
    let changeTracker: ChangeTracker
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Changes")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if changeTracker.recentChanges.isEmpty {
                Text("No recent changes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(changeTracker.recentChanges.prefix(5), id: \.id) { change in
                        ChangeItemView(change: change)
                    }
                }
                
                if changeTracker.recentChanges.count > 5 {
                    Button("View All Changes") {
                        // TODO: Show all changes view
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct ChangeItemView: View {
    let change: ChangeRecord
    
    var body: some View {
        HStack {
            // Change type indicator
            changeTypeIcon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(change.description)
                    .font(.caption)
                    .lineLimit(1)
                
                HStack {
                    Text(change.key)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)

                    Spacer()
                    
                    Text(change.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 4) {
                if change.type == .draft {
                    Button(action: { commitChange(change) }) {
                        Image(systemName: "checkmark.circle")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .help("Commit change")
                    
                    Button(action: { discardChange(change) }) {
                        Image(systemName: "xmark.circle")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Discard change")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(change.type == .draft ? Color.orange.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
    
    private var changeTypeIcon: some View {
        Group {
            switch change.type {
            case .draft:
                Image(systemName: "pencil.circle.fill")
                    .foregroundColor(.orange)
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .deleted:
                Image(systemName: "trash.circle.fill")
                    .foregroundColor(.red)
            case .created:
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .font(.caption)
    }
    
    private func commitChange(_ change: ChangeRecord) {
        // TODO: Implement commit functionality
    }
    
    private func discardChange(_ change: ChangeRecord) {
        // TODO: Implement discard functionality
    }
}

struct TranslationChangeIndicator: View {
    let translation: Translation
    let isCompact: Bool
    
    init(translation: Translation, isCompact: Bool = false) {
        self.translation = translation
        self.isCompact = isCompact
    }
    
    var body: some View {
        HStack(spacing: isCompact ? 2 : 4) {
            // Draft indicator
            if translation.isDraft {
                if isCompact {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                } else {
                    Label("Draft", systemImage: "pencil.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            
            // Changes indicator
            if translation.hasChanges {
                if isCompact {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                } else {
                    Label("Modified", systemImage: "circle.fill")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            
            // Validation indicator
            let validationResult = translation.validate()
            if validationResult.hasIssues {
                if isCompact {
                    Circle()
                        .fill(validationResult.isValid ? Color.yellow : Color.red)
                        .frame(width: 6, height: 6)
                } else {
                    Label(validationResult.isValid ? "Warning" : "Error", 
                          systemImage: validationResult.isValid ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(validationResult.isValid ? .yellow : .red)
                }
            }
        }
    }
}

struct KeyUsageIndicator: View {
    let key: I18nKey
    let isCompact: Bool
    
    init(key: I18nKey, isCompact: Bool = false) {
        self.key = key
        self.isCompact = isCompact
    }
    
    var body: some View {
        HStack(spacing: isCompact ? 2 : 4) {
            // Usage indicator
            if key.isUsedInFiles {
                if isCompact {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                } else {
                    Label("\(key.activeFileUsages.count)", systemImage: "link")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            } else {
                if isCompact {
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 6, height: 6)
                } else {
                    Label("Unused", systemImage: "link.slash")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            
            // Missing translations indicator
            if key.hasMissingTranslations {
                if isCompact {
                    Triangle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                } else {
                    Label("Missing", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            
            // Completion indicator
            let completion = key.completionPercentage
            if completion < 1.0 && !isCompact {
                HStack(spacing: 2) {
                    Text("\(Int(completion * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    ProgressView(value: completion)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(width: 30, height: 4)
                        .tint(completionColor(completion))
                }
            }
        }
    }
    
    private func completionColor(_ completion: Double) -> Color {
        if completion >= 0.8 {
            return .green
        } else if completion >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct ChangeDetailsView: View {
    let project: Project
    let changeTracker: ChangeTracker
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                // Changes list
                List {
                    ForEach(changeTracker.recentChanges, id: \.id) { change in
                        ChangeDetailRow(change: change)
                    }
                }
                
                // Action buttons
                HStack {
                    Button("Discard All") {
                        changeTracker.discardAllDrafts()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Save All") {
                        // Post notification to trigger save all in TranslationEditorView
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SaveAllTranslations"),
                            object: project
                        )
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Changes")
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

struct ChangeDetailRow: View {
    let change: ChangeRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                changeTypeIcon
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.description)
                        .font(.headline)
                    
                    Text(change.key)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(change.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let oldValue = change.oldValue, let newValue = change.newValue {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Changes:")
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    HStack {
                        Text("- \(oldValue)")
                            .font(.caption)
                            .foregroundColor(.red)
                            .strikethrough()
                        
                        Spacer()
                    }
                    
                    HStack {
                        Text("+ \(newValue)")
                            .font(.caption)
                            .foregroundColor(.green)
                        
                        Spacer()
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var changeTypeIcon: some View {
        Group {
            switch change.type {
            case .draft:
                Image(systemName: "pencil.circle.fill")
                    .foregroundColor(.orange)
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .deleted:
                Image(systemName: "trash.circle.fill")
                    .foregroundColor(.red)
            case .created:
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .font(.title3)
    }
}

// MARK: - Change Tracker

class ChangeTracker: ObservableObject {
    @Published var recentChanges: [ChangeRecord] = []
    
    private var project: Project?
    
    func startTracking(project: Project) {
        self.project = project
        loadRecentChanges()
    }
    
    func stopTracking() {
        self.project = nil
        recentChanges = []
    }
    
    func recordChange(_ change: ChangeRecord) {
        recentChanges.insert(change, at: 0)
        
        // Keep only recent changes (last 100)
        if recentChanges.count > 100 {
            recentChanges = Array(recentChanges.prefix(100))
        }
    }
    
    func discardAllDrafts() {
        guard let project = project else { return }
        
        // TODO: Implement discard all drafts functionality
        // This would involve removing all draft translations
        
        loadRecentChanges()
    }
    
    private func loadRecentChanges() {
        guard let project = project else { return }
        
        // Load recent changes from Core Data
        // This is a simplified implementation
        let translations = project.translations?.allObjects as? [Translation] ?? []
        
        recentChanges = translations.compactMap { translation in
            guard translation.isDraft || translation.hasChanges else { return nil }
            
            return ChangeRecord(
                type: translation.isDraft ? .draft : .saved,
                key: translation.i18nKey?.key ?? "",
                locale: translation.locale ?? "",
                description: translation.isDraft ? "Draft changes" : "Saved changes",
                oldValue: translation.value,
                newValue: translation.draftValue ?? translation.value,
                timestamp: translation.lastModified ?? Date()
            )
        }.sorted { $0.timestamp > $1.timestamp }
    }
}

// MARK: - Supporting Types

struct ChangeRecord: Identifiable {
    let id = UUID()
    let type: ChangeType
    let key: String
    let locale: String
    let description: String
    let oldValue: String?
    let newValue: String?
    let timestamp: Date
}

enum ChangeType {
    case draft
    case saved
    case deleted
    case created
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let project = Project(context: context)
    project.name = "Sample Project"
    project.locales = ["en", "es"]
    
    return ChangeTrackingIndicators(project: project)
}
