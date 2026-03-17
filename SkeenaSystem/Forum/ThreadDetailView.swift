// Bend Fly Shop

// ThreadDetailView.swift
import SwiftUI

struct ThreadDetailView: View {
  let thread: ForumThread
  let categoryName: String
  @EnvironmentObject private var auth: AuthService

  @State private var posts: [ForumPost] = []
  @State private var isLoading = false
  @State private var error: String?
  @State private var draft = ""
  @State private var currentUserId: String?
  @FocusState private var isFocused: Bool

  // Media attachment state
  @State private var selectedMedia: [SelectedMedia] = []
  @State private var showMediaPicker = false
  @State private var mediaError: String?
  @State private var isSending = false
  private let maxMediaCount = 5

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      VStack(spacing: 0) {
        // Thread heading (no Bend Fly Shop header on detail)
        VStack(alignment: .leading, spacing: 6) {
          Text(thread.title)
            .font(.title2.bold())
            .foregroundColor(.white)

          HStack(spacing: 8) {
            Text(threadAuthorName())
            if let when = thread.created_at { Text("• \(absoluteDate(when))") }
          }
          .font(.footnote)
          .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)

        Group {
          if isLoading {
            ProgressView().tint(.white).padding()
          } else if let error {
            Text(error).foregroundColor(.white).padding()
          } else {
            List {
              ForEach(posts) { p in
                postRow(p)
                  .listRowBackground(Color.white.opacity(0.06))
                  .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if canEdit(p) {
                      Button("Delete", role: .destructive) { Task { await delete(p) } }
                      Button("Edit") {
                        draft = p.content
                        isFocused = true
                      }
                    }
                  }
              }
            }
            .listStyle(.plain)
            .scrollContentBackgroundHiddenCompat()
            .refreshable { await load() }
          }
        }

