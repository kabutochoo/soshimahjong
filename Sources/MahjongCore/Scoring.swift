import Foundation

public enum RankedInputError: Error, LocalizedError {
    case selection
    case ascending(higherRank: Int, lowerRank: Int)

    public var errorDescription: String? {
        switch self {
        case .selection:
            return "4人の名前を1位から4位まで重複なく選んでください。"
        case let .ascending(higherRank, lowerRank):
            return "\(lowerRank)位の持ち点が\(higherRank)位を上回っています。名前か持ち点を確認してください。"
        }
    }
}

/// Rank rows are a view of the canonical player-indexed input, never new player identities.
public enum RankedInput {
    public struct Selection {
        public let order: [Int]
        public let inputs: [String]
    }

    public static func isValidOrder(_ order: [Int]) -> Bool {
        order.count == 4 && Set(order) == Set(0..<4)
    }

    public static func select(playerIndex: Int, at rankIndex: Int, order: [Int],
                              inputs: [String]) throws -> Selection {
        guard isValidOrder(order), inputs.count == 4, (0..<4).contains(playerIndex),
              (0..<4).contains(rankIndex), let previousRank = order.firstIndex(of: playerIndex) else {
            throw RankedInputError.selection
        }
        var nextOrder = order
        var nextInputs = inputs
        // Keep the points in each visible rank row when its selected name changes.
        nextInputs.swapAt(order[rankIndex], playerIndex)
        nextOrder.swapAt(rankIndex, previousRank)
        return Selection(order: nextOrder, inputs: nextInputs)
    }

    public static func validate(points: [Int], order: [Int]) throws {
        guard points.count == 4, isValidOrder(order) else { throw RankedInputError.selection }
        for rank in 1..<4 where points[order[rank - 1]] < points[order[rank]] {
            throw RankedInputError.ascending(higherRank: rank, lowerRank: rank + 1)
        }
    }
}

public enum ScoreRounding: String, Codable, CaseIterable, Identifiable {
    case up
    case nearest
    case fiveDownSixUp
    case down

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .up: return "切り上げ"
        case .nearest: return "四捨五入"
        case .fiveDownSixUp: return "五捨六入"
        case .down: return "切り捨て"
        }
    }
    public var explanation: String {
        switch self {
        case .up: return "+12.4 → +13、−12.4 → −12。数直線のプラス方向へ丸めます。"
        case .nearest: return "+12.5 → +13、−12.5 → −13。絶対値の小数が0.5以上なら繰り上げます。"
        case .fiveDownSixUp: return "+12.5 → +12、+12.6 → +13。−12.5 → −12、−12.6 → −13。絶対値の小数が0.6以上なら繰り上げます。"
        case .down: return "+12.4 → +12、−12.4 → −13。数直線のマイナス方向へ丸めます。"
        }
    }

    /// Accepts exact 1/60 score units and returns an integer score.
    public func roundedScore(from units: Int) -> Int {
        let whole = units / 60
        let remainder = units % 60
        switch self {
        case .up: return whole + (remainder > 0 ? 1 : 0)
        case .down: return whole - (remainder < 0 ? 1 : 0)
        case .nearest:
            return whole + (abs(remainder) >= 30 ? (units < 0 ? -1 : 1) : 0)
        case .fiveDownSixUp:
            return whole + (abs(remainder) >= 36 ? (units < 0 ? -1 : 1) : 0)
        }
    }
}

public struct Rules: Codable, Equatable {
    public var startingPoints: Int
    public var returnPoints: Int
    public var uma: [Int]
    /// Yen per one score point (1,000 table points).
    public var yenPerScore: Int
    public var bankruptcyEnabled: Bool
    public var bankruptcyBonus: Int
    /// nil preserves fractional scores for M League and records saved before this option existed.
    public var scoreRounding: ScoreRounding?

    private enum CodingKeys: String, CodingKey {
        case startingPoints, returnPoints, uma, yenPerScore, bankruptcyEnabled, bankruptcyBonus, scoreRounding
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startingPoints = try c.decode(Int.self, forKey: .startingPoints)
        returnPoints = try c.decode(Int.self, forKey: .returnPoints)
        uma = try c.decode([Int].self, forKey: .uma)
        yenPerScore = try c.decode(Int.self, forKey: .yenPerScore)
        bankruptcyEnabled = try c.decodeIfPresent(Bool.self, forKey: .bankruptcyEnabled) ?? false
        bankruptcyBonus = try c.decodeIfPresent(Int.self, forKey: .bankruptcyBonus) ?? 10
        scoreRounding = try c.decodeIfPresent(ScoreRounding.self, forKey: .scoreRounding)
    }

