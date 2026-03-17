// Bend Fly Shop
// CatchDetailView.swift
import SwiftUI

struct CatchDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var auth: AuthService

  let report: CatchReportDTO

  @State private var isLoading = true
  @State private var errorText: String?
  @State private var story: CatchStoryDTO?

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // Story Title (from API; fall back to river while loading)
          Text(story?.title ?? report.river)
            .font(.title2.bold())
            .foregroundColor(.white)
            .padding(.top, 8)

          // Photo (already downloaded URL from the report)
          if let url = report.photoURL {
            AsyncImage(url: url) { phase in
              switch phase {
              case .empty:
                ZStack { Color.white.opacity(0.08); ProgressView() }
                  .frame(maxWidth: .infinity, minHeight: 220)
                  .clipShape(RoundedRectangle(cornerRadius: 14))
              case let .success(img):
                img.resizable()
                  .scaledToFill()
                  .frame(maxWidth: .infinity, minHeight: 220)
                  .clipShape(RoundedRectangle(cornerRadius: 14))
              case .failure:
                ZStack {
                  Color.white.opacity(0.08)
                  Image(systemName: "photo").font(.largeTitle)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14))
              @unknown default:
                Color.white.opacity(0.08)
                  .frame(maxWidth: .infinity, minHeight: 220)
                  .clipShape(RoundedRectangle(cornerRadius: 14))
              }
            }
          }

          // Summary / states
          Group {
            if isLoading {
              HStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("Generating story…")
                  .foregroundColor(.white.opacity(0.9))
                  .font(.subheadline)
              }
              .padding(.top, 4)
            } else if let err = errorText {
              Text(err)
                .foregroundColor(.red)
                .font(.subheadline)
            } else if let s = story {
              Text(s.summary)
                .foregroundColor(.white)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            } else {
              Text("No story available.")
                .foregroundColor(.gray)
                .font(.subheadline)
            }
          }
          .padding(.top, 4)

          // Metadata footer (optional, nice touch)
          VStack(alignment: .leading, spacing: 6) {
            Text(Self.fmtDate(report.createdAt))
              .font(.footnote)
              .foregroundColor(.gray)
            HStack(spacing: 6) {
              Image(systemName: "mappin.and.ellipse")
              Text(String(format: "%.4f, %.4f", report.latitude ?? 0, report.longitude ?? 0))
            }
            .font(.footnote)
            .foregroundColor(.gray)

            // Refresh button placed in the metadata area at the bottom
            Button(action: {
              Task { await refreshStory() }
            }) {
              Text("Refresh Story")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .disabled(isLoading)
            }
            .padding(.top, 12)
          }
          .padding(.top, 8)
        }
        .padding(16)
      }
    }
    // Show the navigation bar with a back button and title
    .navigationBarTitle("Detailed Catch Report", displayMode: .inline)
    .navigationBarBackButtonHidden(false)
    .navigationBarHidden(false) // explicitly unhide on this screen
    .task { await loadStory() }
    .preferredColorScheme(.dark)
  }

  // Load (cached if possible; otherwise request and cache)
  private func loadStory() async {
    isLoading = true
    errorText = nil
    do {
      let s = try await CatchStoryService.shared.fetchStoryWithCache(catchId: report.catch_id)
      withAnimation { self.story = s }
    } catch {
      self.errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
    isLoading = false
  }

  // Force-refresh from the server and persist the result
  private func refreshStory() async {
    isLoading = true
    errorText = nil
    do {
      let s = try await CatchStoryService.shared.fetchFreshStory(catchId: report.catch_id)
      withAnimation { self.story = s }
    } catch {
      self.errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
    isLoading = false
  }

  private static func fmtDate(_ iso: String) -> String {
    if let d = parseISO(iso) {
      let f = DateFormatter()
      f.dateStyle = .medium
      f.timeStyle = .short
      return f.string(from: d)
    }
    return iso
  }

  private static func parseISO(_ iso: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
  }
}
