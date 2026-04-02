//
//  CommunitySwitcherView.swift
//  SkeenaSystem
//
//  A compact community switcher shown as a sheet or inline menu.
//  Displays all communities the user belongs to with their role,
//  and allows switching + joining new communities.
//

import SwiftUI

// MARK: - Toolbar button that shows the switcher sheet

struct CommunityToolbarButton: View {
    @StateObject private var communityService = CommunityService.shared
    @State private var showSwitcher = false

    var body: some View {
        Button {
            showSwitcher = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.3")
                    .font(.subheadline)
                Text(communityService.activeCommunityName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black, in: Capsule())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSwitcher) {
            CommunitySwitcherSheet()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Chevron-only toolbar button (no community name)

/// A minimal community switcher button that shows only a dropdown chevron.
/// Used when the community name is already visible elsewhere on the page.
struct CommunitySwitcherChevron: View {
    @State private var showSwitcher = false

    var body: some View {
        Button {
            showSwitcher = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.3")
                    .font(.subheadline)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSwitcher) {
            CommunitySwitcherSheet()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Full switcher sheet

struct CommunitySwitcherSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var communityService = CommunityService.shared
    @State private var showJoinCommunity = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(communityService.memberships) { membership in
                            let isActive = membership.communityId == communityService.activeCommunityId
                            Button {
                                communityService.setActiveCommunity(id: membership.communityId)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(membership.communities.name)
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        Text(membership.role.capitalized)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                    if isActive {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(isActive ? Color.blue.opacity(0.15) : Color.white.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(isActive ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        // Update default community (only relevant with multiple communities)
                        if communityService.hasMultipleCommunities {
                            Button {
                                communityService.clearActiveCommunity()
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "star.circle")
                                    Text("Update Default Community")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }

                        // Join a community
                        Button {
                            showJoinCommunity = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text(communityService.hasMultipleCommunities ? "Join Another Community" : "Join a Community")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                }
            }
            .navigationTitle("Switch Community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .sheet(isPresented: $showJoinCommunity) {
                JoinCommunityView()
            }
        }
    }
}
