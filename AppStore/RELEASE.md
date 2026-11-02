# App Store提出の準備状況

このリポジトリの変更は提出準備です。Appleへのビルドアップロード・審査提出・公開はまだ実行していません。署名付きの配布ビルドもこのクラウドでは作成していません。

## 用意したもの

- オリジナルの1024pxアプリアイコンとXcodeのAssets設定。
- アプリ内「ルール → プライバシーポリシー」。本文は `App/PrivacyPolicy.json`。
- 非追跡・収集なしのPrivacy manifest。現在のコードには申告が必要なRequired Reason APIの直接利用は確認されていないため、API利用理由は空です。SDKや機能を追加したら再確認が必要です。
- `ja/metadata.json`：日本語掲載文の下書き。nullの項目は未設定です。
- `ja/review-notes.md`：機能を隠さず説明した審査用メモ。
- `site/privacy.html` と `site/support.html`：公開用プライバシーポリシーとメール窓口付きサポートページ。まだホスティングしていません。
- `scripts/archive.sh`：Mac用の配布アーカイブ作成コマンド。クラウドではXcodeがないため実行未検証です。
- CIにReleaseシミュレーターのビルド確認を追加。リモート実行結果は未取得です。

## ユーザー側で必要な情報

有効な有料Apple Developer Programの登録と、App Store Connectでアプリを管理できる権限が必要です。無料Personal Teamの実機実行だけでは一般公開できません。Apple IDのパスワード、2段階認証コード、API秘密鍵をチャットへ送らないでください。

公開名は「歌舞伎の鉄板！セット麻雀記録アプリ歌舞賭(KABUTO)」、公開サポートメール・審査メールは kabuto.kabukicho@gmail.com です。サポートURL、プライバシーポリシーURL、著作権者、審査連絡先の氏名・電話は未設定です。審査連絡先はApp Store Connectの専用欄へ入力します。API接続がないため、このクラウドからApp Store Connectの登録・契約・権限を確認できていません。

サポートページには利用者が連絡できる窓口が必要です。指定された公開メールアドレスでサポートページを生成済みです。更新する場合は `python3 scripts/build_store_site.py --contact-email kabuto.kabukicho@gmail.com` を実行します。`site/` を利用するWebサーバーへ公開し、HTTPSでログイン不要で表示できることを確認してからURLをApp Store Connectへ入力してください。生成・コミットしただけでは公開されません。非公開GitHubリポジトリのファイルURLをそのまま指定しないでください。

## 金額換算機能の審査上の確認

アプリには任意の円換算単価、負け金額、支払い・受取合計の表示があります。金銭賭博やその補助機能と判断されるかはAppleの審査・提供地域の法令に関わるため、現時点で適合や承認を保証できません。実際の機能を年齢制限の質問と審査メモで正確に申告し、[App Review Guidelines 5.3](https://developer.apple.com/app-store/review/guidelines/#gaming-gambling-and-lotteries)を確認してください。審査を通すために金額機能を隠したり、実態と違う説明にしたりしないでください。機能の削除は行っていません。

このクラウドからApple公式ページの取得は通信制限で403になったため、最新の規約・必要SDK版・年齢制限の質問はMacのブラウザとApp Store Connectで確認する必要があります。

## Macからの提出手順

1. 最新版の `Soshima.xcodeproj` を開き、署名のTeamとBundle ID（`com.kabutochoo.soshimahjong`）を確認します。既存のiPhone記録を残すため、アプリは削除せず同じBundle IDで更新します。
2. iPhoneで最新版を実行します。名前入力と完了、順位ごとの選択、4種類の端数処理、飛び終了、円換算、保存後の再起動、履歴削除、プライバシー画面を確認します。大きな文字、VoiceOver、ダークモードも確認します。
3. App Store Connectで新規アプリを作成します。Bundle IDは配布ビルドと同じものを使用します。価格・配信地域・コンテンツの権利・年齢制限・契約事項は実態に合わせて入力します。現在の価格設定は未確定です。
4. 「Appのプライバシー」は現在のコードでは開発者によるデータ収集なしです。名前・対局記録は端末内の保存であり、開発者へ送信されません。OSのバックアップやApple側の標準機能とは区別してください。SDKを追加した場合は申告内容を見直します。
5. Xcodeの実行先を「Any iOS Device」にして **Product → Archive**。Organizerで **Validate App**、次に **Distribute App → App Store Connect → Upload** を実行します。Appleが指定する最新のXcode/SDK要件を満たしたMacで行います。
6. 処理完了後、App Store Connectでビルドを選びます。`ja/metadata.json` の掲載文、公開URL、連絡先、実際のiPhoneスクリーンショット、審査メモを登録します。スクリーンショットはこのビルドの実画面を使い、現在のApp Store Connectが求める端末サイズに合わせます。未実装の画面を生成して載せないでください。
7. 最終入力・金額機能の申告を確認して **審査へ提出**。公開方法は初回は手動リリースを推奨します。提出完了はApp Store Connectの状態で確認します。

公式の入口：[App Store Connect](https://appstoreconnect.apple.com/)、[提出手順](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app-for-review/)、[プライバシー情報](https://developer.apple.com/app-store/app-privacy-details/)。これらのページはこのクラウドから内容確認できていません。
