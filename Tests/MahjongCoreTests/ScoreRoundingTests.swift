import XCTest
@testable import MahjongCore

final class ScoreRoundingTests: XCTestCase {
    private let players = ["自分", "あおい", "はる", "そら"].map { Player(name: $0) }
    private let modes: [ScoreRounding] = [.up, .nearest, .fiveDownSixUp, .down]

    func testMathematicalCeilingAndFloorForBothSigns() {
        XCTAssertEqual(ScoreRounding.up.roundedScore(from: 744), 13)   // +12.4
        XCTAssertEqual(ScoreRounding.up.roundedScore(from: -744), -12)
        XCTAssertEqual(ScoreRounding.down.roundedScore(from: 744), 12)
        XCTAssertEqual(ScoreRounding.down.roundedScore(from: -744), -13)
    }

    func testNearestUsesHalfAwayFromZeroAtExactBoundary() {
        XCTAssertEqual(ScoreRounding.nearest.roundedScore(from: 749), 12)
        XCTAssertEqual(ScoreRounding.nearest.roundedScore(from: 750), 13)
        XCTAssertEqual(ScoreRounding.nearest.roundedScore(from: 751), 13)
        XCTAssertEqual(ScoreRounding.nearest.roundedScore(from: -749), -12)
        XCTAssertEqual(ScoreRounding.nearest.roundedScore(from: -750), -13)
        XCTAssertEqual(ScoreRounding.nearest.roundedScore(from: -751), -13)
    }

    func testFiveDownSixUpUsesPointSixRatherThanGreaterThanHalf() {
        for fraction in [30, 31, 35] { // .5 through .5833... stay down in magnitude.
            XCTAssertEqual(ScoreRounding.fiveDownSixUp.roundedScore(from: 720 + fraction), 12)
            XCTAssertEqual(ScoreRounding.fiveDownSixUp.roundedScore(from: -720 - fraction), -12)
        }
        XCTAssertEqual(ScoreRounding.fiveDownSixUp.roundedScore(from: 756), 13)
        XCTAssertEqual(ScoreRounding.fiveDownSixUp.roundedScore(from: -756), -13)
        XCTAssertEqual(ScoreRounding.fiveDownSixUp.roundedScore(from: 779), 13)
        XCTAssertEqual(ScoreRounding.fiveDownSixUp.roundedScore(from: -779), -13)
    }

    func testWholeScoresAndZeroStayUnchangedForEveryMode() {
        for mode in modes {
            for score in [-100, -12, -1, 0, 1, 12, 100] {
                XCTAssertEqual(mode.roundedScore(from: score * 60), score)
            }
        }
    }

