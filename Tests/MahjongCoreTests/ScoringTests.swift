import XCTest
@testable import MahjongCore

final class ScoringTests: XCTestCase {
    let players = ["自分", "あおい", "はる", "そら"].map { Player(name: $0) }

    func testMLeagueExampleAndTransfers() throws {
        var rules = Rules.mLeague
        rules.yenPerScore = 100
        let rows = try Scoring.calculate(players: players, points: [42000, 31000, 18000, 9000], rules: rules)
        XCTAssertEqual(rows.map(\.score), [62, 11, -22, -51])
        XCTAssertEqual(rows.map(\.yen), [6200, 1100, -2200, -5100])
        XCTAssertEqual(rows.reduce(0) { $0 + $1.scoreUnits }, 0)
        let payments = Scoring.payments(for: rows)
        for row in rows {
            let received = payments.filter { $0.to.id == row.id }.reduce(0) { $0 + $1.yen }
            let paid = payments.filter { $0.from.id == row.id }.reduce(0) { $0 + $1.yen }
            XCTAssertEqual(received - paid, row.yen)
        }
    }

    func testTiedFirstShareUmaAndOka() throws {
        let rows = try Scoring.calculate(players: players, points: [35000, 35000, 20000, 10000], rules: .mLeague)
        XCTAssertEqual(rows.map(\.rank), [1, 1, 3, 4])
        XCTAssertEqual(rows.map(\.score), [35, 35, -20, -50])
    }

    func testThreeWayTieRetainsExactZeroSum() throws {
        let rules = Rules(uma: [30, 10, 0, -40], yenPerScore: 7)
        let rows = try Scoring.calculate(players: players, points: [30000, 30000, 30000, 10000], rules: rules)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.scoreUnits }, 0)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.yen }, 0)
        XCTAssertEqual(rows.map(\.yen), [140, 140, 140, -420])
    }

    func testFourWayTieIsZero() throws {
        let rows = try Scoring.calculate(players: players, points: [25000, 25000, 25000, 25000], rules: .mLeague)
        XCTAssertEqual(rows.map(\.score), [0, 0, 0, 0])
    }

    func testNegativePointsAndFractionalYen() throws {
        let rows = try Scoring.calculate(players: players, points: [50100, 30000, 25000, -5100], rules: Rules(yenPerScore: 3))
        XCTAssertEqual(rows.reduce(0) { $0 + $1.yen }, 0)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.scoreUnits }, 0)
        for row in rows { XCTAssertLessThan(abs(Double(row.yen) - row.score * 3), 1) }
    }

    func testInvalidTotalAndUnitsRejected() {
        XCTAssertThrowsError(try Scoring.calculate(players: players, points: [25000, 25000, 25000, 24000], rules: .mLeague)) {
            XCTAssertEqual($0 as? ScoringError, .total)
        }
        XCTAssertThrowsError(try Scoring.calculate(players: players, points: [25001, 24999, 25000, 25000], rules: .mLeague))
    }

    func testBadRulesAndDuplicateNamesRejected() {
        XCTAssertThrowsError(try Scoring.calculate(players: players, points: [25000, 25000, 25000, 25000], rules: Rules(uma: [30, 10, -10, -20])))
        let duplicates = ["自分", "自分", "はる", "そら"].map { Player(name: $0) }
        XCTAssertThrowsError(try Scoring.calculate(players: duplicates, points: [25000, 25000, 25000, 25000], rules: .mLeague))
    }

    func testRecordRoundTripKeepsOriginalRules() throws {
        let original = GameRecord(players: players, points: [42000, 31000, 18000, 9000], rules: Rules(yenPerScore: 100))
        let copy = try JSONDecoder().decode(GameRecord.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(copy.id, original.id)
        XCTAssertEqual(copy.results, original.results)
        XCTAssertEqual(copy.rules.yenPerScore, 100)
    }

    func testManyGamesConserveScoreAndMoney() throws {
        for a in stride(from: -10000, through: 70000, by: 1700) {
            let points = [a, 20000, 21000, 59000 - a]
            for rate in [0, 1, 7, 100] {
                let rows = try Scoring.calculate(players: players, points: points, rules: Rules(yenPerScore: rate))
                XCTAssertEqual(rows.reduce(0) { $0 + $1.scoreUnits }, 0)
                XCTAssertEqual(rows.reduce(0) { $0 + $1.yen }, 0)
            }
        }
    }
}
