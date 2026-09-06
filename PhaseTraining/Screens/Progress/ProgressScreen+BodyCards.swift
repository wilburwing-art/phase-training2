// ProgressScreen+BodyCards.swift — body-centric cards.
//
// Split out of ProgressScreen.swift (architecture item 9, pure move): the
// body-weight trend, body-composition trend, strength-ratios (1RM vs.
// bodyweight), and muscle-balance cards. The two sheet-toggle @State vars
// these cards drive live on the struct in ProgressScreen.swift (stored
// properties can't live in an extension). Card-entry vars are internal
// (referenced from `content` in the main file); everything else stays
// private to this file.

import SwiftUI

extension ProgressScreen {

    // MARK: - Body-weight trend (build 103)
    //
    // The TrainingMemory.bodyWeightLog series surfaces here as a compact
    // sparkline + delta read-out. Tapping the card opens
    // BodyWeightLogSheet for a richer log + chart. Hidden entirely when
    // the user has never logged a weight — empty state would just be
    // noise on Progress. Mirrors the volume card's hand-drawn LineSpark
    // for consistency with the rest of the screen.

    var bodyWeightTrendCard: some View {
        let log = memoryStore.memory.bodyWeightLog.sorted { $0.date < $1.date }
        return Group {
            if log.isEmpty {
                EmptyView()
            } else {
                Button { presentingBodyWeightSheet = true } label: {
                    bodyWeightCardBody(log: log)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("progress-body-weight-card")
                .sheet(isPresented: $presentingBodyWeightSheet) {
                    BodyWeightLogSheet().environmentObject(memoryStore)
                }
            }
        }
    }

    private func bodyWeightCardBody(log: [BodyWeightEntry]) -> some View {
        let imperial = memoryStore.memory.usesImperial
        let displaySeries = log.map { imperial ? BodyMetrics.kgToLb($0.weightKg) : $0.weightKg }
        let latest = ProgressStats.latestBodyWeightKg(in: log) ?? 0
        let latestDisplay = BodyMetrics.formatWeight(kg: latest, imperial: imperial)
        let deltaStr: String? = ProgressStats.bodyWeightDeltaKg(in: log).map { dKg in
            let absDisplay = abs(imperial ? BodyMetrics.kgToLb(dKg) : dKg)
            let sign = dKg >= 0 ? "+" : "−"
            return String(format: "%@%.1f", sign, absDisplay)
        }
        // Pass the true min/max; the spark centers a flat series itself
        // (no dimMax-1 hack that pinned an all-equal line to the top edge).
        let dimMax = displaySeries.max() ?? 1
        let dimMin = displaySeries.min() ?? 0
        return card(title: "BODY WEIGHT") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(latestDisplay)
                        .font(.custom("JetBrainsMono-SemiBold", size: 22))
                        .foregroundStyle(Color.ink)
                    if let deltaStr {
                        Text(deltaStr)
                            .font(.monoXS)
                            .foregroundStyle(deltaColor(log: log))
                    }
                    Spacer()
                    Text("\(log.count) entr\(log.count == 1 ? "y" : "ies")")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
                BodyWeightSpark(points: displaySeries, minValue: dimMin, maxValue: dimMax)
                    .frame(height: 50)
                Text("Tap to add a new weight.")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
        }
    }

    private func deltaColor(log: [BodyWeightEntry]) -> Color {
        guard let delta = ProgressStats.bodyWeightDeltaKg(in: log) else { return .ink3 }
        return delta >= 0 ? .accent : .ok
    }

    // MARK: - Body-composition trend (build 103)
    //
    // Symmetric with bodyWeightTrendCard but for BF% + lean mass. Each
    // series is optional per entry — DEXA users log both, scale users
    // log just BF% — so the card renders whichever sparklines have data.
    // Hidden entirely when the user has never logged a composition reading.

    var bodyCompositionTrendCard: some View {
        let log = memoryStore.memory.bodyCompositionLog.sorted { $0.date < $1.date }
        return Group {
            if log.isEmpty {
                EmptyView()
            } else {
                Button { presentingBodyCompositionSheet = true } label: {
                    bodyCompositionCardBody(log: log)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("progress-body-composition-card")
                .sheet(isPresented: $presentingBodyCompositionSheet) {
                    BodyCompositionLogSheet().environmentObject(memoryStore)
                }
            }
        }
    }

    private func bodyCompositionCardBody(log: [BodyCompositionEntry]) -> some View {
        let imperial = memoryStore.memory.usesImperial
        // Series, latest-per-metric and deltas all live in ProgressStats so
        // they can be tested — notably the most-recent NON-NIL rule, which
        // keeps a newest lean-only (or BF-only) entry from blanking the other
        // stat while its sparkline still renders from the full series.
        let bfSeries = ProgressStats.bodyFatSeries(in: log)
        let leanSeries = ProgressStats.leanMassSeries(in: log, imperial: imperial)
        let latestBF = ProgressStats.latestBodyFatPercent(in: log)
        let latestLean = ProgressStats.latestLeanMassKg(in: log)
        let bfDelta = ProgressStats.trendDelta(bfSeries)
        let leanDelta = ProgressStats.trendDelta(leanSeries)

        return card(title: "BODY COMPOSITION") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    if let bf = latestBF {
                        statBlock(
                            label: "BF",
                            value: String(format: "%.1f%%", bf),
                            delta: bfDelta.map { String(format: "%@%.1f", $0 >= 0 ? "+" : "−", abs($0)) },
                            tint: bfDelta.map { $0 < 0 ? Color.ok : Color.accent } ?? .ink3
                        )
                    }
                    if let lean = latestLean {
                        let displayLean = imperial ? BodyMetrics.kgToLb(lean) : lean
                        statBlock(
                            label: "LEAN",
                            value: String(format: "%.0f %@", displayLean, imperial ? "lb" : "kg"),
                            delta: leanDelta.map { String(format: "%@%.1f", $0 >= 0 ? "+" : "−", abs($0)) },
                            tint: leanDelta.map { $0 >= 0 ? Color.ok : Color.danger } ?? .ink3
                        )
                    }
                    Spacer()
                    Text("\(log.count) reading\(log.count == 1 ? "" : "s")")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
                if bfSeries.count >= 2 {
                    miniSeries(label: "BF %", values: bfSeries)
                }
                if leanSeries.count >= 2 {
                    miniSeries(label: imperial ? "LEAN LB" : "LEAN KG", values: leanSeries)
                }
                Text("Tap to log a new reading.")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
        }
    }