        composer
      }
    }
    .navigationTitle(categoryName) // system back arrow; title stays category
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await load()
      await setupCurrentUser()
    }
  }

  private func postRow(_ p: ForumPost) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(postAuthorName(p)).font(.subheadline.weight(.semibold))
        Spacer()
        Text(absoluteDate(p.created_at ?? "")).font(.caption)
      }
      .foregroundColor(.white.opacity(0.9))
      Text(p.content)
        .foregroundColor(.white)
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)

      // Media attachments
      if let media = p.media, !media.isEmpty {
        ForumMediaGrid(media: media)
          .padding(.top, 4)
      }

      if p.is_edited == true {
        Text("Edited").font(.caption2).foregroundColor(.white.opacity(0.6))
      }
    }
    .padding(.vertical, 6)
  }

  private var composer: some View {
    VStack(spacing: 8) {
      // Selected media preview
      if !selectedMedia.isEmpty {
        SelectedMediaGrid(media: selectedMedia) { item in
          selectedMedia.removeAll { $0.id == item.id }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
      }

      // Media error
      if let mediaError = mediaError {
        Text(mediaError)
          .font(.caption)
          .foregroundColor(.red)
          .padding(.horizontal, 12)
      }

      HStack(spacing: 10) {
        // Add media button
        Button { showMediaPicker = true } label: {
          Image(systemName: "photo.on.rectangle")
            .foregroundColor(selectedMedia.count >= maxMediaCount ? .white.opacity(0.3) : .white.opacity(0.7))
            .padding(10)
            .background(Color.white.opacity(0.1))
            .clipShape(Circle())
        }
        .disabled(selectedMedia.count >= maxMediaCount || !auth.isAuthenticated)

        TextField("Write a reply…", text: $draft, axis: .vertical)
          .lineLimit(1 ... 5)
          .focused($isFocused)
          .padding(8)
          .background(Color.black)
          .foregroundColor(.white)
          .cornerRadius(8)
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))

        Button { Task { await send() } } label: {
          Group {
            if isSending {
              ProgressView()
                .tint(.white)
            } else {
              Image(systemName: "paperplane.fill")
            }
          }
          .foregroundColor(.white)
          .padding(10)
          .background(canSend ? Color.blue : Color.white.opacity(0.2))
          .clipShape(Circle())
        }
        .disabled(!canSend || isSending)
      }
      .padding(12)
    }
    .background(Color.white.opacity(0.05))
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

  private var canSend: Bool {
    let hasContent = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let hasMedia = !selectedMedia.isEmpty
    return (hasContent || hasMedia) && auth.isAuthenticated
  }

  // MARK: Data

  private func load() async {
    error = nil; isLoading = true
    defer { isLoading = false }
    do {
      // Edge Function requires auth token even for GET
      let accessToken = await auth.forumAccessToken()
      let fetched = try await ForumAPI.fetchPostsWithMedia(threadId: thread.id, accessToken: accessToken)
      posts = fetched
      #if DEBUG
      for p in posts.prefix(3) {
        print("[ThreadDetail] Post created_at:", p.created_at ?? "nil", "media count:", p.media?.count ?? 0)
      }
      #endif

      // Prefetch images for visible posts
      let imageURLs = posts.flatMap { $0.media ?? [] }
        .filter { $0.isImage }
        .compactMap { URL(string: $0.publicUrl) }
      ForumImageCache.shared.prefetch(urls: imageURLs)
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func setupCurrentUser() async {
    if let access = await auth.forumAccessToken() {
      currentUserId = auth.userId(fromAccessToken: access)
    } else {
      currentUserId = nil
    }
  }

  private func send() async {
    let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty || !selectedMedia.isEmpty else { return }
    guard let access = await auth.forumAccessToken() else {
      error = ForumAPIError.missingAuth.localizedDescription
      return
    }

    isSending = true
    defer { isSending = false }

    do {
      // Convert selected media to attachments
      let attachments: [MediaAttachment]? = selectedMedia.isEmpty ? nil : selectedMedia.map { media in
        MediaAttachment(
          fileName: media.fileName,
          mimeType: media.mimeType,
          data_base64: media.data.base64EncodedString()
        )
      }

      _ = try await ForumAPI.createPostWithMedia(
        accessToken: access,
        threadId: thread.id,
        content: content,
        media: attachments
      )

      // Clear composer
      draft = ""
      selectedMedia = []
      mediaError = nil

      await load()
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func delete(_ post: ForumPost) async {
    guard let access = await auth.forumAccessToken() else { return }
    do {
      try await ForumAPI.deletePost(accessToken: access, postId: post.id)
      await load()
    } catch { self.error = error.localizedDescription }
  }

  private func canEdit(_ post: ForumPost) -> Bool {
    currentUserId == post.user_id
  }

  // MARK: Helpers

  private func name(forUserId uid: String?) -> String {
    "Anonymous"
  }

  private func threadAuthorName() -> String {
    let fn = thread.author_first_name ?? ""
    let ln = thread.author_last_name ?? ""
    let both = "\(fn) \(ln)".trimmingCharacters(in: .whitespaces)
    return both.isEmpty ? "Anonymous" : both
  }

  private func postAuthorName(_ p: ForumPost) -> String {
    let fn = p.author_first_name ?? ""
    let ln = p.author_last_name ?? ""
    let both = "\(fn) \(ln)".trimmingCharacters(in: .whitespaces)
    return both.isEmpty ? name(forUserId: p.user_id) : both
  }

  private func parseISO8601(_ iso: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: iso)
  }

  private func relative(_ iso: String) -> String {
    if let d = parseISO8601(iso) {
      return RelativeDateTimeFormatter().localizedString(for: d, relativeTo: .now)
    }
    return ""
  }

  private func absoluteDate(_ iso: String) -> String {
    if let d = parseISO8601(iso) {
      let out = DateFormatter()
      out.dateStyle = .medium
      out.timeStyle = .none
      return out.string(from: d)
    }
    return ""
  }
}
