// Bend Fly Shop

// CreateThreadView.swift
import SwiftUI

struct CreateThreadView: View {
  let categoryId: String
  let categoryName: String

  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var auth: AuthService

  // Inputs
  @State private var titleText: String = ""
  @State private var bodyText: String = ""

  // Media state
  @State private var selectedMedia: [SelectedMedia] = []
  @State private var showMediaPicker = false
  @State private var mediaError: String?

  // UI state
  @State private var isSubmitting = false
  @State private var error: String?
  @State private var showCancelConfirm = false

  // Limits
  private let titleMaxWords = 20
  private let bodyMaxWords = 500
  private let maxMediaCount = 5

  var body: some View {
    NavigationView {
      ZStack {
        Color.black.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 16) {
          // Title input (multiline wrapping; iOS 15-safe)
          VStack(alignment: .leading, spacing: 6) {
            Text("Thread title")
              .font(.subheadline.weight(.semibold))
              .foregroundColor(.white.opacity(0.9))

            titleInputField

            Text("\(wordCount(titleText))/\(titleMaxWords) words")
              .font(.caption)
              .foregroundColor(.white.opacity(0.6))
          }

          // Body input (becomes first post)
          VStack(alignment: .leading, spacing: 6) {
            Text("Body")
              .font(.subheadline.weight(.semibold))
              .foregroundColor(.white.opacity(0.9))

            bodyInputField

            Text("\(wordCount(bodyText))/\(bodyMaxWords) words")
              .font(.caption)
              .foregroundColor(.white.opacity(0.6))
          }

          // Media attachments section
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text("Attachments")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))
              Text("(optional)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
            }

            // Selected media preview
            if !selectedMedia.isEmpty {
              SelectedMediaGrid(media: selectedMedia) { item in
                selectedMedia.removeAll { $0.id == item.id }
              }
            }

            // Add media button
            AddMediaButton(
              currentCount: selectedMedia.count,
              maxCount: maxMediaCount
            ) {
              showMediaPicker = true
            }

            if let mediaError = mediaError {
              Text(mediaError)
                .font(.caption)
                .foregroundColor(.red)
            }
          }

          if let error {
            Text(error).foregroundColor(.red)
          }

          Spacer()

          Button {
            guard canSubmit && !isSubmitting else { return }
            Task { await submit() }
          } label: {
            HStack {
              if isSubmitting { ProgressView().tint(.white) }
              Text(isSubmitting ? "Posting…" : "Post Thread")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(canSubmit ? Color.blue : Color.white.opacity(0.2))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
          }
          .disabled(!canSubmit || isSubmitting)
        }
        .padding(16)
        .onAppear { AppLogging.log("[CreateThreadView] onAppear", level: .debug, category: .forum) }
        .onDisappear { AppLogging.log("[CreateThreadView] onDisappear", level: .debug, category: .forum) }
      }
      .preferredColorScheme(.dark)
      .navigationTitle("New Thread (\(categoryName))")
      .navigationBarTitleDisplayMode(.inline)
      .navigationBarBackButtonHidden(true)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            if hasUnsavedChanges {
              showCancelConfirm = true
            } else {
              dismiss()
            }
          }
        }
      }
      .confirmationDialog(
        "You have unsaved changes. Discard them?",
        isPresented: $showCancelConfirm,
        titleVisibility: .visible
      ) {
        Button("Discard Changes", role: .destructive) { dismiss() }
        Button("Keep Editing", role: .cancel) {}
      }
      .sheet(isPresented: $showMediaPicker) {
        ForumMediaPicker(
          maxSelections: maxMediaCount - selectedMedia.count,
          onPicked: { media in
            selectedMedia.append(contentsOf: media)
            mediaError = nil
          },
          onError: { error in
            mediaError = error
          }
        )
      }
    }
  }

  // MARK: - Submit

  private var canSubmit: Bool {
    wordCount(titleText) > 0 && wordCount(titleText) <= titleMaxWords && !isSubmitting
  }

  private var hasUnsavedChanges: Bool {
    !titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !selectedMedia.isEmpty
  }

  private func submit() async {
    AppLogging.log("[CreateThreadView] submit() called. titleWords=\(wordCount(titleText)), bodyWords=\(wordCount(bodyText)), mediaCount=\(selectedMedia.count)", level: .debug, category: .forum)
    guard let access = await auth.forumAccessToken() else {
      error = ForumAPIError.missingAuth.localizedDescription
      return
    }
    isSubmitting = true; error = nil
    defer { isSubmitting = false }

    do {
      let titleTrimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
      let bodyTrimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)

      // Convert selected media to attachments
      let attachments: [MediaAttachment]? = selectedMedia.isEmpty ? nil : selectedMedia.map { media in
        MediaAttachment(
          fileName: media.fileName,
          mimeType: media.mimeType,
          data_base64: media.data.base64EncodedString()
        )
      }

      AppLogging.log("[CreateThreadView] Creating thread with media. categoryId=\(categoryId), title=\(titleTrimmed), mediaCount=\(attachments?.count ?? 0)", level: .debug, category: .forum)

      let (thread, post) = try await ForumAPI.createThreadWithMedia(
        accessToken: access,
        categoryId: categoryId,
        title: titleTrimmed,
        content: bodyTrimmed,
        media: attachments
      )

      AppLogging.log("[CreateThreadView] Thread created. threadId=\(thread.id), postId=\(post.id)", level: .debug, category: .forum)
      AppLogging.log("[CreateThreadView] Submission complete. Dismissing view.", level: .debug, category: .forum)
      dismiss()
    } catch {
      AppLogging.log("[CreateThreadView] Submission failed: \(error.localizedDescription)", level: .debug, category: .forum)
      self.error = error.localizedDescription
    }
  }

  // MARK: - Word limiting

  private func wordCount(_ text: String) -> Int {
    text.split { $0.isWhitespace || $0.isNewline }.count
  }

  private func limited(to maxWords: Int, text: String) -> String {
    let parts = text.split { $0.isWhitespace || $0.isNewline }
    if parts.count <= maxWords { return text }
    // Rebuild with first maxWords preserving single spaces
    return parts.prefix(maxWords).joined(separator: " ")
  }

  // MARK: - Input fields

  private var titleInputField: some View {
    TextField("What do you want to discuss?", text: $titleText, axis: .vertical)
      .textFieldStyle(.roundedBorder)
      .lineLimit(1 ... 3)
      .onChange(of: titleText) { _ in
        titleText = limited(to: titleMaxWords, text: titleText)
      }
  }

  private var bodyInputField: some View {
    TextField("Add details…", text: $bodyText, axis: .vertical)
      .textFieldStyle(.roundedBorder)
      .lineLimit(3 ... 10)
      .onChange(of: bodyText) { _ in
        bodyText = limited(to: bodyMaxWords, text: bodyText)
      }
  }
}
