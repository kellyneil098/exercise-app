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
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    HStack(spacing: Theme.Spacing.m) {
                        Avatar(name: model.settings?.displayName ?? "", size: 56)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Overline("You")
                            Text(model.settings?.displayName ?? "").font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                    .padding(.top, Theme.Spacing.s)

                    account
                    gyms
                    rotation
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
                            Text("\(model.equipment(for: loc).count) pieces of equipment").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
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

    var rotation: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Heavy rotation", icon: "flame", tint: Theme.Colors.push)
            ForEach(DayType.allCases, id: \.self) { d in
                let rot = model.splitState.heavyRotations[d]
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    Glyph(d.symbol, tint: Theme.Colors.day(d))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.label).font(Theme.Fonts.bodyMedium).foregroundStyle(Theme.Colors.textPrimary)
                        Text((rot?.sequence ?? []).map { $0.replacingOccurrences(of: "_", with: " ").capitalized }.joined(separator: " → "))
                            .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                }
            }
        }
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

struct EquipmentEditor: View {
    @State var location: Location
    @Environment(AppModel.self) private var model
    @State private var selected: Set<String> = []
    @State private var dbMax: Double = 0

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Overline("Gym")
                        TextField("Gym name", text: $location.name).font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .padding(.top, Theme.Spacing.s)
                    Group {
                        Adjuster(dbMax == 0 ? "Dumbbells: no limit" : "Dumbbells up to \(dbMax.formatted()) lb", value: $dbMax, in: 0...150, step: 5)
                    }
                    Group {
                        VStack(spacing: 0) {
                            Hairline()
                            ForEach(Array(model.catalog.equipmentTypes.enumerated()), id: \.element.key) { i, eq in
                                let on = selected.contains(eq.key)
                                Button { Haptics.play(.swap); if on { selected.remove(eq.key) } else { selected.insert(eq.key) } } label: {
                                    HStack(spacing: Theme.Spacing.m) {
                                        Text(eq.label).font(on ? Theme.Fonts.bodyMedium : Theme.Fonts.body)
                                            .foregroundStyle(on ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                                        Spacer()
                                        Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                                            .foregroundStyle(on ? Theme.Colors.brass : Theme.Colors.textTertiary)
                                    }
                                    .padding(.horizontal, Theme.Spacing.s).frame(minHeight: 48)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PressStyle())
                                Hairline()
                            }
                        }
                    }
                    PillButton("Save", icon: "checkmark") { save() }
                }
                .padding(.horizontal, Theme.Spacing.l).padding(.bottom, Theme.Spacing.xl)
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
