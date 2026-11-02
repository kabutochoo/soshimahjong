import SwiftUI

struct SavedState: Codable {
    var players = ["自分", "プレイヤー2", "プレイヤー3", "プレイヤー4"].map { Player(name: $0) }
    var inputs = Array(repeating: "25000", count: 4)
    var rules = Rules.mLeague
    var records: [GameRecord] = []
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

private let accent = Color(red: 0.08, green: 0.43, blue: 0.34)

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
                    Text(error).font(.caption).foregroundStyle(.red)
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
    @FocusState private var focused: Int?

    private var points: [Int]? {
        let values = store.state.inputs.map { Int($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")) }
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
                    LabeledContent("いまのルール", value: "\(store.state.rules.startingPoints.formatted())点持ち・\(store.state.rules.returnPoints.formatted())点返し")
                        .font(.caption)
                }
                Section("4人の最終持ち点") {
                    ForEach(0..<4, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("名前", text: $store.state.players[index].name)
                                .font(.subheadline).textInputAutocapitalization(.never)
                                .accessibilityLabel("\(index + 1)人目の名前")
                            HStack(alignment: .firstTextBaseline) {
                                TextField("25000", text: $store.state.inputs[index])
                                    .keyboardType(.numbersAndPunctuation)
                                    .font(.system(.title, design: .rounded).weight(.semibold))
                                    .monospacedDigit().focused($focused, equals: index)
                                    .accessibilityLabel("\(store.state.players[index].name)の持ち点")
                                Text("点").foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 5)
                    }
                }
                Section {
                    if let difference {
                        Label(difference == 0 ? "合計が一致しています" : "あと\(difference.formatted())点で合計が一致",
                              systemImage: difference == 0 ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(difference == 0 ? accent : .orange)
                    } else {
                        Label("全員の持ち点を数字で入力してください", systemImage: "pencil")
                    }
                    Text("供託は受け取り先に加算してください。同点はウマ・オカを均等に分けます。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let validation { Text(validation).foregroundStyle(.red).font(.callout) }
                    Button {
                        focused = nil
                        do {
                            guard let points else { throw ScoringError.points }
                            _ = try Scoring.calculate(players: store.state.players, points: points, rules: store.state.rules)
                            validation = nil
                            preview = GameRecord(players: store.state.players, points: points, rules: store.state.rules)
                        } catch { validation = error.localizedDescription }
                    } label: {
                        Text("結果を確認する").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 7)
                    }.buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("点数入力")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { focused = nil }
                }
            }
            .sheet(item: $preview) { record in
                NavigationStack {
                    ResultView(record: record, onSave: {
                        if store.save(record) { preview = nil }
                    })
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("戻る") { preview = nil } } }
                }
            }
        }
    }
}

func scoreText(_ score: Double) -> String {
    String(format: "%+.1f", score)
}

func yenText(_ yen: Int) -> String {
    (yen > 0 ? "+" : "") + yen.formatted() + "円"
}

struct ResultView: View {
    let record: GameRecord
    var onSave: (() -> Void)? = nil
    private var rows: [ResultRow] { record.results }
    var body: some View {
        List {
            Section("スコア") {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(row.rank)位").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(row.player.name).font(.headline)
                            Spacer()
                            Text(scoreText(row.score)).font(.system(.title2, design: .rounded).bold())
                                .foregroundStyle(row.score >= 0 ? accent : .primary)
                        }
                        Text("\(row.points.formatted())点  ／  素点 \(scoreText(Double(row.baseUnits) / 60))  ウマ \(scoreText(Double(row.umaUnits) / 60))  オカ \(scoreText(Double(row.okaUnits) / 60))")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if record.rules.yenPerScore > 0 {
                            HStack {
                                Text(row.yen >= 0 ? "受け取り" : "支払い").font(.caption)
                                Spacer()
                                Text(yenText(row.yen)).font(.headline).monospacedDigit()
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
                    ForEach(Scoring.payments(for: rows)) { payment in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(payment.from.name) → \(payment.to.name)")
                            Text("\(payment.yen.formatted())円").font(.title3.bold()).monospacedDigit()
                        }
                    }
                    if Scoring.payments(for: rows).isEmpty { Text("支払いはありません。") }
                    Text("1スコア = \(record.rules.yenPerScore.formatted())円。1円未満は合計が一致するよう端数調整します。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let onSave {
                Section {
                    Button(action: onSave) {
                        Text("この結果を保存").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent)
                    Text("保存後もルールと名前は保持されます。次の半荘の入力欄は開始点に戻ります。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle(onSave == nil ? "半荘の記録" : "今回の結果")
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
                                    Text(scoreText(rows.reduce(0) { $0 + $1.score })).bold().monospacedDigit()
                                }
                                Text("累計収支 \(yenText(rows.reduce(0) { $0 + $1.yen }))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("累計収支は保存時の単価で集計した結果です。支払い済みかどうかは管理しません。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("\(store.state.records.count)半荘") {
                        ForEach(store.state.records) { record in
                            NavigationLink {
                                ResultView(record: record)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                    if let top = record.results.first {
                                        Text("1位 \(top.player.name)  \(scoreText(top.score))")
                                            .foregroundStyle(.secondary).font(.subheadline)
                                    }
                                }.padding(.vertical, 4)
                            }
                            .swipeActions { Button("削除", role: .destructive) { deleting = record } }
                        }
                    }
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
    @FocusState private var editing: Bool
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
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("持ち点とオカ") {
                    integerField("開始の持ち点", value: $store.state.rules.startingPoints)
                    integerField("返し点", value: $store.state.rules.returnPoints)
                    LabeledContent("オカ合計", value: "\(store.state.rules.oka.formatted())点")
                    Text("オカ =（返し点 − 開始の持ち点）× 4。通常は1位に加算し、同点1位なら分けます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("ウマ（順位点）") {
                    ForEach(0..<4, id: \.self) { index in
                        integerField("\(index + 1)位", value: $store.state.rules.uma[index])
                    }
                    Text("合計が0になるよう設定してください。同点は該当順位のウマの平均です。小数のスコアは表示時のみ小数1桁に丸めます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("金額換算（任意）") {
                    integerField("1スコアあたりの円", value: $store.state.rules.yenPerScore)
                    Text("0円ならスコアのみ記録します。例：100円なら +42.0 は +4,200円です。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Text("ルール変更は次に保存する記録に反映されます。過去の記録は保存時のルールを保持します。記録はこのiPhone内に保存され、アプリ削除時は失われます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("ルール")
                .scrollDismissesKeyboard(.interactively)
                .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完了") { editing = false } } }
        }
    }

    private func integerField(_ title: String, value: Binding<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.grouping(.never))
                .multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation)
                .monospacedDigit().focused($editing)
                .accessibilityLabel(title)
        }
    }
}
