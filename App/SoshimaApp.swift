import SwiftUI
import UIKit

struct SavedState: Codable {
    var players = ["自分", "プレイヤー2", "プレイヤー3", "プレイヤー4"].map { Player(name: $0) }
    var inputs = Array(repeating: "25000", count: 4)
    var rules = Rules.mLeague
    var records: [GameRecord] = []
    // Optional fields keep drafts from earlier versions readable.
    var inputByRank: Bool?
    var rankOrder: [Int]?
}

@MainActor
final class GameStore: ObservableObject {
    @Published var state: SavedState { didSet { persist() } }
    @Published var storageError: String?
    private let url: URL
    private var canWrite = true

    init() {
        let directory = URL.applicationSupportDirectory.appending(path: "Soshima", directoryHint: .isDirectory)
        url = directory.appending(path: "records.json")
        state = SavedState()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
                guard state.players.count == 4, state.inputs.count == 4, state.rules.uma.count == 4 else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
        } catch {
            canWrite = false
            storageError = "記録を読み込めません。元のデータを保護するため保存を停止しています。\n\(error.localizedDescription)"
            state = SavedState()
        }
    }

    private func persist() {
        guard canWrite else { return }
        do {
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
            storageError = nil
        } catch { storageError = "端末に保存できませんでした。\n\(error.localizedDescription)" }
    }

    func save(_ record: GameRecord) -> Bool {
        guard canWrite else { return false }
        var next = state
        next.records.insert(record, at: 0)
        next.inputs = Array(repeating: String(next.rules.startingPoints), count: 4)
        do {
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
            state = next
            return storageError == nil
        } catch {
            storageError = "記録を保存できませんでした。\n\(error.localizedDescription)"
            return false
        }
    }
}

private let accent = Color(red: 0.78, green: 0.10, blue: 0.16)

/// Shared 1.2× number sizing; still follows the user's Dynamic Type setting.
private struct NumberFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(_ style: Font.TextStyle, weight: Font.Weight, design: Font.Design) {
        let base: CGFloat
        switch style {
        case .largeTitle: base = 34
        case .title: base = 28
        case .title2: base = 22
        case .title3: base = 20
        case .subheadline: base = 15
        case .caption: base = 12
        case .footnote: base = 13
        default: base = 17
        }
        _size = ScaledMetric(wrappedValue: base * 1.2, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design)).monospacedDigit()
    }
}

private extension View {
    func numberFont(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular,
                    design: Font.Design = .default) -> some View {
        modifier(NumberFont(style, weight: weight, design: design))
    }
}

