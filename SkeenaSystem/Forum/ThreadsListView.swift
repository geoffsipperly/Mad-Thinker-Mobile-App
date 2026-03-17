// Bend Fly Shop

// ThreadsListView.swift
import SwiftUI

struct ThreadsListView: View {
  let category: ForumCategory
  @EnvironmentObject private var auth: AuthService

  @State private var threads: [ForumThread] = []
  @State private var isLoading = false
  @State private var error: String?
  @State private var showCreate = false
  @State private var showAll = false

  private var displayedThreads: [ForumThread] {
    showAll ? threads : Array(threads.prefix(5))
  }

  private var hasMore: Bool { threads.count > 5 }

  var body: some View {
    ZStack { Color.black.ignoresSafeArea()
      VStack(spacing: 0) {
        // --- Bend Fly Shop Header ---
        VStack(spacing: 6) {
          Spacer().frame(height: 12)
          Image(AppEnvironment.shared.appLogoAsset)
            .resizable().scaledToFit()
            .frame(width: 130, height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(radius: 10)
            .padding(.bottom, 2)
        }
        .padding(.bottom, 10)

        Group {
          if isLoading {
            ProgressView().tint(.white).padding()
          } else if let error {
            Text(error).foregroundColor(.white).padding()
          } else if threads.isEmpty {
            Text("No threads yet. Be the first to post!")
              .foregroundColor(.white.opacity(0.8)).padding()
          } else {
            List {
              ForEach(displayedThreads) { t in
                NavigationLink {
                  ThreadDetailView(thread: t, categoryName: category.name)
                    .environmentObject(auth)
                } label: {
                  VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                      if t.is_pinned == true { Image(systemName: "pin.fill") }
                      Text(t.title).font(.headline)
                    }
                    .foregroundColor(.white)
                    HStack(spacing: 8) {
                      Text(authorName(for: t))
                      if let when = t.created_at { Text("• \(absoluteDate(when))") }
                    }
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
                  }
                  .padding(.vertical, 6)
                }
                .listRowBackground(Color.white.opacity(0.06))
              }

              if hasMore, !showAll {
                Button { withAnimation { showAll = true } } label: {
                  HStack {
                    Spacer()
                    Text("Show more threads…")
                      .font(.footnote.weight(.semibold))
                      .foregroundColor(.white)
                      .padding(.horizontal, 12)
                      .padding(.vertical, 8)
                      .background(Color.white.opacity(0.10))
                      .clipShape(RoundedRectangle(cornerRadius: 10))
                    Spacer()
                  }
                }
                .listRowBackground(Color.clear)
              }
            }
            .listStyle(.plain)
            .scrollContentBackgroundHiddenCompat()
            .refreshable { await load() }
          }
        }
      }
    }
    .navigationTitle(category.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          showCreate = true
        } label: {
          Image(systemName: "square.and.pencil")
            .font(.body.weight(.semibold))
        }
        .disabled(!auth.isAuthenticated)
        .accessibilityLabel("Create Thread")
      }
    }
    .task { await load() }
    .fullScreenCover(isPresented: $showCreate, onDismiss: {
      AppLogging.log("[ThreadsListView] fullScreenCover dismissed. Triggering reload.", level: .debug, category: .forum)
      Task { await load() }
    }) {
      CreateThreadView(categoryId: category.id, categoryName: category.name)
        .environmentObject(auth)
    }

    .onAppear {
      AppLogging.log("[ThreadsListView] onAppear; showCreate=\(showCreate)", level: .debug, category: .forum)
    }
    .onDisappear {
      AppLogging.log("[ThreadsListView] onDisappear", level: .debug, category: .forum)
    }
    .onChange(of: showCreate) { newValue in
      AppLogging.log("[ThreadsListView] showCreate -> \(newValue)", level: .debug, category: .forum)
    }
  }

  private func load() async {
    AppLogging.log("[ThreadsListView] load() begin. categoryId=\(category.id), name=\(category.name)", level: .debug, category: .forum)
    error = nil; isLoading = true
    defer { isLoading = false }
    do {
      let fetched = try await ForumAPI.fetchThreads(categoryId: category.id)
      AppLogging.log("[ThreadsListView] load() fetched count=\(fetched.count)", level: .debug, category: .forum)
      
      let sampleCount = min(3, fetched.count)
      if sampleCount > 0 {
        let samples = fetched.prefix(sampleCount).map { t in
          let fn = t.author_first_name ?? ""
          let ln = t.author_last_name ?? ""
          let name = "\(fn) \(ln)".trimmingCharacters(in: .whitespaces)
          let display = name.isEmpty ? "(empty -> Anonymous)" : name
          return "{id=\(t.id), title=\(t.title), author=\(display)}"
        }.joined(separator: ", ")
        AppLogging.log("[ThreadsListView] load() samples: [\(samples)]", level: .debug, category: .forum)
      }
      threads = fetched; showAll = false
      
      let anonymous = threads.filter {
        let fn = $0.author_first_name ?? ""
        let ln = $0.author_last_name ?? ""
        return fn.isEmpty && ln.isEmpty
      }
      if !anonymous.isEmpty {
        let ids = anonymous.prefix(5).map { $0.id }.joined(separator: ", ")
        AppLogging.log("[ThreadsListView] anonymous-author threads count=\(anonymous.count) sampleIds=[\(ids)]", level: .debug, category: .forum)
      }
      
      AppLogging.log("[ThreadsListView] load() complete. threads=\(threads.count), showAll=\(showAll)", level: .debug, category: .forum)
    } catch { self.error = error.localizedDescription }
  }

  private func authorName(for thread: ForumThread) -> String {
    let fn = thread.author_first_name ?? ""
    let ln = thread.author_last_name ?? ""
    let both = "\(fn) \(ln)".trimmingCharacters(in: .whitespaces)
    return both.isEmpty ? "Anonymous" : both
  }

  private func relative(_ iso: String) -> String {
    ISO8601DateFormatter().date(from: iso)
      .map { RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: .now) }
      ?? ""
  }

  private func parseISO8601(_ iso: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: iso)
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
