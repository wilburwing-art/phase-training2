// SupportSportEditorSheet.swift — declare the SUPPORT sport's weekly load
// (primary/support model, PLAN-primary-support.md phase 2 UI).
//
// The primary sport keeps its periodized plan (Seasons editor). The SUPPORT
// sport is in-season and gets no plan — the user just declares which days they
// do it and how hard (light/medium/big). The planner then reflows the primary
// lift week AROUND those days. This is the app's launch differentiator, so the
// copy states it plainly.
//
// Fully store-derived (no local @State) like SeasonsEditorSheet: every control
// reads memory.supportPattern and writes it back through store.update — the
// SupportPattern initializer dedupes/sorts, so days can be built naively.

import SwiftUI

struct SupportSportEditorSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss

    /// The wedge (v1): climbing support with an authored interference table.
    private let variants: [SportVariant] = [.sportRoute, .boulder, .tradAlpine]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        blurb
                        sectionLabel("SUPPORT SPORT")
                        enableChips
                        if isEnabled {
                            sectionLabel("DISCIPLINE").padding(.top, 4)
                            disciplineChips
                            sectionLabel("WHICH DAYS — AND HOW HARD").padding(.top, 4)
                            ForEach(Weekday.allCases) { day in dayRow(day) }
                            footerHint.padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Support Sport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var blurb: some View {
        Text("Serious about two sports? Tell us your in-season sport's weekly rhythm and we'll build your primary sport's plan around it — no more burying a hard climb day under heavy legs.")
            .font(.custom("Inter-Regular", size: 13))
            .foregroundStyle(Color.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var enableChips: some View {
        WrappingFlow(spacing: 6) {
            OnboardingChip(label: "None", selected: !isEnabled, action: { setEnabled(false) })
            OnboardingChip(label: "Climbing", selected: isEnabled, action: { setEnabled(true) })
        }
    }

    private var disciplineChips: some View {
        WrappingFlow(spacing: 6) {
            ForEach(variants, id: \.self) { v in
                OnboardingChip(label: variantLabel(v), selected: currentVariant == v,
                               action: { setVariant(v) })
            }
        }
    }

    private func dayRow(_ day: Weekday) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(day.short)
                .font(.custom("SpaceGrotesk-Medium", size: 13))
                .foregroundStyle(Color.ink)
                .frame(width: 34, alignment: .leading)
            WrappingFlow(spacing: 6) {
                OnboardingChip(label: "—", selected: magnitude(day) == nil,
                               action: { setMagnitude(day, nil) })
                ForEach(SupportMagnitude.allCases, id: \.self) { mag in
                    OnboardingChip(label: mag.label, selected: magnitude(day) == mag,
                                   action: { setMagnitude(day, mag) })
                }
            }
        }
    }

    private var footerHint: some View {
        Text(dayCount == 0
             ? "Pick at least one day to activate the reflow."
             : "\(dayCount) \(dayCount == 1 ? "day" : "days") set. Your primary plan will shift heavy sessions away from big days and trim volume when the combined load is high.")
            .font(.custom("Inter-Regular", size: 12))
            .foregroundStyle(Color.ink3)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Store-derived state

    private var isEnabled: Bool { store.memory.supportPattern != nil }
    private var currentVariant: SportVariant { store.memory.supportPattern?.variant ?? .sportRoute }
    private var dayCount: Int { store.memory.supportPattern?.days.count ?? 0 }
    private func magnitude(_ day: Weekday) -> SupportMagnitude? {
        store.memory.supportPattern?.magnitude(on: day)
    }

    // MARK: - Writes

    private func setEnabled(_ on: Bool) {
        store.update { mem in
            mem.supportPattern = on
                ? SupportPattern(sportSlug: "climbing",
                                 variant: mem.supportPattern?.variant ?? .sportRoute,
                                 days: mem.supportPattern?.days ?? [])
                : nil
        }
    }

    private func setVariant(_ v: SportVariant) {
        store.update { mem in
            mem.supportPattern = SupportPattern(
                sportSlug: "climbing", variant: v,
                days: mem.supportPattern?.days ?? [])
        }
    }

    private func setMagnitude(_ day: Weekday, _ mag: SupportMagnitude?) {
        store.update { mem in
            var days = mem.supportPattern?.days ?? []
            days.removeAll { $0.weekday == day }
            if let mag { days.append(SupportDay(weekday: day, magnitude: mag)) }
            mem.supportPattern = SupportPattern(
                sportSlug: "climbing",
                variant: mem.supportPattern?.variant ?? .sportRoute,
                days: days)
        }
    }

    // MARK: - Labels

    private func variantLabel(_ v: SportVariant) -> String {
        switch v {
        case .sportRoute: return "Sport / Route"
        case .boulder:    return "Bouldering"
        case .tradAlpine: return "Trad / Alpine"
        default:          return v.rawValue
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).styled(.micro).foregroundStyle(Color.ink3)
    }
}
