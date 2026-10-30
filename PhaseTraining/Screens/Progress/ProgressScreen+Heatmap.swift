// ProgressScreen+Heatmap.swift — month heatmap of logged workouts.
//
// A calendar month of day cells shaded by minutes trained (grid math in
// Data/TrainingHeatmap.swift). Tapping a day with one session opens it in
// EditSessionSheet, the same sheet History opens; a day with several asks
// which one first. The chevrons page back through earlier months.

import SwiftUI

extension ProgressScreen {

    var heatmapCard: some View {
        let now = Date()
        let month = TrainingHeatmap.monthStart(offset: heatmapMonthOffset, now: now)
        let weeks = TrainingHeatmap.weeks(month: month, sessions: sessions)
        let days = weeks.flatMap { $0 }.compactMap { $0 }
        let sessionCount = days.reduce(0) { $0 + $1.sessions.count }
        let minutes = days.reduce(0) { $0 + $1.minutes }

        return card(title: "TRAINING DAYS") {
            HStack(spacing: 8) {
                Text(Self.heatmapMonthFormatter.string(from: month))
                    .font(.scaled("Inter-Regular", size: 15))
                    .foregroundStyle(Color.ink)
                Spacer()
                heatmapPageButton("chevron.left", id: "progress-heatmap-prev") {
                    heatmapMonthOffset -= 1
                }
                heatmapPageButton("chevron.right", id: "progress-heatmap-next") {
                    heatmapMonthOffset += 1
                }
                .disabled(heatmapMonthOffset >= 0)
                .opacity(heatmapMonthOffset >= 0 ? 0.3 : 1)
            }

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(Array(TrainingHeatmap.weekdaySymbols().enumerated()), id: \.offset) { _, s in
                        Text(s)
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 4) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            heatmapCell(day, now: now)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Text(sessionCount == 0
                     ? "No sessions"
                     : "\(sessionCount) session\(sessionCount == 1 ? "" : "s") · "
                       + SessionRowMeta.durationLabel(minutes * 60, style: .spelled))
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                    .accessibilityIdentifier("progress-heatmap-summary")
                Spacer()
                Text("LESS").font(.monoXS).foregroundStyle(Color.ink3)
                ForEach(0...4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.heatmapFill(level))
                        .frame(width: 10, height: 10)
                }
                Text("MORE").font(.monoXS).foregroundStyle(Color.ink3)
            }
            .accessibilityElement(children: .combine)
        }
        .confirmationDialog(
            "Which session?",
            isPresented: Binding(
                get: { !heatmapDayChoices.isEmpty },
                set: { if !$0 { heatmapDayChoices = [] } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(heatmapDayChoices) { s in
                Button("\(s.name) · \(SessionRowMeta.durationLabel(s.duration, style: .spelled))") {
                    heatmapSession = s
                }
            }
        }
        .sheet(item: $heatmapSession) { session in
            EditSessionSheet(session: session)
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private func heatmapCell(_ day: TrainingHeatmap.Day?, now: Date) -> some View {
        if let day {
            let isToday = Calendar.current.isDate(day.date, inSameDayAs: now)
            // Imported workouts shade the day but are read-only, so only
            // native sessions open the editor.
            let editable = day.sessions.filter { $0.importSource == nil }
            Button {
                if editable.count == 1 {
                    heatmapSession = editable[0]
                } else if editable.count > 1 {
                    heatmapDayChoices = editable
                }
            } label: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Self.heatmapFill(day.level))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Text("\(Calendar.current.component(.day, from: day.date))")
                            .font(.monoXS)
                            .foregroundStyle(day.level >= 2 ? Color.accentInk : Color.ink3)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isToday ? Color.ink2 : .clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(editable.isEmpty)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(heatmapAccessibilityLabel(day))
            .accessibilityIdentifier("progress-heatmap-day-\(Self.heatmapIdFormatter.string(from: day.date))")
        } else {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
    }

    private func heatmapPageButton(_ symbol: String, id: String,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink2)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func heatmapAccessibilityLabel(_ day: TrainingHeatmap.Day) -> String {
        let date = Self.heatmapA11yDateFormatter.string(from: day.date)
        guard !day.sessions.isEmpty else { return "\(date), no workout" }
        let n = day.sessions.count
        return "\(date), \(n) session\(n == 1 ? "" : "s"), "
            + SessionRowMeta.durationLabel(day.minutes * 60, style: .spelled)
    }

    static func heatmapFill(_ level: Int) -> Color {
        switch level {
        case 0: return Color.lineSoft
        case 1: return Color.accent.opacity(0.25)
        case 2: return Color.accent.opacity(0.45)
        case 3: return Color.accent.opacity(0.7)
        default: return Color.accent
        }
    }

    private static let heatmapMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f
    }()

    private static let heatmapA11yDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE MMMM d")
        return f
    }()

    private static let heatmapIdFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
