import XCTest
@testable import MahjongCore

final class RankedInputTests: XCTestCase {
    private let players = ["自分", "あおい", "はる", "そら"].map { Player(name: $0) }

    func testSelectingAssignedPlayerSwapsNamesAndKeepsPointsInRankRows() throws {
        let inputs = ["42000", "31000", "18000", "9000"]
        let selection = try RankedInput.select(playerIndex: 2, at: 0,
                                               order: [0, 1, 2, 3], inputs: inputs)

        XCTAssertEqual(selection.order, [2, 1, 0, 3])
        XCTAssertEqual(selection.inputs, ["18000", "31000", "42000", "9000"])
        XCTAssertEqual(selection.order.map { selection.inputs[$0] }, inputs)
        XCTAssertEqual(Set(selection.order).count, 4)
    }

    func testPermutedSelectionSavesScoresUnderCorrectPlayerIDs() throws {
        let order = [3, 0, 2, 1]
        let inputs = ["31000", "9000", "18000", "42000"]
        let selection = try RankedInput.select(playerIndex: 2, at: 0, order: order, inputs: inputs)

        XCTAssertEqual(selection.order, [2, 0, 3, 1])
        XCTAssertEqual(selection.inputs, ["31000", "9000", "42000", "18000"])
        XCTAssertEqual(selection.order.map { selection.inputs[$0] }, order.map { inputs[$0] })
        let points = try selection.inputs.map { try XCTUnwrap(Int($0)) }
        try RankedInput.validate(points: points, order: selection.order)
        let record = GameRecord(players: players, points: points, rules: .mLeague)
        XCTAssertEqual(record.results.map(\.id), [players[2].id, players[0].id, players[3].id, players[1].id])
        XCTAssertEqual(record.results.map(\.score), [62, 11, -22, -51])
        XCTAssertEqual(record.players, players)
        XCTAssertEqual(record.points, [31000, 9000, 42000, 18000])
    }

    func testSelectingSamePlayerDoesNotChangeDraft() throws {
        let order = [3, 0, 2, 1]
        let inputs = ["31000", "9000", "", "42000"]
        let selection = try RankedInput.select(playerIndex: 0, at: 1, order: order, inputs: inputs)

        XCTAssertEqual(selection.order, order)
        XCTAssertEqual(selection.inputs, inputs)
    }

    func testSwappingBackRestoresNamesAndUnparsedDraftInputs() throws {
        let order = [3, 0, 2, 1]
        let inputs = ["31,000", "-5000", "", "未入力"]
        let first = try RankedInput.select(playerIndex: 2, at: 0, order: order, inputs: inputs)
        let restored = try RankedInput.select(playerIndex: 3, at: 0,
                                              order: first.order, inputs: first.inputs)

        XCTAssertEqual(restored.order, order)
        XCTAssertEqual(restored.inputs, inputs)
    }

    func testInvalidSelectionsThrowInsteadOfIndexingInvalidArrays() {
        let validOrder = [0, 1, 2, 3]
        let inputs = ["42000", "31000", "18000", "9000"]
        for invalid in [-1, 4, Int.max] {
            XCTAssertThrowsError(try RankedInput.select(playerIndex: invalid, at: 0,
                                                       order: validOrder, inputs: inputs))
            XCTAssertThrowsError(try RankedInput.select(playerIndex: 0, at: invalid,
                                                       order: validOrder, inputs: inputs))
        }
        for order in [[], [0, 1, 2], [0, 1, 2, 3, 4], [0, 1, 1, 3], [-1, 0, 1, 2], [0, 1, 2, 4]] {
            XCTAssertThrowsError(try RankedInput.select(playerIndex: 0, at: 0, order: order, inputs: inputs))
        }
        for invalidInputs in [[], ["1", "2", "3"], ["1", "2", "3", "4", "5"]] {
            XCTAssertThrowsError(try RankedInput.select(playerIndex: 0, at: 0,
                                                       order: validOrder, inputs: invalidInputs))
        }
    }

    func testValidateUsesDisplayedRankOrderAndAllowsTies() throws {
        try RankedInput.validate(points: [31000, 9000, 42000, 18000], order: [2, 0, 3, 1])
        XCTAssertThrowsError(try RankedInput.validate(points: [42000, 31000, 18000, 9000],
                                                     order: [2, 0, 3, 1]))
        try RankedInput.validate(points: [35000, 35000, 20000, 10000], order: [1, 0, 2, 3])
        try RankedInput.validate(points: [25000, 25000, 25000, 25000], order: [3, 1, 0, 2])
    }

    func testValidateRejectsMalformedCountsAndPermutations() {
        for points in [[], [1, 2, 3], [1, 2, 3, 4, 5]] {
            XCTAssertThrowsError(try RankedInput.validate(points: points, order: [0, 1, 2, 3]))
        }
        for order in [[], [0, 1, 2], [0, 1, 2, 3, 4], [0, 1, 1, 3], [-1, 0, 1, 2], [0, 1, 2, 4]] {
            XCTAssertThrowsError(try RankedInput.validate(points: [42000, 31000, 18000, 9000], order: order))
        }
    }
}
