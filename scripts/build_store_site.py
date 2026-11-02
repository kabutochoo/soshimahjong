#!/usr/bin/env python3
"""Build static privacy/support pages from the bundled policy; does not publish."""
import argparse
import html
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def page(title: str, body: str) -> str:
    return f'''<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title><style>
body{{font:18px/1.8 system-ui,sans-serif;background:#fff9f8;color:#241c1d;margin:0}}
main{{max-width:760px;margin:auto;padding:40px 24px}}h1{{font-size:30px;line-height:1.5}}h2{{font-size:22px;margin-top:32px}}
a{{color:#b71f30}}nav{{margin-bottom:28px}}footer{{margin-top:40px;border-top:1px solid #e9d7d9;padding-top:16px}}
</style></head><body><main><nav><a href="support.html">サポート</a> · <a href="privacy.html">プライバシーポリシー</a></nav>
{body}<footer>歌舞賭(KABUTO)</footer></main></body></html>
'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contact-email", required=True, help="Public support email address")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", args.contact_email):
        parser.error("Enter a valid public support email address")
    policy = json.loads((ROOT / "App/PrivacyPolicy.json").read_text())
    title = "歌舞賭(KABUTO) プライバシーポリシー"
    body = f'<h1>{html.escape(title)}</h1><p>最終更新：{html.escape(policy["updated"])}</p>'
    for section in policy["sections"]:
        body += f'<section><h2>{html.escape(section["title"])}</h2><p>{html.escape(section["body"])}</p></section>'
    destination = ROOT / "site"
    destination.mkdir(exist_ok=True)
    (destination / "privacy.html").write_text(page(title, body))
    contact = html.escape(args.contact_email, quote=True)
    support = f'''<h1>歌舞賭(KABUTO) サポート</h1>
<p>麻雀の持ち点、スコアと対局記録を管理するiPhoneアプリです。</p>
<h2>お問い合わせ</h2><p><a href="mailto:{contact}">{contact}</a></p>
<p>不具合のお問い合わせでは、iPhoneの機種、iOSバージョン、アプリのバージョン、問題が起きる操作をお知らせください。Apple IDのパスワード、認証コード、銀行情報は送らないでください。画像に他の参加者の名前などが写る場合は、必要に応じて隠してください。</p>
<h2>記録を残してアプリを更新したい</h2><p>同じアプリのアップデートとして更新してください。アプリを削除すると端末内の記録が失われます。</p>
<h2>持ち点の合計が合わない</h2><p>4人の最終持ち点の合計が開始時の合計と一致しているか確認してください。供託は受け取り先の持ち点に加算して入力します。</p>
<h2>端数処理の後にトップの点数が変わる</h2><p>4人のスコアの合計が0になるよう、1位でトップ調整を行います。同点1位は差分を均等に分けます。</p>
<h2>記録の訂正・削除</h2><p>記録一覧で対象を左にスワイプし、確認後に削除できます。訂正する場合は削除して入力し直してください。</p>
<h2>データとプライバシー</h2><p>開発者へのデータ送信、広告や追跡はありません。保存先と削除方法は<a href="privacy.html">プライバシーポリシー</a>をご確認ください。</p>'''
    (destination / "support.html").write_text(page("歌舞賭(KABUTO) サポート", support))
    print("Built site/privacy.html and site/support.html (not published).")


if __name__ == "__main__":
    main()