    private func statBlock(label: String, value: String, delta: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.custom("JetBrainsMono-SemiBold", size: 18))
                    .foregroundStyle(Color.ink)
                if let delta {
                    Text(delta)
                        .font(.monoXS)
                        .foregroundStyle(tint)
                }
            }
        }
        // One element: label, value, then the delta with its sign spoken.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.capitalized), \(value)\(delta.map { ", change \($0)" } ?? "")")
    }

    private func miniSeries(label: String, values: [Double]) -> some View {
        let maxV = values.max() ?? 1
        let minV = values.min() ?? 0
        return HStack(spacing: 8) {
            Text(label)
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
                .frame(width: 56, alignment: .leading)
            BodyWeightSpark(points: values, minValue: minV, maxValue: maxV)
                .frame(height: 24)
        }
    }

    // MARK: - Strength ratios card

    var strengthRatiosCard: some View {
        // Memoized (item 8): StrengthStandards.rows is the screen's heaviest
        // walk. bodyweightKg + gender are part of the aggregates cache key,
        // so a profile edit recomputes on the next render.
        let rows = aggregates.strengthRows
        return Group {
            if memoryStore.memory.weightKg == nil {
                // Don't show the card at all without bodyweight — the entire
                // value-prop is the ratio, which is undefined without it.
                EmptyView()
            } else if rows.isEmpty {
                card(title: "STRENGTH RATIOS") {
                    Text("Log Bench, Squat, Deadlift, OHP, or Pull-Up to see ratios.")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            } else {
                card(title: "STRENGTH RATIOS") {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                            strengthRow(row)
                            if idx < rows.count - 1 {
                                Rectangle()
                                    .fill(Color.lineSoft)
                                    .frame(height: 0.5)
                            }
                        }
                    }
                    // Tiers render as bare authoritative words ("ELITE"), but
                    // StrengthStandards.swift:14 says they're "a directional
                    // signal, not a diagnosis" — say so where the user reads
                    // them. And .nonbinary / .preferNotToSay are routed to the
                    // female curve, which the card must not do silently while
                    // telling the user that gender is what unlocks the label.
                    Text(tierDisclosure)
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
            }
        }
    }

    /// What the tier labels mean, and which curve produced them. Copy lives
    /// in ProgressStats so it can be tested against the routing it describes
    /// (StrengthStandards.curve(for:)) — see ProgressGenderDisclosureTests.
    private var tierDisclosure: String {
        ProgressStats.strengthTierDisclosure(gender: memoryStore.memory.gender)
    }

    private func strengthRow(_ row: StrengthStandards.LiftRow) -> some View {
        let imperial = memoryStore.memory.usesImperial
        let oneRmDisplay = imperial
            ? "\(Int(row.oneRepMaxLb.rounded())) lb"
            : "\(Int(BodyMetrics.lbToKg(row.oneRepMaxLb).rounded())) kg"
        let bestDisplay = imperial
            ? "\(Int(row.bestWeightLb.rounded())) × \(row.bestReps)"
            : "\(Int(BodyMetrics.lbToKg(row.bestWeightLb).rounded())) × \(row.bestReps)"
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.lift.label)
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Text("est 1RM \(oneRmDisplay) · from \(bestDisplay)")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%.2f× BW", row.ratio))
                    .font(.custom("JetBrainsMono-SemiBold", size: 14))
                    .foregroundStyle(Color.accent)
                if let tier = row.tier {
                    Text(tier.label)
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                }
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Muscle balance card

    var muscleBalanceCard: some View {
        let rows = aggregates.muscleRows
        return Group {
            if rows.isEmpty {
                // Skip entirely — empty card would just be noise.
                EmptyView()
            } else {
                card(title: "MUSCLE BALANCE · 4w") {
                    let maxVol = rows.first?.volume ?? 1
                    VStack(spacing: 8) {
                        ForEach(rows) { row in
                            muscleBar(row: row, maxVol: maxVol)
                        }
                    }
                }
            }
        }
    }

    private func muscleBar(row: MuscleVolume.Row, maxVol: Double) -> some View {
        HStack(spacing: 10) {
            Text(row.label)
                .font(.monoXS)
                .foregroundStyle(Color.ink2)
                .frame(width: 92, alignment: .leading)
                .lineLimit(1)
            GeometryReader { geo in
                let frac = max(0.02, CGFloat(row.volume / maxVol))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.elevated)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accent)
                        .frame(width: geo.size.width * frac)
                }
            }
            .frame(height: 10)
        }
    }
}
