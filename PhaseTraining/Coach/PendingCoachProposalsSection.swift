// PendingCoachProposalsSection.swift — coach changes waiting on the user,
// shown on the Complete screen (voice 3.3).
//
// A voice turn mid-workout cannot show an Apply button, so its proposal stays
// pending in today's thread. This section lists the turns that were pending
// when the screen opened, through the same mini cards the drawer uses, so
// Apply goes through the same by-id seams (`MiniPlanDiffCard.apply()` and
// siblings). The id list is captured once so a card that was just applied or
// rejected stays on screen showing its new status.

import SwiftUI

struct PendingCoachProposalsSection: View {
    @EnvironmentObject private var conv: CoachConversationStore
    @State private var shownIds: [UUID]? = nil

    var body: some View {
        let ids = shownIds ?? conv.pendingProposalMessages.map(\.id)
        let messages = ids.compactMap { id in conv.messages.first(where: { $0.id == id }) }
        Group {
            if !messages.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .scaledSystemFont(13)
                            .foregroundStyle(Color.accent)
                        Text("STAGED BY YOUR COACH")
                            .styled(.micro)
                            .foregroundStyle(Color.accent)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    ForEach(messages) { message in
                        cards(for: message)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .accessibilityIdentifier("complete-pending-coach-proposals")
            }
        }
        .onAppear {
            if shownIds == nil { shownIds = conv.pendingProposalMessages.map(\.id) }
        }
    }

    @ViewBuilder
    private func cards(for message: CoachMessage) -> some View {
        if let proposal = message.proposal {
            MiniPlanDiffCard(messageId: message.id, proposal: proposal)
        }
        if let workoutProposal = message.workoutProposal {
            MiniWorkoutDiffCard(messageId: message.id, proposal: workoutProposal)
        }
        if let memoryProposal = message.memoryProposal {
            MiniMemoryDiffCard(messageId: message.id, proposal: memoryProposal)
        }
    }
}
