//
//  InactiveMemberView.swift
//  SkeenaSystem
//
//  Shown when the current user's membership in the active community
//  has been deactivated by a guide or admin.
//

import SwiftUI

struct InactiveMemberView: View {
    @StateObject private var communityService = CommunityService.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "person.crop.circle.badge.minus")
                    .font(.system(size: 56))
                    .foregroundColor(.orange)

                Text("Membership Inactive")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text("Your membership in **\(communityService.activeCommunityName)** is currently inactive. Please contact your guide or lodge administrator to restore access.")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if communityService.hasMultipleCommunities {
                    Button {
                        communityService.clearActiveCommunity()
                    } label: {
                        Text("Switch Community")
                            .font(.headline)
                            .foregroundColor(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .cornerRadius(10)
                    }
                }

                Button {
                    Task {
                        await communityService.fetchMemberships()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
        }
    }
}
