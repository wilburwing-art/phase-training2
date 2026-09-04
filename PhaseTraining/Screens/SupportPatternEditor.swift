// SupportPatternEditor.swift — the reusable support-sport editing controls
// (primary/support model). Driven by a Binding<SupportPattern?> so both the
// Profile sheet (SupportSportEditorSheet) and onboarding
// (OnboardingSportSeasonsScreen) embed the same UI without duplication.
//
// Enable (None/Climbing) → discipline chips → 7-weekday × magnitude grid.
// Chip labels are load-bearing for SupportSportUITests — keep them stable.

import SwiftUI

struct SupportPatternEditor: View {
    @Binding var pattern: SupportPattern?
    /// Show the selling-point blurb above the controls (Profile sheet does;
    /// onboarding supplies its own section header instead).
    var showBlurb: Bool = true

    /// The wedge (v1): climbing support with an authored interference table.
    private let variants: [SportVariant] = [.sportRoute, .boulder, .tradAlpine]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showBlurb { blurb }
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
    }

    // MARK: - Sections

    private var blurb: some View {
        Text("Serious about two sports? Tell us your in-season sport's weekly rhythm and we'll build your primary sport's plan around it, so a hard climb day never lands under heavy legs.")
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

    // MARK: - Binding-derived state

    private var isEnabled: Bool { pattern != nil }
    private var currentVariant: SportVariant { pattern?.variant ?? .sportRoute }
    private var dayCount: Int { pattern?.days.count ?? 0 }
    private func magnitude(_ day: Weekday) -> SupportMagnitude? { pattern?.magnitude(on: day) }

    // MARK: - Writes

    private func setEnabled(_ on: Bool) {
        pattern = on
            ? SupportPattern(sportSlug: "climbing",
                             variant: pattern?.variant ?? .sportRoute,
                             days: pattern?.days ?? [])
            : nil
    }

    private func setVariant(_ v: SportVariant) {
        pattern = SupportPattern(sportSlug: "climbing", variant: v, days: pattern?.days ?? [])
    }

    private func setMagnitude(_ day: Weekday, _ mag: SupportMagnitude?) {
        var days = pattern?.days ?? []
        days.removeAll { $0.weekday == day }
        if let mag { days.append(SupportDay(weekday: day, magnitude: mag)) }
        pattern = SupportPattern(sportSlug: "climbing",
                                 variant: pattern?.variant ?? .sportRoute, days: days)
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