@main
struct SoshimaApp: App {
    @StateObject private var store = GameStore()
    var body: some Scene {
        WindowGroup {
            TabView {
                EntryView().tabItem { Label("点数入力", systemImage: "square.and.pencil") }
                HistoryView().tabItem { Label("記録", systemImage: "clock") }
                RulesView().tabItem { Label("ルール", systemImage: "slider.horizontal.3") }
            }
            .tint(accent)
            .environmentObject(store)
            .safeAreaInset(edge: .top) {
                if let error = store.storageError {
                    Text(error).numberFont(.caption).foregroundStyle(.red)
                        .padding().frame(maxWidth: .infinity).background(.regularMaterial)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
        }
    }
}

struct EntryView: View {
    @EnvironmentObject private var store: GameStore
    @State private var preview: GameRecord?
    @State private var validation: String?
    private enum InputField: Hashable { case name(Int), points(Int) }
    @FocusState private var focused: InputField?
    @State private var recipients: [UUID: UUID] = [:]
    @State private var editingNames = false

    private var isRankMode: Bool { store.state.inputByRank ?? true }
    private var rankOrder: [Int] {
        if let order = store.state.rankOrder, RankedInput.isValidOrder(order) { return order }
        return Array(0..<4)
    }
    private var sortedPlayerIndices: [Int] {
        guard let points else { return Array(0..<4) }
        return (0..<4).sorted { points[$0] == points[$1] ? $0 < $1 : points[$0] > points[$1] }
    }
    private var displayOrder: [Int] { isRankMode ? rankOrder : Array(0..<4) }
    private var rankMode: Binding<Bool> {
        Binding(get: { isRankMode }, set: { value in
            finishInput()
            var next = store.state
            if value { next.rankOrder = sortedPlayerIndices }
            next.inputByRank = value
            store.state = next
            validation = nil
        })
    }

    private func playerSelection(at rank: Int) -> Binding<Int> {
        Binding(get: { rankOrder[rank] }, set: { playerIndex in
            finishInput()
            guard rankOrder[rank] != playerIndex else { return }
            do {
                let selection = try RankedInput.select(playerIndex: playerIndex, at: rank,
                                                       order: rankOrder, inputs: store.state.inputs)
                var next = store.state
                next.rankOrder = selection.order
                next.inputs = selection.inputs
                store.state = next
                validation = nil
                // Changing the assigned points can change who went bankrupt.
                recipients = [:]
            } catch { validation = error.localizedDescription }
        })
    }

    private func focusNextPoint(after playerIndex: Int) {
        guard let row = displayOrder.firstIndex(of: playerIndex), row < 3 else {
            finishInput()
            return
        }
        focused = .points(displayOrder[row + 1])
    }

    private func pointRow(_ row: Int) -> some View {
        let index = displayOrder[row]
        return VStack(alignment: .leading, spacing: 8) {
            if isRankMode {
                Picker(selection: playerSelection(at: row)) {
                    ForEach(0..<4, id: \.self) { playerIndex in
                        Text(store.state.players[playerIndex].name.isEmpty
                             ? "プレイヤー\(playerIndex + 1)" : store.state.players[playerIndex].name)
                            .tag(playerIndex)
                    }
                } label: {
                    Text("\(row + 1)位").numberFont(.title3, weight: .bold)
                        .foregroundStyle(accent)
                }
                .pickerStyle(.menu)
                .accessibilityLabel("\(row + 1)位の名前")
            } else {
                TextField("名前", text: $store.state.players[index].name)
                    .font(.subheadline).textInputAutocapitalization(.never)
                    .focused($focused, equals: .name(index))
                    .submitLabel(.next)
                    .onSubmit { focused = .points(index) }
                    .accessibilityLabel("\(index + 1)人目の名前")
            }
            HStack(alignment: .firstTextBaseline) {
                TextField("25000", text: $store.state.inputs[index])
                    .keyboardType(.numbersAndPunctuation)
                    .numberFont(.largeTitle, weight: .semibold, design: .rounded)
                    .monospacedDigit().focused($focused, equals: .points(index))
                    .submitLabel(row == 3 ? .done : .next)
                    .onSubmit { focusNextPoint(after: index) }
                    .accessibilityLabel("\(store.state.players[index].name)の持ち点")
                Text("点").foregroundStyle(.secondary)
            }
        }.padding(.vertical, 5)
    }

    private var transfers: [BankruptcyTransfer] {
        guard store.state.rules.bankruptcyEnabled, store.state.rules.bankruptcyBonus > 0, let points else { return [] }
        return (0..<4).compactMap { index in
            guard points[index] < 0, let to = recipients[store.state.players[index].id] else { return nil }
            return BankruptcyTransfer(from: store.state.players[index].id, to: to)
        }
    }
    private func finishInput() {
        focused = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var points: [Int]? {
        let values = store.state.inputs.map { Int(($0.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? $0).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")) }
        return values.allSatisfy { $0 != nil } ? values.compactMap { $0 } : nil
    }
    private var difference: Int? {
        guard let points, points.allSatisfy({ (-100_000...200_000).contains($0) }),
              (100...100_000).contains(store.state.rules.startingPoints) else { return nil }
        return store.state.rules.startingPoints * 4 - points.reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("半荘が終わったら、持ち点を入力。")
                            .font(.title3.bold())
                        Text("ウマ・オカ・精算額をまとめて計算します。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                    LabeledContent("いまのルール", value: "\(store.state.rules.startingPoints.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))))点持ち・\(store.state.rules.returnPoints.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))))点返し")
                        .numberFont(.caption)
                    LabeledContent("スコア端数", value: store.state.rules.scoreRounding?.title ?? "端数を残す")
                        .numberFont(.caption)
                }
                Section {
                    Picker("入力方法", selection: rankMode) {
                        Text("順位順").tag(true)
                        Text("名前順").tag(false)
                    }.pickerStyle(.segmented)
                    Button {
                        finishInput()
                        editingNames = true
                    } label: { Label("名前を登録・変更", systemImage: "person.crop.circle.badge.pencil") }
                }
                Section {
                    ForEach(0..<4, id: \.self) { row in
                        pointRow(row)
                    }
                } header: {
                    Text(isRankMode ? "1位から順に、名前と最終持ち点を入力" : "4人の最終持ち点").numberFont(.footnote)
                } footer: {
                    if isRankMode {
                        Text("名前を選ぶと他の順位の名前と入れ替わり、各順位の入力点はそのまま残ります。同点でも入力できます。結果では同順位として計算します。")
                            .numberFont(.caption)
                    }
                }
                if store.state.rules.bankruptcyEnabled, let points, points.contains(where: { $0 < 0 }) {
                    Section("飛び終了") {
                        Label("持ち点が0点未満のため、飛び終了", systemImage: "flag.checkered")
                            .numberFont().foregroundStyle(accent)
                        if store.state.rules.bankruptcyBonus > 0 {
                            ForEach((0..<4).filter { points[$0] < 0 }, id: \.self) { index in
                                Picker("\(store.state.players[index].name)を飛ばした人", selection: Binding<UUID?>(
                                    get: { recipients[store.state.players[index].id] },
                                    set: { recipients[store.state.players[index].id] = $0 }
                                )) {
                                    Text("選択してください").tag(UUID?.none)
                                    ForEach((0..<4).filter { points[$0] >= 0 }, id: \.self) { winner in
                                        Text(store.state.players[winner].name).tag(Optional(store.state.players[winner].id))
                                    }
                                }.pickerStyle(.menu)
                            }
                            Text("飛んだ人から飛ばした人へ、1人につき\(store.state.rules.bankruptcyBonus)スコアを移します。持ち点だけでは相手を特定できないため選択してください。")
                                .numberFont(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    if let difference {
                        Label(difference == 0 ? "合計が一致しています" : "あと\(difference.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))))点で合計が一致",
                              systemImage: difference == 0 ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .numberFont().foregroundStyle(difference == 0 ? accent : .orange)
                    } else {
                        Label("全員の持ち点を数字で入力してください", systemImage: "pencil")
                    }
                    Text("供託は受け取り先に加算してください。同点はウマ・オカを均等に分けます。")
                        .numberFont(.caption).foregroundStyle(.secondary)
                    if let validation { Text(validation).foregroundStyle(.red).numberFont(.callout) }
                    Button {
                        finishInput()
                        do {
                            guard let points else { throw ScoringError.points }
                            if isRankMode { try RankedInput.validate(points: points, order: rankOrder) }
                            _ = try Scoring.calculate(players: store.state.players, points: points, rules: store.state.rules, bankruptcyTransfers: transfers)
                            validation = nil
                            preview = GameRecord(players: store.state.players, points: points, rules: store.state.rules, bankruptcyTransfers: transfers)
                        } catch { validation = error.localizedDescription }
                    } label: {
                        Text("結果を確認する").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 7)
                    }.buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("点数入力")
            .onAppear {
                if !RankedInput.isValidOrder(store.state.rankOrder ?? []) {
                    store.state.rankOrder = sortedPlayerIndices
                }
            }
            .onDisappear { finishInput() }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("次へ") {
                        switch focused {
                        case .name(let index): focused = .points(index)
                        case .points(let index): focusNextPoint(after: index)
                        default: finishInput()
                        }
                    }
                    Button("完了") { finishInput() }
                }
            }
            .sheet(item: $preview) { record in
                NavigationStack {
                    ResultView(record: record, onSave: {
                        if store.save(record) { preview = nil; recipients = [:] }
                    })
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("戻る") { preview = nil } } }
                }
            }
            .sheet(isPresented: $editingNames) {
                PlayerNamesView(players: $store.state.players)
            }
        }
    }
}

