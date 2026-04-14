//
//  JoinCommunityView.swift
//  SkeenaSystem
//
//  Allows authenticated users to join an additional community
//  by entering a 6-character alphanumeric code.
//

import SwiftUI

struct JoinCommunityView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var code: String = ""
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var successText: String?

    private var isCodeValid: Bool {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^[A-Za-z0-9]{6}$"#, options: .regularExpression) != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {
                    Text("Enter a community code")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // Code input
                    TextField("Community Code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal)

                    if !code.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: isCodeValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(isCodeValid ? .green : .red)
                            Text(isCodeValid ? "Valid format" : "Must be 6 alphanumeric characters")
                                .font(.caption2)
                                .foregroundColor(isCodeValid ? .green : .red)
                        }
                    }

                    // Error / success messages
                    if let err = errorText {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    if let success = successText {
                        Text(success)
                            .foregroundColor(.green)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Join button
                    Button {
                        Task { await joinTapped() }
                    } label: {
                        HStack {
                            if isBusy { ProgressView().tint(.white) }
                            Text(isBusy ? "Joining..." : "Join Community")
                                .font(.headline.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isCodeValid && !isBusy ? Color.blue : Color.blue.opacity(0.4))
                        )
                        .foregroundColor(.white)
                        .padding(.horizontal)
                    }
                    .disabled(!isCodeValid || isBusy)

                    Spacer()
                }
                .padding(.top, 20)
            }
            .navigationTitle("Join Community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func joinTapped() async {
        errorText = nil
        successText = nil
        isBusy = true

        do {
            let result = try await CommunityService.shared.joinCommunity(code: code)
            successText = "Joined \(result.communityName ?? "community") as \(result.role ?? "member")!"
            // Brief delay before dismissing
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }

        isBusy = false
    }
}
