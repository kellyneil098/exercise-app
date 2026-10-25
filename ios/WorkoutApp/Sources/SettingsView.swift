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
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    HStack(spacing: Theme.Spacing.m) {
                        Avatar(name: model.settings?.displayName ?? "", size: 56)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Overline("You")
                            Text(model.settings?.displayName ?? "").font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                    .padding(.top, Theme.Spacing.xl)

                    account
                    gyms
                    prefs
                }
                .padding(.horizontal, Theme.Spacing.l).padding(.bottom, Theme.Spacing.xl)
            }
        }
        .presentationBackground(Theme.Colors.canvas)
        .sheet(item: $editingLocation) { EquipmentEditor(location: $0) }
        .task { if model.isSignedIn { shares = try? await model.shares() } }
    }

    @ViewBuilder var account: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Account", icon: "icloud", tint: Theme.Colors.brass)
            // Shown signed in or out: a refused account switch (unsent changes from the previous account) reports here.
            if let e = model.lastSyncError { Text(e).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.destructive) }
            if model.isSignedIn {
                HStack(spacing: Theme.Spacing.s) {
                    Circle().fill(Theme.Colors.swipeDone).frame(width: 8, height: 8)
                    Text("Synced").font(Theme.Fonts.bodyMedium).foregroundStyle(Theme.Colors.textPrimary)
                }
                if let shares {
                    ForEach(shares.iCanView, id: \.id) { Text("You can see \($0.displayName)").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary) }
                    ForEach(shares.canViewMe, id: \.id) { Text("\($0.displayName) can see you").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary) }
                }
                if let newInvite {
                    Text(newInvite.code).font(Theme.Fonts.numeral).foregroundStyle(Theme.Colors.brass).textSelection(.enabled)
                    Text("Share this code. Expires \(newInvite.expiresAt.formatted(.relative(presentation: .named))).").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                }
                PillButton("Invite someone", icon: "person.badge.plus", style: .quiet) { Task { newInvite = try? await model.createInvite(viewMe: true, viewThem: true) } }
                PillButton("Sync now", icon: "arrow.triangle.2.circlepath", style: .quiet) { Task { await model.syncIfPossible() } }
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
            SectionHeader("Gyms", icon: "mappin.and.ellipse", tint: Theme.Colors.legs)
            ForEach(model.locations) { loc in
                Button { editingLocation = loc } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Glyph(model.catalog.seededLocations.first { $0.key == loc.seedKey }?.kind == "home_gym" ? "house" : "building.2", tint: Theme.Colors.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.name).font(Theme.Fonts.bodyMedium).foregroundStyle(Theme.Colors.textPrimary)
                            Text(equipmentCaption(loc)).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
            PillButton("Add gym", icon: "plus", style: .quiet) {
                let loc = Location(userId: model.userId, name: "New gym", sortOrder: model.locations.count)
                try? model.store.save(loc)
                editingLocation = loc
            }
        }
    }

    func equipmentCaption(_ loc: Location) -> String {
        let p = model.equipmentPartition(for: loc)
        return "\(p.selectedCount) of \(p.totalCount) equipment types"
    }

    var prefs: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Preferences", icon: "slider.horizontal.3", tint: Theme.Colors.pull)
            Toggle(isOn: Binding(
                get: { model.settings?.keepScreenAwake ?? true },
                set: { v in if var s = model.settings { s.keepScreenAwake = v; try? model.store.save(s) } }
            )) { PrefLabel("Keep screen awake", detail: "During workouts", icon: "sun.max") }
            .tint(Theme.Colors.brass)
            Toggle(isOn: Binding(
                get: { model.settings?.restTimerSoundOn ?? true },
                set: { v in if var s = model.settings { s.restTimerSoundOn = v; try? model.store.save(s) } }
            )) { PrefLabel("Rest timer sound", detail: "Chime when rest ends", icon: "speaker.wave.2") }
            .tint(Theme.Colors.brass)
        }
    }
}

/// Section heading on the canvas: a tinted glyph beside an overline, ruled beneath.
struct SectionHeader: View {
    let title: String
    let icon: String
    let tint: Color
    init(_ title: String, icon: String, tint: Color) { self.title = title; self.icon = icon; self.tint = tint }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Glyph(icon, tint: tint, width: 20)
                Overline(title, tint: Theme.Colors.textSecondary)
            }
            Hairline()
        }
    }
}

struct PrefLabel: View {
    let title: String
    let detail: String
    let icon: String
    init(_ title: String, detail: String, icon: String) { self.title = title; self.detail = detail; self.icon = icon }
    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Glyph(icon, tint: Theme.Colors.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Fonts.bodyMedium).foregroundStyle(Theme.Colors.textPrimary)
                Text(detail).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }
}

