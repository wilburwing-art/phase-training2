// PaywallView.swift — Pro subscription paywall.
//
// Presented from the Profile "Upgrade to Pro" row (and any future gated
// surface — coach bubble, coach consent toggle, etc.). Reads products
// from the injected SubscriptionStore and renders a per-product Subscribe
// button + a Restore action. Until App Store Connect products exist (the
// scaffold ships pre-setup), the view shows an honest "not configured"
// state instead of pretending. See SubscriptionStore.swift for setup
// steps.

import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var subStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var managingSubscriptions = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        hero
                        features
                        productList
                        legalFinePrint
                    }
                    .padding(20)
                    .padding(.bottom, 32)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.ink2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore") {
                        Task { await subStore.restore() }
                    }
                    .foregroundStyle(Color.accent)
                    .accessibilityIdentifier("paywall-restore")
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await subStore.refresh() }
        .manageSubscriptionsSheet(isPresented: $managingSubscriptions)
    }

    // MARK: - Pieces

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Two Kettles, two loops. The pair is the two-sport differentiator
            // made visual — an endurance loop beside the strength flex, which
            // is the range Pro plans across and what the copy below says.
            // Kettle's variation axis is motion, so the pair carries the idea
            // the old lean/swole builds did. Both loops run live; KettleView
            // falls back to a still under Reduce Motion.
            HStack(alignment: .bottom, spacing: 8) {
                KettleView(pose: .bike)
                    .frame(width: 76, height: 88)
                KettleView(pose: .flex)
                    .frame(width: 76, height: 88)
                Spacer(minLength: 0)
            }
            .accessibilityHidden(true)
            Text("Phase Training Pro")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.ink)
            // Copy claims are load-bearing: keep every line to something the
            // shipped code actually does. The old sentence promised "an AI
            // coach that personalizes every workout"; the generator discards
            // the coach's strategy on both paths, which is the same false
            // claim PlanStore+LLMRefinement disabled itself over.
            Text("Training that follows your season, and plans your primary sport around the second one you refuse to give up.")
                .font(.system(size: 15))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 10) {
            featureRow("Two-sport planning: your lifts flex around your climb and ski days")
            featureRow("Season-phase programming, from off-season base to event taper")
            featureRow("Chat coach that can shift your week or swap a lift")
            featureRow("Weekly coaching insights and recovery feedback")
        }
    }

    private func featureRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accent)
                .font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color.ink2)
            Spacer()
        }
    }

    @ViewBuilder
    private var productList: some View {
        if subStore.products.isEmpty {
            unconfiguredState
        } else {
            VStack(spacing: 8) {
                ForEach(subStore.products, id: \.id) { product in
                    productButton(product)
                }
            }
        }
    }

    private func productButton(_ product: Product) -> some View {
        Button {
            Task { await subStore.purchase(product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text(product.description)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ink3)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accent)
            }
            .padding(16)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentBorder, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(subStore.purchaseInFlight)
        .accessibilityIdentifier("paywall-buy-\(product.id)")
    }

    /// Build instructions belong in a debug build, not in front of a
    /// TestFlight tester who tapped Upgrade.
    static var unconfiguredMessage: String {
        #if DEBUG
        return "Subscriptions aren't set up for this build. Create the Pro product in App Store Connect, then update `SubscriptionStore.allProductIDs`. For local previews, add a StoreKit Configuration File to the scheme."
        #else
        return "Pro isn't available yet. Everything in the app is free in the meantime — nothing is locked."
        #endif
    }

    private var unconfiguredState: some View {
        VStack(alignment: .leading, spacing: 8) {
            // User-facing copy. This used to render build instructions —
            // "Create the Pro product in App Store Connect, then update
            // `SubscriptionStore.allProductIDs`" — to anyone who tapped
            // Upgrade, backticked Swift symbol and all. The developer version
            // now lives in the DEBUG branch below.
            Text("NOT AVAILABLE YET")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            Text(Self.unconfiguredMessage)
                .font(.system(size: 13))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("paywall-unconfigured")
    }

    private var legalFinePrint: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let err = subStore.lastError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") {
                    Task { await subStore.refresh() }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accent)
                .accessibilityIdentifier("paywall-retry")
            }
            Text("Auto-renews until cancelled.")
                .font(.system(size: 11))
                .foregroundStyle(Color.ink3)
                .fixedSize(horizontal: false, vertical: true)
            Button("Manage subscription") {
                managingSubscriptions = true
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.ink2)
            .accessibilityIdentifier("paywall-manage")
        }
    }
}

#Preview("Empty (not configured)") {
    PaywallView()
        .environmentObject(SubscriptionStore())
}
