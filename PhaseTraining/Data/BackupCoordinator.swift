// BackupCoordinator.swift — backup / restore / erase state machine for the
// Profile screen.
//
// Extracted from ProfileScreen (architecture item 11): the coordinator owns
// the presentation state plus the full file-import → decode → confirm →
// restore → reload sequence, the export flow, and the full local wipe. The
// view keeps only the .sheet / .alert / .fileImporter modifiers bound to the
// published state below. The coordinator WRAPS BackupManager's atomic
// restore + RestorePhase error semantics — it never reimplements them.
//
// Store reloads take the stores as parameters (they're @EnvironmentObjects
// on the view, which a @StateObject-owned coordinator can't capture at init).

import SwiftUI

@MainActor
final class BackupCoordinator: ObservableObject {
    // Backup / restore UI state (the iOS-level presentation surfaces stay on
    // the Profile screen; DataEditorSheet just fires callbacks).
    @Published var exportURL: URL? = nil
    @Published var presentingImporter = false
    @Published var presentingShare = false
    @Published var backupError: String? = nil
    @Published var restoreCompleted = false
    // Decoded-but-not-yet-applied backup, held while the user confirms the
    // destructive overwrite. Restore only runs after explicit confirmation.
    @Published var pendingRestore: BackupEnvelope? = nil
    @Published var confirmingRestore = false

    // MARK: - Backup / restore

    func exportBackup() {
        do {
            let envelope = BackupManager.snapshot()
            let url = try BackupManager.writeTempFile(envelope)
            exportURL = url
            presentingShare = true
        } catch {
            backupError = (error as? BackupError)?.errorDescription ?? error.localizedDescription
        }
    }

    func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            backupError = err.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                // Decode + validate now, but defer the destructive write until
                // the user confirms — restore replaces ALL local data.
                let data = try Data(contentsOf: url)
                let envelope = try BackupManager.decode(data)
                pendingRestore = envelope
                confirmingRestore = true
            } catch {
                backupError = (error as? BackupError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Apply a confirmed restore, then reload every in-memory store from its
    /// source so the UI reflects the imported data immediately — no relaunch.
    func performRestore(
        _ envelope: BackupEnvelope,
        store: MemoryStore,
        planStore: PlanStore,
        sessionStore: SessionStore,
        customStore: CustomRoutineStore
    ) {
        do {
            try BackupManager.restore(envelope, into: .standard)
            store.reload()
            planStore.reloadFromDefaults()
            sessionStore.reload()
            customStore.reload()
            pendingRestore = nil
            restoreCompleted = true
        } catch {
            backupError = (error as? BackupError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Danger zone

    /// Full local wipe. `MemoryStore.wipeAllUserData()` clears both storage
    /// layers (UserDefaults + the SQLite store) and cancels the pending
    /// reminders; the per-store resets drop the live @Published caches so the
    /// app falls back to the onboarding cover immediately (driven by
    /// `MemoryStore.isOnboarded`).
    ///
    /// EVERY app-lifetime store that persists itself must be reset here. The
    /// wipe removes the `pt_`-prefixed keys from disk, but a store whose
    /// in-memory array survives will write the whole pre-erase history back on
    /// its next mutation — erase, re-onboard, log one sport session, and the
    /// old log reappears. `sportLogStore`, `recentPicks` and `conversation`
    /// were resurrecting exactly that way.
    func eraseAllData(
        store: MemoryStore,
        planStore: PlanStore,
        sessionStore: SessionStore,
        customStore: CustomRoutineStore,
        sportLogStore: SportLogStore,
        recentPicks: RecentPicksStore,
        conversation: CoachConversationStore
    ) {
        MemoryStore.wipeAllUserData()
        store.reset()
        sessionStore.clearInMemoryState()
        customStore.reload()
        planStore.clear()
        sportLogStore.reset()
        recentPicks.clear()
        conversation.resetAll()
    }
}
