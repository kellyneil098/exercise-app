import XCTest
@testable import WorkoutEngine

/// The overview's delete / restore / reorder bookkeeping, independent of any gesture.
final class DeckEditsTests: XCTestCase {
    let blocks: [PlanBlock] = {
        let planner = Planner(catalog: Fixtures.catalog)
        let input = PlannerInput(dayType: .push, durationMinutes: 60, location: Fixtures.commercial, heavyRotation: Fixtures.rotation(.push),
                                 states: Fixtures.baseline, recentSessions: [], now: Date(timeIntervalSince1970: 1_800_000_000))
        return planner.generate(input).blocks.sorted { $0.slot < $1.slot }
    }()
    var ids: [UUID] { blocks.map(\.id) }

    override func setUp() {
        super.setUp()
        XCTAssertGreaterThanOrEqual(blocks.count, 4, "fixture plan too small to exercise ordering")
    }

    func testFreshEditsLeaveEverythingActive() {
        let e = DeckEdits()
        XCTAssertEqual(e.active(blocks).map(\.id), ids)
        XCTAssertTrue(e.skippedBlocks(blocks).isEmpty)
        XCTAssertTrue(e.deletedBlocks(blocks).isEmpty)
        XCTAssertTrue(e.order.isEmpty)
    }

    func testDeleteMovesBlockToDeletedWithoutDisturbingTheRest() {
        var e = DeckEdits()
        e.delete(ids[1])
        XCTAssertEqual(e.active(blocks).map(\.id), [ids[0]] + ids[2...])
        XCTAssertEqual(e.deletedBlocks(blocks).map(\.id), [ids[1]])
        XCTAssertTrue(e.isDeleted(ids[1]))
        XCTAssertTrue(e.isSetAside(ids[1]))
        XCTAssertFalse(e.isSkipped(ids[1]))
        XCTAssertTrue(e.order.isEmpty, "deleting is a flag, not a reorder")
    }

    func testDeletingTheHeavyFirstBlockKeepsTheOthersInSlotOrder() {
        var e = DeckEdits()
        e.delete(ids[0])
        XCTAssertEqual(e.active(blocks).map(\.id), Array(ids[1...]))
    }

    func testRestoreDeletedBlockReturnsItToTheEndOfTheActiveDeck() {
        var e = DeckEdits()
        e.delete(ids[1])
        e.restore(ids[1], in: blocks)
        XCTAssertFalse(e.isDeleted(ids[1]))
        XCTAssertTrue(e.deletedBlocks(blocks).isEmpty)
        XCTAssertEqual(e.order, [ids[0]] + ids[2...] + [ids[1]])
    }

    func testRestoreKeepsSetAsideBlocksBehindTheActiveDeck() {
        var e = DeckEdits()
        e.skip(ids[0])
        e.delete(ids[2])
        e.delete(ids[3])
        e.restore(ids[2], in: blocks)
        let active = [ids[1]] + ids[4...] + [ids[2]]
        XCTAssertEqual(Array(e.order.prefix(active.count)), active)
        XCTAssertEqual(Set(e.order.suffix(from: active.count)), [ids[0], ids[3]])
        XCTAssertEqual(e.order.count, ids.count, "every block keeps a place in the manual order")
    }

    func testRestoreWorksForSkippedBlocksToo() {
        var e = DeckEdits()
        e.skip(ids[1])
        XCTAssertEqual(e.skippedBlocks(blocks).map(\.id), [ids[1]])
        e.restore(ids[1], in: blocks)
        XCTAssertTrue(e.skippedBlocks(blocks).isEmpty)
        XCTAssertEqual(e.order.last, ids[1])
    }

    func testDeletingASkippedBlockMovesItBetweenSections() {
        var e = DeckEdits()
        e.skip(ids[1])
        e.delete(ids[1])
        XCTAssertTrue(e.skippedBlocks(blocks).isEmpty)
        XCTAssertEqual(e.deletedBlocks(blocks).map(\.id), [ids[1]])
        e.skip(ids[1])
        XCTAssertTrue(e.deletedBlocks(blocks).isEmpty)
        XCTAssertEqual(e.skippedBlocks(blocks).map(\.id), [ids[1]])
    }

    func testMoveReordersOnlyTheActiveDeck() {
        var e = DeckEdits()
        e.delete(ids[1])
        // Active is [0, 2, 3, ...]; drag the first active row to the end.
        e.move(fromOffsets: IndexSet(integer: 0), toOffset: e.active(blocks).count, in: blocks)
        let expectedActive = Array(ids[2...]) + [ids[0]]
        XCTAssertEqual(Array(e.order.prefix(expectedActive.count)), expectedActive)
        XCTAssertEqual(e.order.last, ids[1], "the deleted block trails the active deck")
        XCTAssertTrue(e.isDeleted(ids[1]))
    }

    func testSectionsAreFilteredFromWhateverOrderTheyAreGiven() {
        var e = DeckEdits()
        e.delete(ids[0])
        e.skip(ids[1])
        let reversed = Array(blocks.reversed())
        XCTAssertEqual(e.active(reversed).map(\.id), Array(ids[2...].reversed()))
        XCTAssertEqual(e.deletedBlocks(reversed).map(\.id), [ids[0]])
        XCTAssertEqual(e.skippedBlocks(reversed).map(\.id), [ids[1]])
    }

    // MARK: Deleted flag in the plan (what syncs)

    func testDeletedFlagDecodesOffForOlderPlans() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(blocks[0])) as! [String: Any]
        json.removeValue(forKey: "isDeleted")
        json.removeValue(forKey: "isCustomAdded")
        let back = try JSONDecoder().decode(PlanBlock.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(back.isDeleted)
        XCTAssertFalse(back.isCustomAdded)
        XCTAssertEqual(back.id, blocks[0].id)
    }

    func testDeletedFlagRoundTripsAndEditsHydrateFromIt() throws {
        var plan = Plan(dayType: .push, durationMinutes: 60, locationKey: "x", blocks: blocks)
        plan.blocks[1].isDeleted = true
        let back = try JSONDecoder().decode(Plan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(back.liveBlocks.map(\.id), ids.filter { $0 != ids[1] })
        let e = DeckEdits(deleted: Set(back.blocks.filter(\.isDeleted).map(\.id)))
        XCTAssertEqual(e.deletedBlocks(back.blocks).map(\.id), [ids[1]])
        XCTAssertEqual(e.active(back.blocks).map(\.id), ids.filter { $0 != ids[1] })
    }

    func testDeletedHostNoLongerPairsItsPartner() {
        var plan = Plan(dayType: .push, durationMinutes: 60, locationKey: "x", blocks: blocks)
        plan.blocks[1].supersetHostID = plan.blocks[0].id
        XCTAssertEqual(plan.host(of: plan.blocks[1])?.id, ids[0])
        XCTAssertEqual(plan.supersetPartner(of: plan.blocks[0])?.id, ids[1])
        plan.blocks[0].isDeleted = true
        XCTAssertNil(plan.host(of: plan.blocks[1]), "partner works standalone while the host is deleted")
        XCTAssertNil(plan.supersetPartner(of: plan.blocks[0]))
        plan.blocks[0].isDeleted = false
        XCTAssertEqual(plan.host(of: plan.blocks[1])?.id, ids[0], "restoring the host pairs them again")
    }
}
