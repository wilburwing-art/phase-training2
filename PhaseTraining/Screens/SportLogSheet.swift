// SportLogSheet.swift — record a sport-day session after the fact.
//
// Presented from TodayScreen when today is a .sport day. Captures the
// minimum useful outcome (duration, intensity, optional note) and writes
// it through SportLogStore. Re-opening for an existing entry on the same
// day pre-fills with the previous values and edits in place.

import SwiftUI

struct SportLogSheet: View {
    /// Day this log is for — must be start-of-day; the store normalizes
    /// again on insert in case a caller forgets.
    let date: Date
    /// Sport from the day's plan (e.g. Climbing). Surfaced read-only on
    /// the sheet so the user knows which day they're logging.
    let sport: Sport
    /// When non-nil, the sheet edits this entry rather than creating one.
    let existing: SportLogEntry?

    let onSave: (_ durationMinutes: Int, _ intensity: EventIntensity, _ note: String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var durationMinutes: Int
    @State private var intensity: EventIntensity
    @State private var note: String

    // Custom duration entry — tapping the minutes value opens an alert
    // TextField for sessions the ±5 stepper can't reach quickly. The valid
    // range lives in the alert message so clamping isn't a silent rewrite.
    @State private var editingDuration = false
    @State private var durationText = ""

    init(date: Date,
         sport: Sport,
         existing: SportLogEntry? = nil,
         onSave: @escaping (Int, EventIntensity, String?) -> Void) {
        self.date = date
        self.sport = sport
        self.existing = existing
        self.onSave = onSave
        // Defaults match the "moderate hour" most hybrid athletes log if
        // they don't think about it. Pre-fill from the existing entry
        // when the user re-opens to edit.
        _durationMinutes = State(initialValue: existing?.durationMinutes ?? 60)
        _intensity = State(initialValue: existing?.intensity ?? .moderate)
        _note = State(initialValue: existing?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        sportRow
                        durationCard
                        intensityCard
                        noteCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
                VStack {
                    Spacer()
                    saveButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
            .navigationTitle(existing == nil ? "Log session" : "Edit log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.ink2)
                }
            }
            .alert("Duration", isPresented: $editingDuration) {
                TextField("minutes", text: $durationText)
                    .keyboardType(.numberPad)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    guard let raw = Int(durationText.trimmingCharacters(in: .whitespaces)) else { return }
                    durationMinutes = min(600, max(5, raw))
                }
            } message: {
                Text("Enter 5–600 minutes.")
            }
        }
        .presentationBackground(Color.bg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Rows

    private var sportRow: some View {
        HStack(spacing: 10) {
            Text(sport.name.uppercased())
                .font(.custom("SpaceGrotesk-SemiBold", size: 13))
                .tracking(1.2)
                .foregroundStyle(Color.ink3)
            Spacer()
            Text(dateLabel)
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
        }
    }

    private var durationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("DURATION")
            HStack(spacing: 14) {
                Spacer()
                Button {
                    if durationMinutes > 5 { durationMinutes -= 5 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(durationMinutes > 5 ? Color.accent : Color.line)
                }
                .buttonStyle(.plain)
                .disabled(durationMinutes <= 5)

                Button {
                    durationText = String(durationMinutes)
                    editingDuration = true
                } label: {
                    Text("\(durationMinutes) min")
                        .font(.custom("SpaceGrotesk-SemiBold", size: 22))
                        .foregroundStyle(Color.ink)
                        .frame(minWidth: 110)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sport-duration-value")

                Button {
                    if durationMinutes < 600 { durationMinutes += 5 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(durationMinutes < 600 ? Color.accent : Color.line)
                }
                .buttonStyle(.plain)
                .disabled(durationMinutes >= 600)
                Spacer()
            }
        }
        .padding(16)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var intensityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("INTENSITY")
            HStack(spacing: 8) {
                ForEach(EventIntensity.allCases, id: \.self) { option in
                    intensityChip(option)
                }
            }
        }
        .padding(16)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func intensityChip(_ option: EventIntensity) -> some View {
        let selected = (option == intensity)
        return Button {
            intensity = option
        } label: {
            Text(option.label)
                .font(.custom("SpaceGrotesk-SemiBold", size: 14))
                .foregroundStyle(selected ? Color.accentInk : Color.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? Color.accent : Color.bg)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Color.clear : Color.line, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("NOTE (OPTIONAL)")
            // TextEditor over TextField so multi-line notes don't truncate.
            // axis: .vertical on a TextField would also work but TextEditor
            // matches the editor surfaces elsewhere in the app.
            TextEditor(text: $note)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(8)
                .background(Color.bg)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Color.ink)
                .font(.system(size: 15))
        }
        .padding(16)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.custom("SpaceGrotesk-SemiBold", size: 11))
            .tracking(1.2)
            .foregroundStyle(Color.ink3)
    }

    private var saveButton: some View {
        Button {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            onSave(durationMinutes, intensity, trimmed.isEmpty ? nil : trimmed)
            dismiss()
        } label: {
            Text(existing == nil ? "Save log" : "Update log")
                .font(.custom("SpaceGrotesk-SemiBold", size: 15))
                .foregroundStyle(Color.accentInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sport-log-save")
    }

    /// Cached — dateLabel re-renders with every field edit; allocating a
    /// DateFormatter each call is needless churn.
    private static let dateLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f
    }()

    private var dateLabel: String {
        Self.dateLabelFormatter.string(from: date)
    }
}
