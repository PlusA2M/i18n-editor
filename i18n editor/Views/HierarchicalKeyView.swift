//
//  HierarchicalKeyView.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import SwiftUI

/// Hierarchical view for displaying nested i18n keys with collapsible sections
struct HierarchicalKeyView: View {
    let project: Project
    let searchText: String
    let sortOrder: SortOrder
    let filterOption: FilterOption
    @Binding var selectedKeys: Set<String>
    
    @State private var keyHierarchy: [KeyGroup] = []
    @State private var expandedGroups: Set<String> = []
    @State private var locales: [String] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HierarchicalTableHeader(locales: locales)
            
            Divider()
            
            // Hierarchical content
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredKeyHierarchy, id: \.id) { group in
                        KeyGroupView(
                            group: group,
                            locales: locales,
                            selectedKeys: $selectedKeys,
                            expandedGroups: $expandedGroups,
                            level: 0
                        )
                    }
                }
            }
        }
        .onAppear {
            loadHierarchy()
        }
        .onChange(of: project) { _ in
            loadHierarchy()
        }
        .onChange(of: searchText) { _ in
            updateExpansionForSearch()
        }
    }
    
    private var filteredKeyHierarchy: [KeyGroup] {
        if searchText.isEmpty {
            return keyHierarchy
        }
        
        return keyHierarchy.compactMap { group in
            filterGroup(group)
        }
    }
    
    private func filterGroup(_ group: KeyGroup) -> KeyGroup? {
        let filteredChildren = group.children.compactMap { filterGroup($0) }
        let filteredKeys = group.keys.filter { key in
            (key.key ?? "").localizedCaseInsensitiveContains(searchText) ||
            (key.namespace ?? "").localizedCaseInsensitiveContains(searchText)
        }
        
        if filteredChildren.isEmpty && filteredKeys.isEmpty {
            return nil
        }
        
        return KeyGroup(
            name: group.name,
            fullPath: group.fullPath,
            keys: filteredKeys,
            children: filteredChildren,
            level: group.level
        )
    }
    
    private func loadHierarchy() {
        let i18nKeys = DataManager.shared.getI18nKeys(for: project)
        locales = project.allLocales
        keyHierarchy = buildKeyHierarchy(from: i18nKeys)
        
        // Auto-expand root level groups
        expandedGroups = Set(keyHierarchy.map { $0.fullPath })
    }
    
    private func updateExpansionForSearch() {
        if !searchText.isEmpty {
            // Expand all groups when searching
            expandAllGroups(keyHierarchy)
        }
    }
    
    private func expandAllGroups(_ groups: [KeyGroup]) {
        for group in groups {
            expandedGroups.insert(group.fullPath)
            expandAllGroups(group.children)
        }
    }
    
    private func buildKeyHierarchy(from keys: [I18nKey]) -> [KeyGroup] {
        var groupMap: [String: KeyGroup] = [:]
        var rootGroups: [KeyGroup] = []
        
        // First pass: create all groups
        for key in keys {
            let keyString = key.key ?? ""
            let components = keyString.components(separatedBy: ".")
            
            if components.count == 1 {
                // Root level key - add to root group
                if groupMap["_root"] == nil {
                    groupMap["_root"] = KeyGroup(
                        name: "Root Keys",
                        fullPath: "_root",
                        keys: [],
                        children: [],
                        level: 0
                    )
                }
                groupMap["_root"]?.keys.append(key)
            } else {
                // Nested key - create hierarchy
                var currentPath = ""
                var currentLevel = 0
                
                for (index, component) in components.enumerated() {
                    let isLast = index == components.count - 1
                    currentPath = currentPath.isEmpty ? component : "\(currentPath).\(component)"
                    
                    if isLast {
                        // This is the actual key, add it to the parent group
                        let parentPath = components.dropLast().joined(separator: ".")
                        if groupMap[parentPath] == nil {
                            groupMap[parentPath] = KeyGroup(
                                name: components.dropLast().last ?? "",
                                fullPath: parentPath,
                                keys: [],
                                children: [],
                                level: currentLevel - 1
                            )
                        }
                        groupMap[parentPath]?.keys.append(key)
                    } else {
                        // This is a group
                        if groupMap[currentPath] == nil {
                            groupMap[currentPath] = KeyGroup(
                                name: component,
                                fullPath: currentPath,
                                keys: [],
                                children: [],
                                level: currentLevel
                            )
                        }
                    }
                    
                    currentLevel += 1
                }
            }
        }
        
        // Second pass: build parent-child relationships
        let sortedPaths = groupMap.keys.sorted { $0.components(separatedBy: ".").count < $1.components(separatedBy: ".").count }
        
        for path in sortedPaths {
            guard let group = groupMap[path], path != "_root" else { continue }
            
            let components = path.components(separatedBy: ".")
            if components.count == 1 {
                // Top level group
                rootGroups.append(group)
            } else {
                // Find parent group
                let parentPath = components.dropLast().joined(separator: ".")
                if let parentGroup = groupMap[parentPath] {
                    parentGroup.children.append(group)
                }
            }
        }
        
        // Add root keys group if it exists
        if let rootGroup = groupMap["_root"], !rootGroup.keys.isEmpty {
            rootGroups.insert(rootGroup, at: 0)
        }
        
        // Sort groups and keys
        return sortGroups(rootGroups)
    }
    
    private func sortGroups(_ groups: [KeyGroup]) -> [KeyGroup] {
        let sortedGroups = groups.sorted { $0.name < $1.name }
        
        for group in sortedGroups {
            group.children = sortGroups(group.children)
            group.keys = group.keys.sorted { ($0.key ?? "") < ($1.key ?? "") }
        }
        
        return sortedGroups
    }
}

