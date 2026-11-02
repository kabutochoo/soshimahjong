# App Review notes (copy into App Store Connect)

KABUTO (歌舞賭) is an offline, manual four-player mahjong score and record utility. No sign-in or demo account is required. No account, ads, analytics, third-party SDK, payment processing, deposits, withdrawals, matchmaking, or in-app mahjong gameplay is included.

The app includes an optional yen-per-score calculator. When enabled, it displays a player's net win/loss and total payable/receivable from manually entered table scores. It does not execute or verify any payment. The UI contains score-to-yen presets and custom rates. This feature is disclosed here and in the product description.

## How to test

1. Launch the app. Open 点数入力 (Score Entry). The four default names can be used; 名前を登録・変更 changes them.
2. With the default 25,000 start / 30,000 return rules, enter 42,000 / 31,000 / 18,000 / 9,000 table points in descending rank order.
3. Tap 結果を確認する (Review Result). Expected scores: +62.0 / +11.0 / −22.0 / −51.0. Save with この結果を保存.
4. Open 記録 (Records) to see the saved game and cumulative scores.
5. Open ルール (Rules). 金額換算 enables the optional rate calculator, スコア端数の処理 selects rounding, and 飛び終了 enables negative-points game-end and a configurable bonus.
6. For a bankruptcy example, use 50,000 / 35,000 / 20,000 / −5,000 points with bankruptcy enabled; choose who caused the bankruptcy before reviewing the result.
7. Privacy policy is accessible from ルール → プライバシーポリシー. All records stay in the app's local storage; OS backup behavior depends on the user's settings.
