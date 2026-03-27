//
//  CommunityPickerView.swift
//  SkeenaSystem
//
//  Shown when a user belongs to multiple communities and needs to select
//  which one to work in. Each community is displayed as a tappable logo tile.
//  After selection, the app routes to the appropriate landing view based on
//  their role in that community.
//

import SwiftUI

struct CommunityPickerView: View {
    @StateObject private var communityService = CommunityService.shared
    @StateObject private var auth = AuthService.shared
    @State private var showJoinCommunity = false

    private let columns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20)
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                // Logout button — upper right
                HStack {
                    Spacer()
                    Button(action: logoutTapped) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .font(.title3.weight(.semibold))
                            Text("Log out")
                                .font(.footnote.weight(.semibold))
                        }
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("logoutCapsule")
                }
                .padding(.horizontal, 20)

                // Platform branding
                Image("MadThinkerLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text("Select Your Community")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)

                // Community grid
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(communityService.memberships) { membership in
                        Button {
                            communityService.setActiveCommunity(id: membership.communityId)
                        } label: {
                            communityTile(membership: membership)
                        }
                        .buttonStyle(.plain)
                    }

                    // Join another community tile
                    Button {
                        showJoinCommunity = true
                    } label: {
                        joinCommunityTile
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.top, 40)
        }
        .sheet(isPresented: $showJoinCommunity) {
            JoinCommunityView()
        }
    }

    // MARK: - Community Tile

    private func communityTile(membership: CommunityMembership) -> some View {
        VStack(spacing: 10) {
            // Name area — fixed height so role badges align across tiles
            Text(membership.communities.name)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 40, alignment: .bottom)

            Text(membership.role.capitalized)
                .font(.caption2.weight(.medium))
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.85), in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Logout

    private func logoutTapped() {
        Task {
            await auth.signOutRemote()
            await MainActor.run {
                AuthStore.shared.clear()
            }
        }
    }

    // MARK: - Join Community Tile

    private var joinCommunityTile: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.title2)
                .foregroundColor(.blue)

            Text("Join Community")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.blue)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.blue.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [6]))
                .background(Color.blue.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        )
    }
}
