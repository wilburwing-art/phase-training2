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
    }

    // MARK: - Pieces

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accent)
                Text("Phase Training Pro")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.ink)
            }
            Text("Unlock the AI coach that personalizes each workout to your recent sessions, soreness, and sport goals.")
                .font(.system(size: 15))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 10) {
            featureRow("Personalized workout polish on every plan generation")
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

    private var unconfiguredState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRO IS NOT YET CONFIGURED")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            Text("Subscriptions aren't set up for this build. Create the Pro product in App Store Connect, then update `SubscriptionStore.allProductIDs`. For local previews, add a StoreKit Configuration File to the scheme.")
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
            }
            Text("Auto-renews until cancelled. Manage in Settings → Apple ID → Subscriptions.")
                .font(.system(size: 11))
                .foregroundStyle(Color.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Empty (not configured)") {
    PaywallView()
        .environmentObject(SubscriptionStore())
}