    public init(startingPoints: Int = 25_000, returnPoints: Int = 30_000,
                uma: [Int] = [30, 10, -10, -30], yenPerScore: Int = 0,
                bankruptcyEnabled: Bool = false, bankruptcyBonus: Int = 10,
                scoreRounding: ScoreRounding? = nil) {
        self.startingPoints = startingPoints
        self.returnPoints = returnPoints
        self.uma = uma
        self.yenPerScore = yenPerScore
        self.bankruptcyEnabled = bankruptcyEnabled
        self.bankruptcyBonus = bankruptcyBonus
        self.scoreRounding = scoreRounding
    }

    public static let mLeague = Rules()
    public var oka: Int {
        let (difference, overflow) = returnPoints.subtractingReportingOverflow(startingPoints)
        let (value, multipliedOverflow) = difference.multipliedReportingOverflow(by: 4)
        return overflow || multipliedOverflow ? 0 : value
    }
}

public struct Player: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
}

public struct ResultRow: Identifiable, Equatable {
    public var id: UUID { player.id }
    public let player: Player
    public let points: Int
    public let rank: Int
    public let baseUnits: Int
    public let umaUnits: Int
    public let okaUnits: Int
    /// Exact units: 60 units = one score point, including three-way ties.
    public var bankruptcyUnits: Int = 0
    public var roundingUnits: Int = 0
    public var topAdjustmentUnits: Int = 0
    public var rawScoreUnits: Int { baseUnits + umaUnits + okaUnits + bankruptcyUnits }
    public var scoreUnits: Int { rawScoreUnits + roundingUnits + topAdjustmentUnits }
    public var score: Double { Double(scoreUnits) / 60 }
    public var yen: Int
}

public struct Payment: Identifiable, Equatable {
    public var id: String { from.id.uuidString + to.id.uuidString }
    public let from: Player
    public let to: Player
    public let yen: Int
}

public struct BankruptcyTransfer: Codable, Equatable {
    public let from: UUID
    public let to: UUID
    public init(from: UUID, to: UUID) { self.from = from; self.to = to }
}

public enum ScoringError: String, Error, LocalizedError {
    case bankruptcy = "飛んだ人ごとに、飛ばした人を選んでください。飛んだ本人や別の飛んだ人は選べません。"
    case playerCount = "4人分の名前と持ち点を入力してください。"
    case names = "名前は重複しないよう、全員分入力してください。"
    case rules = "持ち点・返し点は100点単位、ウマの合計は0、単価は0〜10,000円、飛びボーナスは0〜1,000スコアにしてください。"
    case points = "持ち点は−100,000〜200,000点の範囲で、100点単位で入力してください。"
    case total = "持ち点の合計が開始時の合計と一致していません。供託を精算してから保存してください。"
    public var errorDescription: String? { rawValue }
}

