// CheckInEventsScreen.swift — step 3: races, sport sessions, hard days the
// user already knows about. These pre-empt the planner's default kind for
// their date and (if marked hard) trigger pre-event taper + post-event
// recovery passes.
//
// UI: a row of date chips covering the 7 days the planner will operate over
// (NEXT week's start … +6 — this flow plans next week, not the current one). Tap a date → EventEditorSheet → save lands in
// draft.events. The list below shows everything currently in the draft with
// swipe-to-delete.

import SwiftUI

struct CheckInEventsScreen: View {
    @Binding var draft: WeeklyCheckInDraft
    /// Monday-anchored start of the week the planner will use. Date chips +
    /// EventEditorSheet anchor against this so the user sees real dates,
    /// independent of when they happen to open the check-in.
    let weekStart: Date
    let onNext: () -> Void
    let onBack: () -> Void
    /// Escape hatch. Steps 2-5 passed nil, so CheckInScaffold rendered a blank
    /// 32x32 spacer where the X should be — a user who opened the flow from the
    /// Sunday notification and wanted out had to tap Back three or four times.
    let onClose: () -> Void

    @State private var pickingDate: Date? = nil
    /// B3 — result line under the calendar button; nil until the first tap.
    @State private var calendarNote: String? = nil
    @State private var readingCalendar = false

    var body: some View {
        CheckInScaffold(
            step: .events,
            title: "Anything on the calendar?",
            subtitle: "Add races, sport sessions, or known hard days. We'll taper into them and recover after.",
            nextLabel: draft.events.isEmpty ? "Skip" : "Continue",
            nextEnabled: true,
            onNext: onNext,
            onBack: onBack,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 18) {
                calendarSection
                dayPickerSection
                if !draft.events.isEmpty {
                    eventList
                }
            }
        }
        .sheet(item: pickingDateBinding) { wrapped in
            EventEditorSheet(date: wrapped.date) { event in
                // One event per day. Planner takes `.first` for a date
                // (Planner.swift:212), so a second event on the same day was
                // silently ignored by the plan while still rendering in the
                // list below — the user saw two, the planner honored one.
                // WeekDayEditSheet enforces this with an explicit "Replace
                // existing event?" confirmation; this screen had no equivalent,
                // so replace-in-place is the closest honest behavior here.
                draft.events.removeAll {
                    Calendar.current.isDate($0.date, inSameDayAs: event.date)
                }
                draft.events.append(event)
            }
        }
    }

    // MARK: - Sections

    /// B3 — find travel in next week's calendar. The tap is the only place the
    /// calendar permission prompt can appear. Found days land in the draft as
    /// "Travel" events the user can still remove; nothing commits until the
    /// check-in's own accept.
    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                findTravel()
            } label: {
                Label(readingCalendar ? "Checking your calendar…" : "Find travel in my calendar",
                      systemImage: "airplane.departure")
                    .styled(.monoXS)
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.line, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(readingCalendar)
            .accessibilityIdentifier("checkin-find-travel")
            if let calendarNote {
                Text(calendarNote)
                    .styled(.monoXS)
                    .foregroundStyle(Color.ink2)
                    .accessibilityIdentifier("checkin-find-travel-result")
            }
        }
    }

    private func findTravel() {
        readingCalendar = true
        Task { @MainActor in
            defer { readingCalendar = false }
            switch await CalendarTravelReader.findTravel(weekStart: weekStart) {
            case .denied:
                calendarNote = "Calendar access is off. You can turn it on in iOS Settings, or add travel days below."
            case .failed:
                calendarNote = "Couldn't read your calendar. Add travel days below."
            case .found(let days):
                let added = CalendarTravelDetector.events(for: days, existing: draft.events)
                draft.events.append(contentsOf: added)
                calendarNote = Self.summary(added: added, found: days.count)
            }
        }
    }

    /// "Added Tue to Thu from your calendar." Consecutive days read as a range.
    static func summary(added: [WeekEvent], found: Int) -> String {
        guard !added.isEmpty else {
            return found == 0 ? "No travel found next week." : "Travel days next week already have events."
        }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        let dates = added.map(\.date).sorted()
        let cal = Calendar.current
        let consecutive = zip(dates, dates.dropFirst()).allSatisfy {
            cal.dateComponents([.day], from: $0, to: $1).day == 1
        }
        let label = dates.count == 1 ? f.string(from: dates[0])
            : consecutive ? "\(f.string(from: dates.first!)) to \(f.string(from: dates.last!))"
            : dates.map { f.string(from: $0) }.joined(separator: ", ")
        return "Added \(label) from your calendar. Remove any that are wrong."
    }

    private var dayPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PICK A DAY")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            let columns = [GridItem(.adaptive(minimum: 80), spacing: 6)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(upcomingDays, id: \.self) { date in
                    dateChip(date)
                }
            }
        }
    }

    private func dateChip(_ date: Date) -> some View {
        Button { pickingDate = date } label: {
            VStack(spacing: 2) {
                Text(weekdayShort(date))
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Text(dayNumber(date))
                    .font(.scaled("JetBrainsMono-SemiBold", size: 18))
                    .foregroundStyle(Color.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEXT WEEK")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            VStack(spacing: 8) {
                ForEach(draft.events.sorted(by: { $0.date < $1.date })) { event in
                    eventRow(event)
                }
            }
        }
    }

    private func eventRow(_ event: WeekEvent) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .styled(.body)
                        .foregroundStyle(Color.ink)
                    intensityBadge(event.intensity)
                }
                Text(formattedDate(event.date))
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
            Spacer(minLength: 8)
            Button {
                draft.events.removeAll { $0.id == event.id }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.ink3)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func intensityBadge(_ intensity: EventIntensity) -> some View {
        Text(intensity.label.uppercased())
            .styled(.micro)
            .foregroundStyle(intensity == .hard ? Color.accentInk : Color.ink3)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(intensity == .hard ? Color.danger.opacity(0.9) : Color.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Helpers

    private var upcomingDays: [Date] {
        let cal = Calendar.current
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private func weekdayShort(_ date: Date) -> String {
        EventDateFormatters.weekdayShort.string(from: date).uppercased()
    }

    private func dayNumber(_ date: Date) -> String {
        EventDateFormatters.dayNumber.string(from: date)
    }

    private func formattedDate(_ date: Date) -> String {
        EventDateFormatters.eventDate.string(from: date)
    }

    /// Bridge pickingDate (Date?) → Identifiable wrapper for `.sheet(item:)`.
    private var pickingDateBinding: Binding<EventPickDate?> {
        Binding(
            get: { pickingDate.map(EventPickDate.init) },
            set: { pickingDate = $0?.date }
        )
    }
}

private struct EventPickDate: Identifiable {
    let date: Date
    var id: String { EventDateFormatters.isoDay.string(from: date) }
}

// Cached — the date chips + event rows re-render with every draft mutation;
// allocating a DateFormatter per call is needless churn. (Same pattern as
// WeekScreen's WeekDateFormatters.)
private enum EventDateFormatters {
    static let weekdayShort: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    /// "EEE, MMM d" — event-row date line.
    static let eventDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    /// ISO yyyy-MM-dd — sheet identity for EventPickDate.
    static let isoDay: DateFormatter = DayKeyFormatter.iso
}