/// One gym's equipment: what it has, then everything else in the master catalog, each row a toggle that persists at once.
/// Every gym sees the same catalog (`catalog.equipmentTypes`); only the checked subset differs.
struct EquipmentEditor: View {
    @State var location: Location
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var dbMax: Double = 0
    @State private var confirmDelete = false
    @State private var deleted = false

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header
                    Adjuster(dbMax == 0 ? "Dumbbells: no limit" : "Dumbbells up to \(dbMax.formatted()) lb", value: $dbMax, in: 0...150, step: 5)
                    equipment
                    PillButton("Done", icon: "checkmark") { dismiss() }
                }
                .padding(.horizontal, Theme.Spacing.l).padding(.bottom, Theme.Spacing.xl)
            }
        }
        .presentationBackground(Theme.Colors.canvas)
        .onAppear { dbMax = location.dumbbellMaxWeight ?? 0 }
        .onDisappear { saveDetails() }
        .confirmationDialog("Delete \(location.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete gym", role: .destructive) { deleteGym() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its equipment list goes with it; workouts you logged there are kept. This can't be undone.")
        }
    }

    var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Overline("Gym")
                TextField("Gym name", text: $location.name).font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                    .submitLabel(.done).onSubmit { saveDetails() }
            }
            Spacer()
            if model.canDelete(location) {
                Menu {
                    Button("Delete gym", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Gym options")
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    /// Checked items first, then the rest of the catalog; both grouped by seed category, labels A–Z.
    var equipment: some View {
        let partition = model.equipmentPartition(for: location)
        return VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            FlatSection("Available at this gym", detail: "\(partition.selectedCount) of \(partition.totalCount)") {
                if partition.selectedKeys == [EquipmentType.bodyweightKey] {
                    emptyNote("Nothing checked yet. Check equipment below to add it here.")
                }
                sections(partition.selected, available: true)
            }
            FlatSection("Not at this gym") {
                if partition.unselected.isEmpty {
                    emptyNote("Everything in the catalog is available here.")
                } else {
                    sections(partition.unselected, available: false)
                }
            }
        }
    }

    func sections(_ sections: [EquipmentSection], available: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sections) { section in
                Text(section.category).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.top, Theme.Spacing.m).padding(.bottom, Theme.Spacing.xs)
                    .accessibilityAddTraits(.isHeader)
                ForEach(section.items, id: \.key) { eq in
                    EquipmentRow(type: eq, available: available, locked: eq.key == EquipmentType.bodyweightKey) {
                        Haptics.play(.swap)
                        withAnimation(Theme.Motion.quick) { model.setEquipment(eq.key, available: !available, for: location) }
                    }
                }
            }
        }
    }

    func emptyNote(_ text: String) -> some View {
        Text(text).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary).padding(.vertical, Theme.Spacing.s)
    }

    /// Name and dumbbell ceiling save on Done, submit, or swipe-down; equipment toggles save as they happen.
    func saveDetails() {
        guard !deleted else { return }
        var loc = location
        loc.name = location.name.trimmingCharacters(in: .whitespaces)
        if loc.name.isEmpty { loc.name = model.locations.first { $0.id == location.id }?.name ?? "Gym" }
        loc.dumbbellMaxWeight = dbMax == 0 ? nil : dbMax
        location = loc
        try? model.store.save(loc)
    }

    func deleteGym() {
        guard model.deleteLocation(location) else { return }
        deleted = true
        Haptics.play(.warning)
        dismiss()
    }
}

/// One catalog item: label, note, and a check that reads as a toggle. Bodyweight is shown locked (always available).
struct EquipmentRow: View {
    let type: EquipmentType
    let available: Bool
    var locked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: Theme.Spacing.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(type.label).font(available ? Theme.Fonts.bodyMedium : Theme.Fonts.body)
                            .foregroundStyle(available ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        if locked {
                            Text("Always available").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                        } else if let note = type.note {
                            Text(note).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    Spacer()
                    Image(systemName: available ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                        .foregroundStyle(locked ? Theme.Colors.textTertiary : available ? Theme.Colors.brass : Theme.Colors.textTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Theme.Spacing.s).padding(.vertical, 10).frame(minHeight: 48)
                .contentShape(Rectangle())
                Hairline()
            }
        }
        .buttonStyle(PressStyle())
        .disabled(locked)
        .accessibilityLabel(type.label)
        .accessibilityValue(available ? "Available" : "Not available")
        .accessibilityHint(locked ? "Always available at every gym" : available ? "Removes it from this gym" : "Adds it to this gym")
        .accessibilityAddTraits(available ? .isSelected : [])
    }
}
