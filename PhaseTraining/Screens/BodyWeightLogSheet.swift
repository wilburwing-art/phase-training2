// BodyWeightLogSheet.swift — body-weight time series editor.
//
// Build 103. Before this, `TrainingMemory.weightKg` was a single scalar set
// during onboarding (or in AboutYouEditorSheet), powering strength-ratios
// and 1RM math without any trend signal. This sheet exposes the append-only
// `bodyWeightLog` series: log a weight, see the last 12 entries, see a
// month-scale chart. Adding a new entry mirrors onto `weightKg` so every
// existing read path (StrengthStandards, generator, profile summary) sees
// the latest value without re-plumbing.
//
// Storage stays metric (kg) regardless of display unit — same convention
// as the rest of BodyMetrics. The TextField uses the user's preferred unit
// at the input boundary and converts before write.

import SwiftUI
import Charts

struct BodyWeightLogSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var weightText: String = ""
    @State private var noteText: String = ""
    @FocusState private var weightFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        logInputCard
                        if !sortedEntries.isEmpty {
                            trendCard
                            historyCard
                        } else {
                            emptyHistoryCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Body weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            // Seed the log from a scalar weight set during onboarding / About
            // You so it shows in the trend + history (idempotent — only fires
            // when the log is empty and a scalar exists).
            store.update { $0.backfillBodyWeightLogFromScalar() }
            // Seed input from the most recent entry so the user sees today's
            // logging as a small delta, not a from-scratch number.
            if weightText.isEmpty, let latest = sortedEntries.first {
                weightText = formattedInputValue(kg: latest.weightKg)
            }
        }
    }

    // MARK: - Sections

    private var logInputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("LOG NEW WEIGHT")
            HStack(spacing: 8) {
                TextField(unitLabel, text: $weightText)
                    .focused($weightFocused)
                    .keyboardType(.decimalPad)
                    .font(.custom("JetBrainsMono-SemiBold", size: 22))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.elevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.line, lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("body-weight-log-input")
                Text(unitLabel)
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
            TextField("Note (optional)", text: $noteText)
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.elevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.line, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Button(action: logEntry) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Log weight")
                        .font(.custom("SpaceGrotesk-SemiBold", size: 14))
                }
                .foregroundStyle(canLog ? Color.accentInk : Color.ink3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(canLog ? Color.accent : Color.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(!canLog)
            .accessibilityIdentifier("body-weight-log-submit")
        }
        .padding(14)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("TREND")
                Spacer()
                if let delta = deltaFromOldest {
                    Text(delta)
                        .font(.monoXS)
                        .foregroundStyle(deltaColor)
                }
            }
            Chart {
                ForEach(sortedEntries.reversed()) { entry in
                    LineMark(
                        x: .value("date", entry.date),
                        y: .value("weight", displayValue(kg: entry.weightKg))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                    PointMark(
                        x: .value("date", entry.date),
                        y: .value("weight", displayValue(kg: entry.weightKg))
                    )
                    .foregroundStyle(Color.accent)
                    .symbolSize(20)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .foregroundStyle(Color.ink3)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(Color.ink3)
                }
            }
            .frame(height: 160)
        }
        .padding(14)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("RECENT")
            VStack(spacing: 0) {
                ForEach(Array(sortedEntries.prefix(12).enumerated()), id: \.element.id) { idx, entry in
                    historyRow(entry)
                    if idx < min(sortedEntries.count, 12) - 1 {
                        Rectangle()
                            .fill(Color.lineSoft)
                            .frame(height: 0.5)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var emptyHistoryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("RECENT")
            Text("No weights logged yet. Log one above to start a trend.")
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(Color.ink2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func historyRow(_ entry: BodyWeightEntry) -> some View {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return HStack(spacing: 10) {
            Text(f.string(from: entry.date).uppercased())
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
                .frame(width: 56, alignment: .leading)
            Text(BodyMetrics.formatWeight(kg: entry.weightKg, imperial: store.memory.usesImperial))
                .font(.custom("JetBrainsMono-SemiBold", size: 14))
                .foregroundStyle(Color.ink)
            Spacer(minLength: 8)
            if let note = entry.note, !note.isEmpty {
                Text(note)
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                    .lineLimit(1)
            }
            Button(role: .destructive) { deleteEntry(entry) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ink3)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("body-weight-log-delete-\(entry.id.uuidString)")
        }
        .padding(.vertical, 8)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .styled(.micro)
            .foregroundStyle(Color.ink3)
    }

    // MARK: - Derived

    private var sortedEntries: [BodyWeightEntry] {
        store.memory.bodyWeightLog.sorted { $0.date > $1.date }
    }

    /// True when the input parses to a positive number — guards the Log
    /// button so we don't write "0" or "—".
    private var canLog: Bool {
        guard let kg = parseInputAsKg(weightText) else { return false }
        return kg > 0
    }

    private var unitLabel: String {
        store.memory.usesImperial ? "lb" : "kg"
    }

    /// Convert metric → display unit for the chart axis.
    private func displayValue(kg: Double) -> Double {
        store.memory.usesImperial ? BodyMetrics.kgToLb(kg) : kg
    }

    /// Format a kg value into the user's preferred unit for prefilling the
    /// TextField (no unit suffix — that lives in the placeholder).
    private func formattedInputValue(kg: Double) -> String {
        let v = displayValue(kg: kg)
        return String(format: "%.1f", v)
    }

    /// Best-effort delta from the oldest entry to the newest. Empty/single
    /// entry → nil (no delta to show).
    private var deltaFromOldest: String? {
        guard sortedEntries.count >= 2,
              let newest = sortedEntries.first?.weightKg,
              let oldest = sortedEntries.last?.weightKg else { return nil }
        let dKg = newest - oldest
        let absDisplay = abs(store.memory.usesImperial ? BodyMetrics.kgToLb(dKg) : dKg)
        let sign = dKg >= 0 ? "+" : "−"
        return String(format: "%@%.1f %@ since first entry", sign, absDisplay, unitLabel)
    }

    private var deltaColor: Color {
        guard sortedEntries.count >= 2,
              let newest = sortedEntries.first?.weightKg,
              let oldest = sortedEntries.last?.weightKg else { return .ink3 }
        return newest >= oldest ? .accent : .ok
    }

    // MARK: - Mutations

    private func logEntry() {
        guard let kg = parseInputAsKg(weightText), kg > 0 else { return }
        let note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Single funnel: append + mirror the scalar to the newest entry.
        store.update { mem in
            mem.recordBodyWeight(kg, note: note.isEmpty ? nil : note)
        }
        noteText = ""
        weightFocused = false
    }

    private func deleteEntry(_ entry: BodyWeightEntry) {
        store.update { mem in
            mem.bodyWeightLog.removeAll { $0.id == entry.id }
            // Re-mirror to whatever's still latest. Does NOT null the scalar
            // when the log drains — an onboarded / About-You weight that was
            // never logged must survive deleting the last logged entry.
            mem.remirrorWeightFromLog()
        }
    }

    /// Parse the input TextField. Accepts both unit systems — when imperial
    /// is on we read lb and convert; otherwise we read kg directly. Tolerant
    /// of trailing whitespace + a comma decimal separator.
    private func parseInputAsKg(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        if s.contains(",") && !s.contains(".") {
            s = s.replacingOccurrences(of: ",", with: ".")
        }
        guard let v = Double(s) else { return nil }
        return store.memory.usesImperial ? BodyMetrics.lbToKg(v) : v
    }
}

#Preview {
    let suite = "BodyWeightLogSheet.preview"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = MemoryStore(defaults: defaults)
    let now = Date()
    let cal = Calendar.current
    let seed: [(daysAgo: Int, lb: Double)] = [
        (45, 178),
        (35, 176.4),
        (28, 175.2),
        (21, 174.0),
        (14, 173.6),
        (7,  172.8),
        (1,  172.2),
    ]
    store.update { mem in
        mem.bodyWeightLog = seed.map {
            BodyWeightEntry(
                date: cal.date(byAdding: .day, value: -$0.daysAgo, to: now) ?? now,
                weightKg: BodyMetrics.lbToKg($0.lb)
            )
        }
        mem.weightKg = mem.bodyWeightLog.last?.weightKg
        mem.usesImperial = true
    }
    return BodyWeightLogSheet()
        .environmentObject(store)
}