public enum Scoring {
    public static func calculate(players: [Player], points: [Int], rules: Rules, bankruptcyTransfers: [BankruptcyTransfer] = []) throws -> [ResultRow] {
        guard players.count == 4, points.count == 4, Set(players.map(\.id)).count == 4 else {
            throw ScoringError.playerCount
        }
        let names = players.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard names.allSatisfy({ !$0.isEmpty }), Set(names).count == 4 else { throw ScoringError.names }
        guard (100...100_000).contains(rules.startingPoints),
              (100...100_000).contains(rules.returnPoints),
              rules.startingPoints % 100 == 0, rules.returnPoints % 100 == 0,
              rules.uma.count == 4, rules.uma.allSatisfy({ (-1000...1000).contains($0) }),
              rules.uma.reduce(0, +) == 0, (0...10_000).contains(rules.yenPerScore), (0...1000).contains(rules.bankruptcyBonus) else {
            throw ScoringError.rules
        }
        guard points.allSatisfy({ (-100_000...200_000).contains($0) && $0 % 100 == 0 }) else {
            throw ScoringError.points
        }
        guard points.reduce(0, +) == rules.startingPoints * 4 else { throw ScoringError.total }

        // Seats determine display order only. Tied ranks share the occupied ranks' bonuses.
        let order = (0..<4).sorted { points[$0] == points[$1] ? $0 < $1 : points[$0] > points[$1] }
        var rows: [ResultRow] = []
        var position = 0
        while position < 4 {
            let tied = order.dropFirst(position).prefix { points[$0] == points[order[position]] }
            let count = tied.count
            let bonus = rules.uma[position..<(position + count)].reduce(0, +) * 60 / count
            let oka = position == 0 ? rules.oka * 60 / 1000 / count : 0
            for seat in tied {
                rows.append(ResultRow(player: players[seat], points: points[seat], rank: position + 1,
                                      baseUnits: (points[seat] - rules.returnPoints) * 60 / 1000,
                                      umaUnits: bonus, okaUnits: oka, yen: 0))
            }
            position += count
        }
        let bankruptIDs = Set(players.indices.filter { points[$0] < 0 }.map { players[$0].id })
        if rules.bankruptcyEnabled && rules.bankruptcyBonus > 0 && !bankruptIDs.isEmpty {
            guard bankruptcyTransfers.count == bankruptIDs.count,
                  Set(bankruptcyTransfers.map(\.from)) == bankruptIDs,
                  bankruptcyTransfers.allSatisfy({ transfer in
                      players.contains { $0.id == transfer.to } && !bankruptIDs.contains(transfer.to)
                  }) else { throw ScoringError.bankruptcy }
            for transfer in bankruptcyTransfers {
                for index in rows.indices {
                    if rows[index].id == transfer.from { rows[index].bankruptcyUnits -= rules.bankruptcyBonus * 60 }
                    if rows[index].id == transfer.to { rows[index].bankruptcyUnits += rules.bankruptcyBonus * 60 }
                }
            }
        } else if !bankruptcyTransfers.isEmpty { throw ScoringError.bankruptcy }
        if let rounding = rules.scoreRounding {
            for index in rows.indices {
                let raw = rows[index].rawScoreUnits
                rows[index].roundingUnits = rounding.roundedScore(from: raw) * 60 - raw
            }
            // The top absorbs the residual. Equal first places share it equally, preserving ties.
            let correction = -rows.reduce(0) { $0 + $1.scoreUnits }
            let topIndices = rows.indices.filter { rows[$0].rank == 1 }
            for index in topIndices { rows[index].topAdjustmentUnits = correction / topIndices.count }
        }
        // Largest remainder allocation balances whole yen, including tied fractional amounts.
        let numerators = rows.map { $0.scoreUnits * rules.yenPerScore }
        let floors = numerators.map { Int(floor(Double($0) / 60)) }
        var balances = floors
        let remainder = -floors.reduce(0, +)
        let priority = rows.indices.sorted {
            let a = numerators[$0] - floors[$0] * 60
            let b = numerators[$1] - floors[$1] * 60
            return a == b ? $0 < $1 : a > b
        }
        for index in priority.prefix(max(0, remainder)) { balances[index] += 1 }
        for index in rows.indices { rows[index].yen = balances[index] }
        return rows
    }

    public static func payments(for rows: [ResultRow]) -> [Payment] {
        var debtors = rows.filter { $0.yen < 0 }.map { ($0.player, -$0.yen) }
        var creditors = rows.filter { $0.yen > 0 }.map { ($0.player, $0.yen) }
        var result: [Payment] = []
        var d = 0, c = 0
        while d < debtors.count && c < creditors.count {
            let amount = min(debtors[d].1, creditors[c].1)
            result.append(Payment(from: debtors[d].0, to: creditors[c].0, yen: amount))
            debtors[d].1 -= amount
            creditors[c].1 -= amount
            if debtors[d].1 == 0 { d += 1 }
            if creditors[c].1 == 0 { c += 1 }
        }
        return result
    }
}

public struct GameRecord: Codable, Identifiable {
    public let id: UUID
    public let date: Date
    public let players: [Player]
    public let points: [Int]
    public let rules: Rules
    public let bankruptcyTransfers: [BankruptcyTransfer]?
    public var endedByBankruptcy: Bool { rules.bankruptcyEnabled && points.contains { $0 < 0 } }
    public init(players: [Player], points: [Int], rules: Rules, bankruptcyTransfers: [BankruptcyTransfer] = []) {
        self.id = UUID(); self.date = Date()
        self.players = players; self.points = points; self.rules = rules
        self.bankruptcyTransfers = bankruptcyTransfers
    }
    public var results: [ResultRow] { (try? Scoring.calculate(players: players, points: points, rules: rules, bankruptcyTransfers: bankruptcyTransfers ?? [])) ?? [] }
}
