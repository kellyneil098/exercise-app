import XCTest
@testable import WorkoutEngine

/// The default stretch placeholder that ends every newly generated deck.
final class CooldownTests: XCTestCase {
    let planner = Planner(catalog: Fixtures.catalog)

    func input(_ day: DayType, _ minutes: Int = 60) -> PlannerInput {
        PlannerInput(dayType: day, durationMinutes: minutes, location: Fixtures.commercial, heavyRotation: Fixtures.rotation(day),
                     states: Fixtures.baseline, recentSessions: [], now: Date(timeIntervalSince1970: 1_800_000_000))
    }

    /// What `ActiveSession.orderedBlocks` does with a manual order (minus superset gluing).
    func ordered(_ edits: DeckEdits, _ blocks: [PlanBlock]) -> [PlanBlock] {
        guard !edits.order.isEmpty else { return blocks }
        let rank = Dictionary(edits.order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return blocks.sorted { (rank[$0.id] ?? .max, $0.slot) < (rank[$1.id] ?? .max, $1.slot) }
    }

    func testEveryNewDeckEndsWithOneTenMinuteStretch() {
        for day in DayType.allCases {
            for minutes in EngineConfig.default.durationBuckets {
                let plan = planner.generate(input(day, minutes))
                XCTAssertEqual(plan.blocks.filter(\.isCooldown).count, 1, "\(day) \(minutes)")
                let last = plan.slotOrdered.last!
                XCTAssertTrue(last.isCooldown)
                XCTAssertEqual(last.slot, plan.blocks.map(\.slot).max())
                XCTAssertEqual(last.estimatedSeconds, 600)
                XCTAssertEqual(last.exerciseKey, PlanBlock.cooldownExerciseKey)
            }
        }
    }

    func testStretchIsNotAWeightedHeavyOrSupersetBlock() {
        let plan = planner.generate(input(.push, 90))
        let stretch = plan.blocks.first(where: \.isCooldown)!
        XCTAssertNil(stretch.weight)
        XCTAssertNil(stretch.weightSource)
        XCTAssertTrue(stretch.warmups.isEmpty)
        XCTAssertNotEqual(stretch.band, .heavy)
        XCTAssertNil(stretch.supersetHostID)
        XCTAssertNil(plan.supersetPartner(of: stretch))
        XCTAssertEqual(stretch.sets, 1)
        XCTAssertFalse(stretch.tracksProgression)
        XCTAssertFalse(plan.progressionBlocks.contains(where: \.isCooldown))
    }

    func testStretchAddsTenMinutesOnTopOfTheLiftingBudget() {
        var config = EngineConfig.default
        config.appendsCooldown = false
        let without = Planner(catalog: Fixtures.catalog, config: config)
        for day in DayType.allCases {
            let withStretch = planner.generate(input(day, 45))
            let lifting = without.generate(input(day, 45))
            XCTAssertEqual(withStretch.estimatedSeconds, lifting.estimatedSeconds + 600, accuracy: 0.001, "\(day)")
            XCTAssertEqual(withStretch.progressionBlocks.map(\.exerciseKey), lifting.blocks.map(\.exerciseKey), "\(day)")
            XCTAssertFalse(lifting.blocks.contains(where: \.isCooldown))
        }
    }

    func testStretchCanBeDeletedAndMovedToTheFront() {
        let plan = planner.generate(input(.legs))
        let deck = plan.slotOrdered
        let stretch = deck.last!
        var edits = DeckEdits()
        edits.move(fromOffsets: IndexSet(integer: deck.count - 1), toOffset: 0, in: deck)
        XCTAssertEqual(edits.active(ordered(edits, deck)).first?.id, stretch.id)
        XCTAssertEqual(edits.active(ordered(edits, deck)).count, deck.count)

        var deleting = DeckEdits()
        deleting.delete(stretch.id)
        XCTAssertFalse(deleting.active(deck).contains { $0.id == stretch.id })
        XCTAssertEqual(deleting.deletedBlocks(deck).map(\.id), [stretch.id])
        var marked = plan
        marked.blocks[marked.blocks.firstIndex { $0.id == stretch.id }!].isDeleted = true
        XCTAssertFalse(marked.liveBlocks.contains(where: \.isCooldown))
        XCTAssertEqual(marked.liveBlocks.reduce(0) { $0 + $1.estimatedSeconds }, plan.estimatedSeconds - 600, accuracy: 0.001)
    }

    func testAddedExercisesLandAheadOfTheStretch() {
        let input = input(.push)
        var plan = planner.generate(input)
        let curl = planner.block(adding: Fixtures.catalog.exercises["dumbbell_curl"]!, to: plan, input: input)
        plan.blocks.append(curl)
        XCTAssertTrue(plan.slotOrdered.last!.isCooldown)
        XCTAssertEqual(plan.slotOrdered.dropLast().last?.id, curl.id)

        // With a manual order in place, the added block still slots in before a trailing stretch...
        var edits = DeckEdits()
        let base = plan.slotOrdered.filter { $0.id != curl.id }
        edits.move(fromOffsets: IndexSet(integer: 1), toOffset: 0, in: base)
        edits.add(curl.id, in: ordered(edits, plan.slotOrdered))
        let active = edits.active(ordered(edits, plan.slotOrdered))
        XCTAssertTrue(active.last!.isCooldown)
        XCTAssertEqual(active.dropLast().last?.id, curl.id)

        // ...but goes last when the user has moved the stretch elsewhere.
        var moved = DeckEdits()
        moved.move(fromOffsets: IndexSet(integer: base.count - 1), toOffset: 0, in: base)
        moved.add(curl.id, in: ordered(moved, plan.slotOrdered))
        XCTAssertEqual(moved.active(ordered(moved, plan.slotOrdered)).last?.id, curl.id)
        XCTAssertTrue(moved.active(ordered(moved, plan.slotOrdered)).first!.isCooldown)
    }

    func testStretchCannotBeSwappedOrHaveItsRestEdited() {
        let input = input(.pull)
        var plan = planner.generate(input)
        let stretch = plan.blocks.first(where: \.isCooldown)!
        let swapped = planner.swap(block: stretch, to: Fixtures.catalog.exercises["dumbbell_curl"]!, in: plan, input: input)
        XCTAssertEqual(swapped, plan)
        plan.setRest(of: stretch, to: 90)
        XCTAssertEqual(plan.blocks.first(where: \.isCooldown), stretch)
    }

    func testKindRoundTripsAndOlderPlansDecodeAsExercises() throws {
        let plan = planner.generate(input(.push))
        let decoded = try JSONDecoder().decode(Plan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(decoded, plan)
        XCTAssertTrue(decoded.blocks.last!.isCooldown)

        // A plan saved before `kind` existed: strip the key and every block reads back as a plain exercise.
        var legacy = plan
        legacy.blocks.removeAll(where: \.isCooldown)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        json["blocks"] = (json["blocks"] as! [[String: Any]]).map { var b = $0; b.removeValue(forKey: "kind"); return b }
        let old = try JSONDecoder().decode(Plan.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old, legacy)
        XCTAssertTrue(old.blocks.allSatisfy { $0.kind == .exercise })
    }

    func testCompletingOrSkippingTheStretchLeavesProgressionInputsAlone() {
        // Progression is driven by `progressionBlocks`; the stretch must never appear there, whatever its state.
        var plan = planner.generate(input(.push))
        let keys = plan.progressionBlocks.map(\.exerciseKey)
        XCTAssertFalse(keys.contains(PlanBlock.cooldownExerciseKey))
        XCTAssertNil(Fixtures.catalog.exercises[PlanBlock.cooldownExerciseKey])
        plan.blocks[plan.blocks.firstIndex(where: \.isCooldown)!].isDeleted = true
        XCTAssertEqual(plan.progressionBlocks.map(\.exerciseKey), keys)
    }
}