private struct PlayerNamesView: View {
    @Binding var players: [Player]
    @State private var names: [String]
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Int?
    @State private var validation: String?

    init(players: Binding<[Player]>) {
        _players = players
        _names = State(initialValue: players.wrappedValue.map(\.name))
    }

    private func finish() {
        focused = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(0..<4, id: \.self) { index in
                        TextField("プレイヤー\(index + 1)", text: $names[index])
                            .focused($focused, equals: index)
                            .textInputAutocapitalization(.never)
                            .submitLabel(index == 3 ? .done : .next)
                            .onSubmit { if index < 3 { focused = index + 1 } else { finish() } }
                            .accessibilityLabel("\(index + 1)人目の名前")
                    }
                } footer: { Text("4人それぞれ違う名前を登録してください。過去の記録の名前は変わりません。") }
                if let validation { Text(validation).foregroundStyle(.red) }
            }
            .navigationTitle("名前を登録・変更")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { finish(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        finish()
                        let trimmedNames = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        guard trimmedNames.allSatisfy({ !$0.isEmpty }), Set(trimmedNames).count == 4 else {
                            validation = ScoringError.names.localizedDescription
                            return
                        }
                        players = players.enumerated().map { index, player in
                            Player(id: player.id, name: trimmedNames[index])
                        }
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("次へ") {
                        if let index = focused, index < 3 { focused = index + 1 } else { finish() }
                    }
                    Button("完了") { finish() }
                }
            }
        }
    }
}