    func testRoundingAndTopAdjustmentAreSeparateFromRawBreakdown() throws {
        let rows = try Scoring.calculate(players: players, points: [42400, 31200, 18300, 8100],
                                         rules: Rules(yenPerScore: 100, scoreRounding: .nearest))
        XCTAssertEqual(rows.map(\.rawScoreUnits), [3744, 672, -1302, -3114])
        XCTAssertEqual(rows.map(\.roundingUnits), [-24, -12, -18, -6])
        XCTAssertEqual(rows.map(\.topAdjustmentUnits), [60, 0, 0, 0])
        XCTAssertEqual(rows.map(\.score), [63, 11, -22, -52])
        XCTAssertEqual(rows.map(\.yen), [6300, 1100, -2200, -5200])
        XCTAssertEqual(rows.reduce(0) { $0 + $1.scoreUnits }, 0)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.yen }, 0)
    }

    func testTiedFirstsShareIndivisibleWholeScoreCorrectionEqually() throws {
        let rows = try Scoring.calculate(players: players, points: [35600, 35600, 15100, 13700],
                                         rules: Rules(yenPerScore: 100, scoreRounding: .nearest))
        XCTAssertEqual(rows.map(\.rank), [1, 1, 3, 4])
        XCTAssertEqual(rows.map(\.score), [35.5, 35.5, -25, -46])
        XCTAssertEqual(rows.map(\.topAdjustmentUnits), [-30, -30, 0, 0])
        XCTAssertEqual(rows.map(\.yen), [3550, 3550, -2500, -4600])
    }

    func testCeilingCanBeOffsetByTopZeroSumAdjustment() throws {
        let rows = try Scoring.calculate(players: players, points: [30100, 30000, 25000, 14900],
                                         rules: Rules(scoreRounding: .up))
        XCTAssertEqual(rows.map(\.rawScoreUnits), [3006, 600, -900, -2706])
        XCTAssertEqual(rows.map(\.roundingUnits), [54, 0, 0, 6])
        XCTAssertEqual(rows.map(\.topAdjustmentUnits), [-60, 0, 0, 0])
        XCTAssertEqual(rows.map(\.score), [50, 10, -15, -45])
    }

    func testThreeWayTopTieRetainsExactZeroSum() throws {
        let rows = try Scoring.calculate(players: players, points: [30100, 30100, 30100, 9700],
                                         rules: Rules(yenPerScore: 7, scoreRounding: .nearest))
        XCTAssertEqual(rows.map(\.scoreUnits), [1000, 1000, 1000, -3000])
        XCTAssertEqual(rows.map(\.topAdjustmentUnits), [-20, -20, -20, 0])
        XCTAssertEqual(rows.reduce(0) { $0 + $1.scoreUnits }, 0)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.yen }, 0)
    }

    func testRoundingAppliesAfterBankruptcyBonus() throws {
        let rules = Rules(yenPerScore: 100, bankruptcyEnabled: true, bankruptcyBonus: 10,
                          scoreRounding: .down)
        let transfer = BankruptcyTransfer(from: players[3].id, to: players[1].id)
        let rows = try Scoring.calculate(players: players, points: [50100, 35000, 20000, -5100],
                                         rules: rules, bankruptcyTransfers: [transfer])
        XCTAssertEqual(rows.map(\.bankruptcyUnits), [0, 600, 0, -600])
        XCTAssertEqual(rows.map(\.rawScoreUnits), [4206, 1500, -1200, -4506])
        XCTAssertEqual(rows.map(\.score), [71, 25, -20, -76])
        XCTAssertEqual(rows.map(\.yen), [7100, 2500, -2000, -7600])
    }

    func testSelectedModePersistsWithRecordAndDoesNotChangeOldRecords() throws {
        let points = [42400, 31200, 18300, 8100]
        let original = GameRecord(players: players, points: points, rules: .mLeague)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var rules = try XCTUnwrap(object["rules"] as? [String: Any])
        rules.removeValue(forKey: "scoreRounding")
        object["rules"] = rules
        let legacy = try JSONDecoder().decode(GameRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.rules.scoreRounding)
        XCTAssertEqual(legacy.results, original.results)
        XCTAssertEqual(legacy.results.map(\.score), [62.4, 11.2, -21.7, -51.9])

        let rounded = GameRecord(players: players, points: points,
                                 rules: Rules(scoreRounding: .fiveDownSixUp))
        let copy = try JSONDecoder().decode(GameRecord.self, from: JSONEncoder().encode(rounded))
        XCTAssertEqual(copy.rules.scoreRounding, .fiveDownSixUp)
        XCTAssertEqual(copy.results, rounded.results)
        XCTAssertEqual(legacy.results, original.results)
        XCTAssertNil(Rules.mLeague.scoreRounding)
    }

    func testAllModesConserveScoreAndMoneyAcrossManyGames() throws {
        for mode in modes {
            for a in stride(from: -10000, through: 70000, by: 1700) {
                let rows = try Scoring.calculate(players: players, points: [a, 20000, 21000, 59000 - a],
                                                 rules: Rules(yenPerScore: 7, scoreRounding: mode))
                XCTAssertEqual(rows.reduce(0) { $0 + $1.scoreUnits }, 0)
                XCTAssertEqual(rows.reduce(0) { $0 + $1.yen }, 0)
            }
            let tied = try Scoring.calculate(players: players, points: [25000, 25000, 25000, 25000],
                                             rules: Rules(scoreRounding: mode))
            XCTAssertEqual(tied.map(\.scoreUnits), [0, 0, 0, 0])
        }
    }
}
