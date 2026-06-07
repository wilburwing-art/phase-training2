// HealthImportsScreen.swift — Phase 2 Settings → Health & Imports
// subscreen. Presented from ProfileScreen's APP section as a sheet so
// it composes with the existing Settings row pattern.
//
// Thin shell: the three features live in Screens/HealthImports/ as
// section views that each own their state —
//   - HealthWorkoutSyncSection: auth status row, last-sync summary,
//     "Sync from Health" CTA, debug-only readiness breakdown.
//   - BodyMetricsSyncSection: weight / body-fat / lean-mass sync.
//   - CSVImportSection: Phase 3 CSV import + import-history management.
// The only cross-section seam is `workoutDataVersion`: the CSV importer
// can write cardio rows to imported_workouts, so it bumps the token and
// the workout-sync section refreshes its summary.

import SwiftUI

struct HealthImportsScreen: View {
    @Environment(\.dismiss) private var dismiss

    private let importer = HealthKitImporter()

    /// Bumped when the CSV section writes to imported_workouts so
    /// HealthWorkoutSyncSection re-reads its summary.
    @State private var workoutDataVersion = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        HealthWorkoutSyncSection(importer: importer, refreshToken: workoutDataVersion)
                        BodyMetricsSyncSection(importer: importer)
                        CSVImportSection(onImportedWorkoutsChanged: { workoutDataVersion += 1 })
                        Spacer().frame(height: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                }
            }
            .navigationTitle("Health & Imports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
