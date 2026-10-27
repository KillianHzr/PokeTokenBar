import AppKit
import SwiftUI

/// Sends an idea or a bug to the fork's GitHub issues (`IdeaReport`): posted with the GitHub CLI when it is signed in,
/// else opened prefilled in the browser.
@MainActor
struct IdeasScreen: View {
    let l: L
    let onBack: () -> Void

    @State private var kind: IdeaReport.Kind = .idea
    @State private var title = ""
    @State private var details = ""
    @State private var includeSystem = true
    /// The GitHub CLI, when installed and signed in.
    @State private var gh: String?
    @State private var sending = false
    @State private var posted: URL?
    @State private var failed = false

    private var issueTitle: String { IdeaReport.title(kind, title) }
    private var issueBody: String { IdeaReport.body(details, system: includeSystem ? IdeaReport.systemDescription : nil) }
    private var canSend: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button { onBack() } label: {
                    Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                Spacer(minLength: 4)
                Text(l.ideasTitle).font(.headline)
            }
            Text(l.ideasIntro).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let posted {
                sentView(posted)
            } else {
                form
            }
            Spacer(minLength: 0)
        }
        .padding(PopoverMetrics.padding)
        .frame(height: 520, alignment: .top)
        .task {
            // Resolving the CLI may ask the login shell: off the main thread.
            guard let path = await Task.detached(operation: { IdeaReport.ghPath() }).value else { return }
            if await IdeaReport.ghIsSignedIn(path) { gh = path }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            PillPicker(selection: $kind, options: IdeaReport.Kind.allCases.map { ($0, l.ideaKind($0)) })
            TextField(l.ideasTitleField, text: $title).textFieldStyle(.roundedBorder)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $details)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                if details.isEmpty {
                    Text(l.ideasDetailsPlaceholder).font(.callout).foregroundStyle(.tertiary)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 170)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            Toggle(l.ideasIncludeSystem, isOn: $includeSystem).toggleStyle(.checkbox).font(.caption)
            HStack(spacing: 8) {
                if let gh {
                    Button(l.ideasSend) { Task { await post(with: gh) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSend)
                    Button(l.ideasOpenBrowser) { openInBrowser() }
                        .disabled(!canSend)
                } else {
                    Button(l.ideasOpenBrowser) { openInBrowser() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSend)
                }
                if sending { ProgressView().controlSize(.small) }
            }
            Text(failed ? l.ideasFailed : gh != nil ? l.ideasGHHint : l.ideasBrowserHint)
                .font(.caption2)
                .foregroundStyle(failed ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sentView(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(l.ideasSent, systemImage: "checkmark.circle.fill").foregroundStyle(Color.readableGreen).font(.callout.weight(.semibold))
            Button(l.ideasSeeIssue) { NSWorkspace.shared.open(url) }
        }
    }

    private func post(with gh: String) async {
        sending = true
        failed = false
        defer { sending = false }
        do {
            posted = try await IdeaReport.create(with: gh, title: issueTitle, body: issueBody)
        } catch {
            failed = true
        }
    }

    private func openInBrowser() {
        guard let url = IdeaReport.newIssueURL(title: issueTitle, body: issueBody) else { return }
        NSWorkspace.shared.open(url)
    }
}
