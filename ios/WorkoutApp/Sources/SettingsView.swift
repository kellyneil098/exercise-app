import GRDB
import SwiftUI
import WorkoutEngine
import WorkoutStore
import WorkoutUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var invite = ""
    @State private var newInvite: InviteDTO?
    @State private var shares: SharesDTO?
    @State private var error: String?
    @State private var editingLocation: Location?

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Overline("You")
                    Text(model.settings?.displayName ?? "").font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)

                    Card { account }
                    Card { gyms }
                    Card { rotation }
                    Card { prefs }
                }
                .padding(Theme.Spacing.l)
            }
        }
        .presentationBackground(Theme.Colors.canvas)
        .sheet(item: $editingLocation) { EquipmentEditor(location: $0) }
        .task { if model.isSignedIn { shares = try? await model.shares() } }
    }

    @ViewBuilder var account: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Overline("Account")
            if model.isSignedIn {
                Text("Synced").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textPrimary)
                if let e = model.lastSyncError { Text(e).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.destructive) }
                if let shares {
                    ForEach(shares.iCanView, id: \.id) { Text("You can see \($0.displayName)").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary) }
                    ForEach(shares.canViewMe, id: \.id) { Text("\($0.displayName) can see you").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary) }
                }
                if let newInvite {
                    Text(newInvite.code).font(Theme.Fonts.numeral).foregroundStyle(Theme.Colors.brass).textSelection(.enabled)
                    Text("Share this code. Expires \(newInvite.expiresAt.formatted(.relative(presentation: .named))).").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                }
                PillButton("Invite someone", style: .quiet) { Task { newInvite = try? await model.createInvite(viewMe: true, viewThem: true) } }
                PillButton("Sync now", style: .quiet) { Task { await model.syncIfPossible() } }
                Button("Sign out") { model.signOut() }.font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.destructive)
            } else {
                AppleSignInButton(inviteCode: invite.isEmpty ? nil : invite) { err in error = err }
                TextField("Invite code (first sign-in)", text: $invite).font(Theme.Fonts.body).textInputAutocapitalization(.characters)
                #if DEBUG
                TextField("Dev email", text: $email).font(Theme.Fonts.body).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                PillButton("Dev sign in", style: .quiet) {
                    Task { do { try await model.devLogin(email: email, inviteCode: invite.isEmpty ? nil : invite) } catch { self.error = "\(error)" } }
                }
                #endif
                if let error { Text(error).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.destructive) }
                Text("Everything works offline; signing in adds backup and sharing.").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    var gyms: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Overline("Gyms")
            ForEach(model.locations) { loc in
                Button { editingLocation = loc } label: {
                    HStack {
                        Text(loc.name).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Text("\(model.equipment(for: loc).count) items").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                        Image(systemName: "chevron.right").foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
            PillButton("Add gym", style: .quiet) {
                let loc = Location(userId: model.userId, name: "New gym", sortOrder: model.locations.count)
                try? model.store.save(loc)
                editingLocation = loc
            }
        }
    }

    var rotation: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Overline("Heavy rotation")
            ForEach(DayType.allCases, id: \.self) { d in
                let rot = model.splitState.heavyRotations[d]
                HStack {
                    DayTag(d)
                    Spacer()
                    Text((rot?.sequence ?? []).map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: " → ")).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    var prefs: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Overline("Preferences")
            Toggle("Keep screen awake during workouts", isOn: Binding(
                get: { model.settings?.keepScreenAwake ?? true },
                set: { v in if var s = model.settings { s.keepScreenAwake = v; try? model.store.save(s) } }
            )).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textPrimary)
            Toggle("Rest timer sound", isOn: Binding(
                get: { model.settings?.restTimerSoundOn ?? true },
                set: { v in if var s = model.settings { s.restTimerSoundOn = v; try? model.store.save(s) } }
            )).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textPrimary)
        }
    }
}

struct EquipmentEditor: View {
    @State var location: Location
    @Environment(AppModel.self) private var model
    @State private var selected: Set<String> = []
    @State private var dbMax: Double = 0

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    TextField("Gym name", text: $location.name).font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                    Stepper(dbMax == 0 ? "Dumbbells: no limit" : "Dumbbells up to \(dbMax.formatted()) lb", value: $dbMax, in: 0...150, step: 5)
                        .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textPrimary)
                    Hairline()
                    ForEach(model.catalog.equipmentTypes, id: \.key) { eq in
                        Button { if selected.contains(eq.key) { selected.remove(eq.key) } else { selected.insert(eq.key) } } label: {
                            HStack {
                                Text(eq.label).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textPrimary)
                                Spacer()
                                Image(systemName: selected.contains(eq.key) ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.Colors.brass)
                            }.padding(.vertical, 10)
                        }
                    }
                    PillButton("Save") { save() }
                }
                .padding(Theme.Spacing.l)
            }
        }
        .presentationBackground(Theme.Colors.canvas)
        .onAppear { selected = model.equipment(for: location); dbMax = location.dumbbellMaxWeight ?? 0 }
    }

    @Environment(\.dismiss) private var dismiss
    func save() {
        location.dumbbellMaxWeight = dbMax == 0 ? nil : dbMax
        try? model.store.save(location)
        let existing = (try? model.store.db.read { try LocationEquipment.filter(Column("locationId") == location.id && Column("deleted") == false).fetchAll($0) }) ?? []
        for row in existing where !selected.contains(row.equipmentType) { try? model.store.delete(row) }
        let have = Set(existing.map(\.equipmentType))
        try? model.store.save(selected.subtracting(have).map { LocationEquipment(userId: model.userId, locationId: location.id, equipmentType: $0) })
        dismiss()
    }
}
