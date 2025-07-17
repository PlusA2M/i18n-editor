//
//  ProjectSelectionView.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import SwiftUI

struct ProjectSelectionView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var recentProjects: [RecentProject] = []
    @State private var showingError = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "globe")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("i18n Editor")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Select a SvelteKit project to get started")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 60)
            .padding(.bottom, 40)

            // Main content
            HStack(spacing: 40) {
                // New Project Section
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 32))
                            .foregroundColor(.accentColor)

                        Text("Open Project")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Select a SvelteKit project folder to start editing translations")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: {
                        projectManager.selectProjectFolder()
                    }) {
                        HStack {
                            Image(systemName: "folder")
                            Text("Choose Folder")
                        }
                        .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: 300)

                // Divider
                Divider()
                    .frame(height: 200)

                // Recent Projects Section
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 32))
                            .foregroundColor(.accentColor)

                        Text("Recent Projects")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Quickly access your recently opened projects")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if recentProjects.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.title)
                                .foregroundColor(.secondary)

                            Text("No recent projects")
                                .foregroundColor(.secondary)
                        }
                        .frame(height: 100)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(recentProjects) { project in
                                    RecentProjectRow(
                                        project: project,
                                        onOpen: {
                                            projectManager.openRecentProject(project)
                                        },
                                        onRemove: {
                                            projectManager.removeFromRecentProjects(project)
                                            loadRecentProjects()
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        .frame(maxHeight: 200)

                        if recentProjects.count > 1 {
                            Button("Clear All") {
                                projectManager.clearRecentProjects()
                                loadRecentProjects()
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: 400)
            }

            Spacer()

            // Footer
            HStack {
                Text("Supports SvelteKit projects with inlang configuration")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("About") {
                    // TODO: Show about dialog
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadRecentProjects()
        }
        .alert("Project Loading Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(projectManager.projectLoadingError ?? "Unknown error occurred")
        }
        .onChange(of: projectManager.projectLoadingError) { error in
            showingError = error != nil
        }
        .onChange(of: projectManager.isProjectLoaded) { isLoaded in
            if isLoaded {
                // Project loaded successfully - this will trigger navigation in parent view
            }
        }
    }

    private func loadRecentProjects() {
        recentProjects = projectManager.getRecentProjects()
    }
}

struct RecentProjectRow: View {
    let project: RecentProject
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(project.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text("Last opened: \(project.lastModified, formatter: dateFormatter)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove from recent projects")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovering ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            onOpen()
        }
        .help("Open \(project.name)")
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
}()

#Preview {
    ProjectSelectionView()
        .environmentObject(ProjectManager())
}