struct KeyGroupView: View {
    let group: KeyGroup
    let locales: [String]
    @Binding var selectedKeys: Set<String>
    @Binding var expandedGroups: Set<String>
    let level: Int
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Group header
            if !group.keys.isEmpty || !group.children.isEmpty {
                GroupHeaderView(
                    group: group,
                    isExpanded: expandedGroups.contains(group.fullPath),
                    level: level,
                    isHovered: isHovered
                ) {
                    toggleExpansion()
                }
                .onHover { hovering in
                    isHovered = hovering
                }
                
                Divider()
            }
            
            // Expanded content
            if expandedGroups.contains(group.fullPath) {
                // Child groups
                ForEach(group.children, id: \.id) { childGroup in
                    KeyGroupView(
                        group: childGroup,
                        locales: locales,
                        selectedKeys: $selectedKeys,
                        expandedGroups: $expandedGroups,
                        level: level + 1
                    )
                }
                
                // Keys in this group
                ForEach(group.keys, id: \.id) { key in
                    HierarchicalKeyRow(
                        key: key,
                        locales: locales,
                        level: level + 1,
                        isSelected: selectedKeys.contains(key.key ?? "")
                    )
                    .onTapGesture {
                        toggleKeySelection(key)
                    }
                    
                    Divider()
                }
            }
        }
    }
    
    private func toggleExpansion() {
        if expandedGroups.contains(group.fullPath) {
            expandedGroups.remove(group.fullPath)
        } else {
            expandedGroups.insert(group.fullPath)
        }
    }
    
    private func toggleKeySelection(_ key: I18nKey) {
        let keyString = key.key ?? ""
        if selectedKeys.contains(keyString) {
            selectedKeys.remove(keyString)
        } else {
            selectedKeys.insert(keyString)
        }
    }
}

struct GroupHeaderView: View {
    let group: KeyGroup
    let isExpanded: Bool
    let level: Int
    let isHovered: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            // Indentation and expansion indicator
            HStack(spacing: 4) {
                // Indentation
                ForEach(0..<level, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 20)
                }
                
                // Expansion button
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                
                // Group icon and name
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Text(group.name)
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    // Key count badge
                    if group.totalKeyCount > 0 {
                        Text("\(group.totalKeyCount)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.accentColor.opacity(0.05) : Color(NSColor.controlBackgroundColor))
            .contentShape(Rectangle())
            .onTapGesture {
                onToggle()
            }
        }
    }
}

struct HierarchicalKeyRow: View {
    let key: I18nKey
    let locales: [String]
    let level: Int
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            // Key column with indentation
            HStack(spacing: 0) {
                // Indentation
                ForEach(0..<level, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 20)
                }
                
                // Key content
                KeyCellContent(key: key, isSelected: isSelected)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Translation columns
            ForEach(locales, id: \.self) { locale in
                TranslationCell(
                    key: key,
                    locale: locale,
                    isSelected: isSelected
                )
                
                if locale != locales.last {
                    Divider()
                }
            }
        }
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }
}

struct KeyCellContent: View {
    let key: I18nKey
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Show only the final component for nested keys
                Text(key.finalComponent)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(isSelected ? .primary : .primary)
                
                Spacer()
                
                // Status indicators
                HStack(spacing: 4) {
                    if key.isUsedInFiles {
                        Image(systemName: "link")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .help("Used in \(key.activeFileUsages.count) location(s)")
                    }
                    
                    if key.hasMissingTranslations {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .help("Missing translations")
                    }
                    
                    // Completion indicator
                    let completion = key.completionPercentage
                    if completion < 1.0 {
                        Circle()
                            .fill(completionColor(completion))
                            .frame(width: 8, height: 8)
                            .help("Completion: \(Int(completion * 100))%")
                    }
                }
            }
            
            // Full key path for context (if nested)
            if key.isNested {
                Text(key.key ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .opacity(0.8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

struct HierarchicalTableHeader: View {
    let locales: [String]
    
    var body: some View {
        HStack(spacing: 0) {
            // Key column header
            Text("Key Hierarchy")
                .font(.headline)
                .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            
            Divider()
            
            // Locale column headers
            ForEach(locales, id: \.self) { locale in
                Text(locale.uppercased())
                    .font(.headline)
                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                
                if locale != locales.last {
                    Divider()
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Supporting Types

class KeyGroup: ObservableObject, Identifiable {
    let id = UUID()
    let name: String
    let fullPath: String
    var keys: [I18nKey]
    var children: [KeyGroup]
    let level: Int
    
    init(name: String, fullPath: String, keys: [I18nKey], children: [KeyGroup], level: Int) {
        self.name = name
        self.fullPath = fullPath
        self.keys = keys
        self.children = children
        self.level = level
    }
    
    var totalKeyCount: Int {
        return keys.count + children.reduce(0) { $0 + $1.totalKeyCount }
    }
    
    var hasKeys: Bool {
        return !keys.isEmpty || children.contains { $0.hasKeys }
    }
}

#Preview {
    // Create a mock project for preview
    let context = PersistenceController.preview.container.viewContext
    let project = Project(context: context)
    project.name = "Sample Project"
    project.path = "/path/to/project"
    project.locales = ["en", "es", "fr"]
    
    return HierarchicalKeyView(
        project: project,
        searchText: "",
        sortOrder: .alphabetical,
        filterOption: .all,
        selectedKeys: .constant([])
    )
}
