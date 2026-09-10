/**
 * Apple Sharpener: App Rule Picker
 *
 * Provides a UI component for discovering and selecting installed macOS
 * applications to apply specific sharpening rules.
 */

import SwiftUI
import AppKit

// MARK: - Installed app (same idea as Hider’s AppInfo: icon + name + bundle id)

struct InstalledAppInfo: Identifiable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let name: String
    let icon: NSImage
}

// MARK: - Loader (Hider-style directories + running apps + ~/Applications)

@MainActor
final class InstalledAppListLoader: ObservableObject {
    @Published private(set) var apps: [InstalledAppInfo] = []
    @Published private(set) var isLoading = false

    func refresh() {
        isLoading = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.performScan()
            }.value
            apps = result
            isLoading = false
        }
    }

    nonisolated private static func performScan() -> [InstalledAppInfo] {
        var seen = Set<String>()
        var result: [InstalledAppInfo] = []

        var dirs: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Library/CoreServices"),
        ]
        let homeApps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        if FileManager.default.fileExists(atPath: homeApps.path) {
            dirs.insert(homeApps, at: 0)
        }

        for dir in dirs {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in urls where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bid = bundle.bundleIdentifier,
                      !seen.contains(bid) else { continue }
                seen.insert(bid)

                let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle.infoDictionary?["CFBundleName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                result.append(InstalledAppInfo(bundleIdentifier: bid, name: name, icon: icon))
            }
        }

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bid = app.bundleIdentifier,
                  !seen.contains(bid),
                  let url = app.bundleURL else { continue }
            seen.insert(bid)
            let name = app.localizedName
                ?? Bundle(url: url)?.infoDictionary?["CFBundleDisplayName"] as? String
                ?? Bundle(url: url)?.infoDictionary?["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
            let icon = app.icon ?? NSWorkspace.shared.icon(forFile: url.path)
            result.append(InstalledAppInfo(bundleIdentifier: bid, name: name, icon: icon))
        }

        result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return result
    }
}

// MARK: - Sheet: search + scroll list + optional manual bundle ID

struct AddAppRuleSheet: View {
    @ObservedObject var model: ConfigModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var loader = InstalledAppListLoader()
    @State private var searchText = ""
    @State private var manualBundleID = ""
    @State private var showManualEntry = false

    private var existingBundleIds: Set<String> {
        Set(model.rules.map(\.bundleId))
    }

    private var filteredApps: [InstalledAppInfo] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return loader.apps.filter { app in
            !existingBundleIds.contains(app.bundleIdentifier)
                && (q.isEmpty
                    || app.name.lowercased().contains(q)
                    || app.bundleIdentifier.lowercased().contains(q))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add per-app rule")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Text("Pick an app — bundle ID is filled in for you. You can also paste a bundle ID below.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("Search apps or bundle ID", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.06))
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            Group {
                if loader.isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading apps…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredApps.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 26))
                            .foregroundStyle(.secondary)
                        Text(searchText.isEmpty ? "No apps to add (all listed may already have a rule)." : "No matching apps")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredApps) { app in
                                InstalledAppPickerRow(app: app) {
                                    addRule(bundleId: app.bundleIdentifier)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .frame(height: 280)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showManualEntry.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(showManualEntry ? 90 : 0))
                        Text("Enter bundle identifier manually")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if showManualEntry {
                    HStack(spacing: 8) {
                        TextField("com.example.app", text: $manualBundleID)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        Button("Add") { addRule(bundleId: manualBundleID) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(manualBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 400)
        .onAppear { loader.refresh() }
    }

    private func addRule(bundleId raw: String) {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        guard !existingBundleIds.contains(id) else { return }
        model.rules.append(AppRuleModel(bundleId: id))
        model.save()
        dismiss()
    }
}

// MARK: - Row (Hider-style hover + icon + name)

private struct InstalledAppPickerRow: View {
    let app: InstalledAppInfo
    let onSelect: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(app.bundleIdentifier)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.blue.opacity(hovered ? 1 : 0.45))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovered ? Color.primary.opacity(0.07) : Color.clear)
                    .padding(.horizontal, 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