func scoreText(_ score: Double) -> String {
    String(format: "%+.1f", locale: Locale(identifier: "en_US_POSIX"), score)
}

func yenText(_ yen: Int) -> String {
    (yen > 0 ? "+" : "") + yen.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))) + "円"
}

private struct SettlementSummary: View {
    let yen: Int

    private var amount: String {
        yen.magnitude.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))) + "円"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(yen < 0 ? "\(amount)の負け" : yen > 0 ? "\(amount)の勝ち" : "収支は0円")
                .numberFont(.subheadline).foregroundStyle(.secondary)
            Text(yen < 0 ? "全体に支払う合計" : yen > 0 ? "受け取る合計" : "支払い・受け取りなし")
                .font(.subheadline)
            Text(amount).numberFont(.title2, weight: .bold)
                .foregroundStyle(yen < 0 ? accent : .primary)
        }
    }
}

struct ResultView: View {
    let record: GameRecord
    var onSave: (() -> Void)? = nil
    private var rows: [ResultRow] { record.results }
    var body: some View {
        List {
            if record.endedByBankruptcy {
                Section { Label("飛び終了", systemImage: "flag.checkered").foregroundStyle(accent) }
            }
            if let rounding = record.rules.scoreRounding {
                Section("スコアの端数") {
                    Text("\(rounding.title)（1スコア単位）")
                    Text("丸めた後の差分は1位のトップ調整に反映します。同点1位は均等配分するため、調整後に小数が残る場合があります。")
                        .numberFont(.caption).foregroundStyle(.secondary)
                }
            }
            Section("スコア") {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(row.rank)位").numberFont(.title3, weight: .bold).foregroundStyle(.secondary)
                            Text(row.player.name).font(.headline)
                            Spacer()
                            Text(scoreText(row.score)).numberFont(.largeTitle, weight: .bold, design: .rounded)
                                .foregroundStyle(row.score >= 0 ? accent : .primary)
                        }
                        LabeledContent("最終持ち点") {
                            Text("\(row.points.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))))点")
                                .numberFont(.title2, weight: .bold).monospacedDigit()
                        }
                        scoreDetail("素点", units: row.baseUnits)
                        scoreDetail("ウマ", units: row.umaUnits)
                        scoreDetail("オカ", units: row.okaUnits)
                        if row.bankruptcyUnits != 0 {
                            scoreDetail("飛びボーナス", units: row.bankruptcyUnits)
                        }
                        if record.rules.scoreRounding != nil {
                            scoreDetail("端数処理", units: row.roundingUnits)
                        }
                        if row.topAdjustmentUnits != 0 {
                            scoreDetail("トップ調整", units: row.topAdjustmentUnits)
                        }
                        if record.rules.yenPerScore > 0 {
                            HStack {
                                Text("今回の収支").numberFont(.caption)
                                Spacer()
                                Text(yenText(row.yen)).numberFont(.title2, weight: .bold).monospacedDigit()
                            }
                        }
                    }.padding(.vertical, 6)
                }
            }
            Section("精算") {
                if record.rules.yenPerScore == 0 {
                    Text("金額換算はオフです。「ルール」で1スコアあたりの円を設定できます。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(row.player.name).font(.headline)
                            SettlementSummary(yen: row.yen)
                        }.padding(.vertical, 6)
                    }
                    Text("各人の収支をまとめた精算額です。負けた人は表示された合計額を支払います。")
                        .numberFont(.caption).foregroundStyle(.secondary)
                    Text("1スコア = \(record.rules.yenPerScore.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))))円。1円未満は合計が一致するよう端数調整します。")
                        .numberFont(.caption).foregroundStyle(.secondary)
                }
            }
            if let onSave {
                Section {
                    Button(action: onSave) {
                        Text("この結果を保存").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent)
                    Text("保存後もルールと名前は保持されます。次の半荘の入力欄は開始点に戻ります。")
                        .numberFont(.caption).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle(onSave == nil ? "半荘の記録" : "今回の結果")
    }
    private func scoreDetail(_ title: String, units: Int) -> some View {
        LabeledContent(title) {
            Text(scoreText(Double(units) / 60)).numberFont(.title2, weight: .semibold).monospacedDigit()
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var store: GameStore
    @State private var deleting: GameRecord?
    var body: some View {
        NavigationStack {
            List {
                if store.state.records.isEmpty {
                    ContentUnavailableView("記録はまだありません", systemImage: "square.and.pencil",
                                           description: Text("点数を入力して結果を保存すると、ここに残ります。"))
                } else {
                    Section("これまでの合計") {
                        ForEach(store.state.players) { player in
                            let rows = store.state.records.flatMap(\.results).filter { $0.id == player.id }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(player.name)
                                    Spacer()
                                    Text(scoreText(rows.reduce(0) { $0 + $1.score })).numberFont(.title, weight: .bold).monospacedDigit()
                                }
                                SettlementSummary(yen: rows.reduce(0) { $0 + $1.yen })
                            }
                        }
                        Text("累計収支は保存時の単価で集計した結果です。支払い済みかどうかは管理しません。")
                            .numberFont(.caption).foregroundStyle(.secondary)
                    }
                    Section {
                        ForEach(store.state.records) { record in
                            NavigationLink {
                                ResultView(record: record)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.date.formatted(date: .abbreviated, time: .shortened)).numberFont(.headline, weight: .semibold)
                                    if let top = record.results.first {
                                        Text("1位 \(top.player.name)  \(scoreText(top.score))")
                                            .foregroundStyle(.secondary).numberFont(.subheadline)
                                    }
                                }.padding(.vertical, 4)
                            }
                            .swipeActions { Button("削除", role: .destructive) { deleting = record } }
                        }
                    } header: { Text("\(store.state.records.count)半荘").numberFont(.footnote) }
                }
            }.navigationTitle("記録")
                .alert("この記録を削除しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("削除", role: .destructive) {
                        if let deleting { store.state.records.removeAll { $0.id == deleting.id } }
                        deleting = nil
                    }
                    Button("キャンセル", role: .cancel) { deleting = nil }
                } message: { Text("削除した記録は元に戻せません。累計収支も再計算されます。") }
        }
    }
}

