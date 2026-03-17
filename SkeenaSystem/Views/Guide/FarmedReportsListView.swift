// Bend Fly Shop

import SwiftUI

// MARK: - View

struct FarmedReportsListView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var store = FarmedReportStore.shared

  // Upload state
  @State private var isUploading = false
  @State private var uploadProgress: Double = 0.0
  @State private var uploadErrorMessage: String?
  @State private var showErrorAlert = false

  private let uploader = UploadFarmedReports()

  private var pendingReports: [FarmedReport] {
    store.reports.filter { $0.status == .savedLocally }
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 0) {
        // Content
        ZStack(alignment: .bottom) {
          if store.reports.isEmpty {
            VStack {
              Text("No farmed reports yet.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding()
              Spacer()
            }
          } else {
            List {
              ForEach(store.reports) { report in
                FarmedReportRow(report: report)
                  .listRowBackground(Color.black)
              }
              .onDelete { offsets in
                deleteReports(at: offsets)
              }
            }
            .listStyle(.plain)
            .background(Color.black)
            .modifier(FarmedHideListBackground())
          }

          // Upload progress overlay
          if isUploading {
            VStack(spacing: 8) {
              ProgressView(value: uploadProgress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle())
                .padding(.horizontal)
              Text("Uploading farmed reports… \(Int(uploadProgress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(.ultraThinMaterial)
          }
        }
        .frame(maxHeight: .infinity)
      }
    }
    .navigationTitle("Farmed Reports")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(true)
    .toolbar {
      ToolbarItem(placement: .navigationBarLeading) {
        Button {
          dismiss()
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "chevron.left")
            Text("Back")
          }
        }
      }
      ToolbarItem(placement: .navigationBarTrailing) {
        Button(action: startUpload) {
          HStack(spacing: 4) {
            Image(systemName: "arrow.up.circle")
            Text("Upload")
          }
        }
        .disabled(isUploading || pendingReports.isEmpty)
      }
    }
    .environment(\.colorScheme, .dark)
    .onAppear {
      store.purgeOldUploaded()
      store.refresh()
    }
    .alert("Upload Error", isPresented: $showErrorAlert) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(uploadErrorMessage ?? "Unknown error")
    }
  }

  // MARK: - Delete

  private func deleteReports(at offsets: IndexSet) {
    for index in offsets {
      let report = store.reports[index]
      // Only allow deleting reports that are saved locally (not yet uploaded)
      if report.status == .savedLocally {
        store.delete(report)
      }
    }
  }

  // MARK: - Upload

  private func startUpload() {
    guard !pendingReports.isEmpty else { return }

    isUploading = true
    uploadProgress = 0
    uploadErrorMessage = nil

    Task {
      await AuthStore.shared.refreshFromSupabase()

      guard let jwt = AuthStore.shared.jwt, !jwt.isEmpty else {
        await MainActor.run {
          self.isUploading = false
          self.uploadErrorMessage = "You must be signed in to upload farmed reports."
          self.showErrorAlert = true
        }
        return
      }

      _ = jwt

      uploader.upload(
        reports: pendingReports,
        progress: { progress in
          DispatchQueue.main.async {
            self.uploadProgress = progress
          }
        },
        completion: { result in
          DispatchQueue.main.async {
            self.isUploading = false

            switch result {
            case let .success(uploadedIDs):
              FarmedReportStore.shared.markUploaded(uploadedIDs)
              self.store.refresh()
            case let .failure(error):
              self.uploadErrorMessage = error.localizedDescription
              self.showErrorAlert = true
            }
          }
        }
      )
    }
  }
}

// MARK: - Row

private struct FarmedReportRow: View {
  let report: FarmedReport

  private static let timestampFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .short
    return df
  }()

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(Self.timestampFormatter.string(from: report.createdAt))
          .font(.headline)
          .foregroundColor(.white)
          .lineLimit(1)

        Spacer()
        FarmedStatusChip(status: report.status)
      }

      if let lat = report.lat, let lon = report.lon {
        Text("GPS: \(String(format: "%.5f", lat)), \(String(format: "%.5f", lon))")
          .font(.footnote)
          .foregroundColor(.secondary)
          .lineLimit(1)
      } else {
        Text("GPS: —")
          .font(.footnote)
          .foregroundColor(.secondary)
      }

      Text("Guide: \(report.guideName)")
        .font(.footnote)
        .foregroundColor(.secondary)
        .lineLimit(1)

      if let angler = report.anglerNumber, !angler.isEmpty {
        Text("Angler: \(angler)")
          .font(.footnote)
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
    }
    .listRowBackground(Color.black)
    .deleteDisabled(report.status != .savedLocally)
  }
}

// MARK: - Status chip

private struct FarmedStatusChip: View {
  let status: FarmedReportStatus

  var body: some View {
    Text(status.rawValue)
      .font(.caption2)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(background)
      .foregroundColor(foreground)
      .clipShape(Capsule())
  }

  private var background: Color {
    switch status {
    case .savedLocally: return Color.blue.opacity(0.12)
    case .uploaded: return Color.green.opacity(0.12)
    }
  }

  private var foreground: Color {
    switch status {
    case .savedLocally: return .blue
    case .uploaded: return .green
    }
  }
}

// MARK: - List background helper

private struct FarmedHideListBackground: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.0, *) {
      content.scrollContentBackground(.hidden)
    } else {
      content
    }
  }
}
