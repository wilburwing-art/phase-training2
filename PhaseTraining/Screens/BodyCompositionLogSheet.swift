// BodyCompositionLogSheet.swift — body-fat % + lean mass time series editor.
//
// Build 103. Mirrors BodyWeightLogSheet shape: top input card → trend → recent
// history. Either field is optional per row — DEXA users log both, scale
// users log just BF%, and we still chart whichever's present. Method +
// note are free-text so users can tag a row "DEXA at clinic" vs
// "weekly InBody".
//
// Lean mass stored in kg (metric convention); display flips per
// `usesImperial`. BF% is unit-agnostic so no conversion needed.

import SwiftUI
import Charts

struct BodyCompositionLogSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var bfText: String = ""
    @State private var leanText: String = ""
    @State private var methodText: String = ""
    @State private var noteText: String = ""
    @State private var pendingDelete: BodyCompositionEntry?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        logInputCard
                        if !sortedEntries.isEmpty {
                            bfTrendCard
                            leanTrendCard
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
            .navigationTitle("Body composition")
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
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) { deleteEntry(entry); pendingDelete = nil }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("This removes the logged measurement. Your history can't recover it.")
        }
        .onAppear {
            if let latest = sortedEntries.first {
                if let bf = latest.bodyFatPercent { bfText = String(format: "%.1f", bf) }
                if let lean = latest.leanMassKg {
                    leanText = String(format: "%.1f", displayMass(kg: lean))
                }
                if let method = latest.method { methodText = method }
            }
        }
    }

    // MARK: - Input

    private var logInputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("NEW READING")
            fieldRow(label: "BODY FAT", placeholder: "% (e.g. 18.5)", text: $bfText, suffix: "%")
            fieldRow(label: "LEAN MASS", placeholder: "(optional)", text: $leanText, suffix: massUnit)
            TextField("Method (DEXA, InBody, calipers…)", text: $methodText)
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
                    Text("Log reading")
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
            .accessibilityIdentifier("body-composition-log-submit")
        }
        .cardSurface()
    }

    private func fieldRow(label: String, placeholder: String, text: Binding<String>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            HStack(spacing: 8) {
                TextField(placeholder, text: text)
                    .keyboardType(.decimalPad)
                    .font(.custom("JetBrainsMono-SemiBold", size: 18))
                    .foregroundStyle(Color.ink)
                Text(suffix)
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.elevated)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Trends

    private var bfTrendCard: some View {
        let entriesWithBF = sortedEntries.reversed().compactMap { e -> (Date, Double)? in
            guard let bf = e.bodyFatPercent else { return nil }
            return (e.date, bf)
        }
        return Group {
            if entriesWithBF.isEmpty {
                EmptyView()
            } else {
                trendCard(title: "BODY FAT %", points: entriesWithBF, suffix: "%")
            }
        }
    }

    private var leanTrendCard: some View {
        let entriesWithLean = sortedEntries.reversed().compactMap { e -> (Date, Double)? in
            guard let lean = e.leanMassKg else { return nil }
            return (e.date, displayMass(kg: lean))
        }
        return Group {
            if entriesWithLean.isEmpty {
                EmptyView()
            } else {
                trendCard(title: "LEAN MASS · \(massUnit.uppercased())", points: entriesWithLean, suffix: massUnit)
            }
        }
    }

    private func trendCard(title: String, points: [(Date, Double)], suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel(title)
                Spacer()
                if let delta = trendDelta(points: points, suffix: suffix) {
                    Text(delta)
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            }
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("date", point.0),
                        y: .value(title, point.1)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                    PointMark(
                        x: .value("date", point.0),
                        y: .value(title, point.1)
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
            .frame(height: 140)
        }
        .cardSurface()
    }

    // MARK: - History

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
        .cardSurface()
    }

    private var emptyHistoryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("RECENT")
            Text("No readings logged yet. Log a body-fat % above to start a trend.")
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

    private func historyRow(_ entry: BodyCompositionEntry) -> some View {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return HStack(spacing: 10) {
            Text(f.string(from: entry.date).uppercased())
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    if let bf = entry.bodyFatPercent {
                        Text(String(format: "%.1f%%", bf))
                            .font(.custom("JetBrainsMono-SemiBold", size: 14))
                            .foregroundStyle(Color.ink)
                    }
                    if let lean = entry.leanMassKg {
                        Text(String(format: "%.1f %@", displayMass(kg: lean), massUnit))
                            .font(.custom("JetBrainsMono-SemiBold", size: 14))
                            .foregroundStyle(Color.ink2)
                    }
                }
                if let method = entry.method, !method.isEmpty {
                    Text(method)
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            }
            Spacer(minLength: 8)
            Button(role: .destructive) { pendingDelete = entry } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ink3)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("body-composition-log-delete-\(entry.id.uuidString)")
        }
        .padding(.vertical, 8)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .styled(.micro)
            .foregroundStyle(Color.ink3)
    }

    // MARK: - Derived

    private var sortedEntries: [BodyCompositionEntry] {
        store.memory.bodyCompositionLog.sorted { $0.date > $1.date }
    }

    private var canLog: Bool {
        // Either BF% or lean mass has to parse — otherwise there's nothing
        // to log. Both blank → no-op rather than write an empty row.
        return parseDouble(bfText) != nil || parseDouble(leanText) != nil
    }

    private var massUnit: String {
        store.memory.usesImperial ? "lb" : "kg"
    }

    private func displayMass(kg: Double) -> Double {
        store.memory.usesImperial ? BodyMetrics.kgToLb(kg) : kg
    }

    private func storeMass(_ raw: Double) -> Double {
        store.memory.usesImperial ? BodyMetrics.lbToKg(raw) : raw
    }

    private func trendDelta(points: [(Date, Double)], suffix: String) -> String? {
        guard points.count >= 2 else { return nil }
        let first = points.first!.1
        let last = points.last!.1
        let d = last - first
        let sign = d >= 0 ? "+" : "−"
        return String(format: "%@%.1f %@ since first", sign, abs(d), suffix)
    }

    // MARK: - Mutations

    private func logEntry() {
        let bf = parseDouble(bfText)
        let leanRaw = parseDouble(leanText)
        let leanKg = leanRaw.map(storeMass)
        guard bf != nil || leanKg != nil else { return }
        let method = methodText.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = BodyCompositionEntry(
            date: Date(),
            bodyFatPercent: bf,
            leanMassKg: leanKg,
            method: method.isEmpty ? nil : method,
            note: note.isEmpty ? nil : note
        )
        store.update { mem in
            mem.bodyCompositionLog.append(entry)
        }
        noteText = ""
    }

    private func deleteEntry(_ entry: BodyCompositionEntry) {
        store.update { mem in
            mem.bodyCompositionLog.removeAll { $0.id == entry.id }
        }
    }

    private func parseDouble(_ raw: String) -> Double? {
        BodyMetrics.parseDecimalInput(raw)
    }
}

#Preview {
    let suite = "BodyCompositionLogSheet.preview"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = MemoryStore(defaults: defaults)
    let now = Date()
    let cal = Calendar.current
    store.update { mem in
        mem.bodyCompositionLog = [
            BodyCompositionEntry(
                date: cal.date(byAdding: .day, value: -90, to: now) ?? now,
                bodyFatPercent: 22.0,
                leanMassKg: 62.0,
                method: "DEXA"
            ),
            BodyCompositionEntry(
                date: cal.date(byAdding: .day, value: -60, to: now) ?? now,
                bodyFatPercent: 20.5,
                leanMassKg: 62.8,
                method: "InBody"
            ),
            BodyCompositionEntry(
                date: cal.date(byAdding: .day, value: -30, to: now) ?? now,
                bodyFatPercent: 19.0,
                leanMassKg: 63.5,
                method: "InBody"
            ),
            BodyCompositionEntry(
                date: now,
                bodyFatPercent: 17.8,
                leanMassKg: 64.0,
                method: "DEXA"
            ),
        ]
    }
    return BodyCompositionLogSheet()
        .environmentObject(store)
}
