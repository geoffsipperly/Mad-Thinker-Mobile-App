// Bend Fly Shop

// CommunityForumView.swift
import SwiftUI

struct CommunityForumView: View {
  @EnvironmentObject private var auth: AuthService
  @Environment(\.dismiss) private var dismiss
  @State private var categories: [ForumCategory] = []
  @State private var isLoading = false
  @State private var error: String?

  var body: some View {
    DarkPageTemplate(bottomToolbar: {
      RoleAwareToolbar(activeTab: "community")
    }) {
      ScrollView {
        VStack(spacing: 18) {
          AppHeader()
            .padding(.bottom, 10)

          if isLoading {
            ProgressView().tint(.white).padding()
          } else if let error {
            VStack(spacing: 12) {
              Text(error).foregroundColor(.white)
              Button("Retry") { Task { await load() } }
                .buttonStyle(.borderedProminent)
            }
          } else {
            VStack(spacing: 14) {
              ForEach(categories) { cat in
                NavigationLink {
                  ThreadsListView(category: cat)
                } label: {
                  categoryRow(cat)
                }
                .buttonStyle(.plain)
              }
            }
            .padding(.horizontal, 16)
          }

          Spacer()
        }
      }
    }
    .navigationTitle("Community forum")
    .navigationBarBackButtonHidden(true)
    .task { await load() }
    .onAppear {
      AppLogging.log("[CommunityForumView] onAppear; authId=\(ObjectIdentifier(auth).hashValue)", level: .debug, category: .forum)
    }
    .onDisappear {
      AppLogging.log("[CommunityForumView] onDisappear", level: .debug, category: .forum)
    }

  }

  private func load() async {
    error = nil; isLoading = true
    do { categories = try await ForumAPI.fetchCategories() } catch { self.error = error.localizedDescription }
    isLoading = false
  }

  private func categoryRow(_ cat: ForumCategory) -> some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(cat.name)
          .font(.headline)
          .foregroundColor(.blue)
        if let desc = cat.description, !desc.isEmpty {
          Text(desc)
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.7))
            .lineLimit(2)
        }
      }
      Spacer()
      Image(systemName: "chevron.right")
        .foregroundColor(.white.opacity(0.6))
        .font(.subheadline.weight(.semibold))
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 12)
    .background(Color.white.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
  }
}