struct RulesView: View {
    @EnvironmentObject private var store: GameStore
    @FocusState private var editing: String?
    @State private var customRate = false
    private let rates = [0, 30, 50, 100, 200, 500, 1000]
    private var roundsScores: Binding<Bool> {
        Binding(get: { store.state.rules.scoreRounding != nil },
                set: { enabled in
                    finishEditing()
                    store.state.rules.scoreRounding = enabled ? .nearest : nil
                })
    }
    private var roundingMode: Binding<ScoreRounding> {
        Binding(get: { store.state.rules.scoreRounding ?? .nearest },
                set: { store.state.rules.scoreRounding = $0 })
    }
    private var rateSelection: Binding<Int> {
        Binding(get: { customRate || !rates.contains(store.state.rules.yenPerScore) ? -1 : store.state.rules.yenPerScore },
                set: { value in
                    finishEditing()
                    customRate = value == -1
                    if value != -1 { store.state.rules.yenPerScore = value }
                })
    }
    private func finishEditing() {
        editing = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Mリーグの点数ルールにする") {
                        let rate = store.state.rules.yenPerScore
                        store.state.rules = .mLeague
                        store.state.rules.yenPerScore = rate
                    }
                    Text("25,000点持ち・30,000点返し。順位点は +30 / +10 / −10 / −30。金額換算はこのアプリ独自の設定です。")
                        .numberFont(.caption).foregroundStyle(.secondary)
                }
                Section("持ち点とオカ") {
                    integerField("開始の持ち点", value: $store.state.rules.startingPoints)
                    integerField("返し点", value: $store.state.rules.returnPoints)
                    LabeledContent("オカ合計", value: "\(store.state.rules.oka.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))))点").numberFont()
                    Text("オカ =（返し点 − 開始の持ち点）× 4。通常は1位に加算し、同点1位なら分けます。")
                        .numberFont(.caption).foregroundStyle(.secondary)
                }
                Section("ウマ（順位点）") {
                    ForEach(0..<4, id: \.self) { index in
                        integerField("\(index + 1)位", value: $store.state.rules.uma[index])
                    }
                    Text("合計が0になるよう設定してください。同点は該当順位のウマの平均です。")
                        .numberFont(.caption).foregroundStyle(.secondary)
                }
                Section("スコア端数の処理") {
                    Toggle("1スコア単位に丸める", isOn: roundsScores).numberFont()
                    if let rounding = store.state.rules.scoreRounding {
                        Picker("丸め方", selection: roundingMode) {
                            ForEach(ScoreRounding.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }.pickerStyle(.menu)
                        Text(rounding.explanation).numberFont(.caption).foregroundStyle(.secondary)
                        Text("素点・ウマ・オカ・飛びボーナスを合計したスコアを丸めます。合計が0になるよう差分を1位で調整します。同点1位は均等配分するため、調整後に小数が残る場合があります。")
                            .numberFont(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("小数のスコアをそのまま使います。Mリーグのプリセットでは丸めません。以前のバージョンで保存した記録も端数を保持します。")
                            .numberFont(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("飛び終了") {
                    Toggle("0点未満で終了する", isOn: $store.state.rules.bankruptcyEnabled).numberFont()
                    if store.state.rules.bankruptcyEnabled {
                        integerField("飛ばした人のボーナス", value: $store.state.rules.bankruptcyBonus)
                        Text("単位はスコアです。例：10なら飛んだ人 −10.0、飛ばした人 +10.0。0ならボーナスなし。0点ちょうどでは飛び終了にしません。")
                            .numberFont(.caption).foregroundStyle(.secondary)
                    }
                    Text("Mリーグ設定では飛び終了はオフです。オンにするとカスタムルールになります。")
                        .numberFont(.caption).foregroundStyle(.secondary)
                }
                Section("金額換算（任意）") {
                    Picker("1スコアあたりの円", selection: rateSelection) {
                        ForEach(rates, id: \.self) { rate in
                            Text(rate == 0 ? "換算しない（0円）" : "\(rate)円").tag(rate)
                        }
                        Text("その他").tag(-1)
                    }.pickerStyle(.menu).numberFont(.title3)
                    if rateSelection.wrappedValue == -1 {
                        integerField("その他の金額（円）", value: $store.state.rules.yenPerScore)
                    }
                    Text("0円ならスコアのみ記録します。例：100円なら +42.0 は +4,200円です。")
                        .numberFont(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Text("ルール変更は次に保存する記録に反映されます。過去の記録は保存時のルールを保持します。記録はこのiPhone内に保存され、アプリ削除時は失われます。")
                        .numberFont(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("ルール")
                .onDisappear { finishEditing() }
                .scrollDismissesKeyboard(.interactively)
                .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完了") { finishEditing() } } }
        }
    }

    private func integerField(_ title: String, value: Binding<Int>) -> some View {
        HStack {
            Text(title).numberFont()
            Spacer()
            TextField(title, value: value, format: .number.grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
                .numberFont(.title2, weight: .semibold, design: .rounded)
                .multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation)
                .monospacedDigit().focused($editing, equals: title)
                .submitLabel(.done).onSubmit { finishEditing() }
                .accessibilityLabel(title)
        }
    }
}
