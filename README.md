# TEE Simulator Plus

Tricky-Store + KSU WebUI manager — Android key attestation simulator with GUI.

## 構成

このモジュールは2つの部分から成ります:

1. **Tricky-Store core** ([5ec1cff/TrickyStore](https://github.com/5ec1cff/TrickyStore) v1.2.1) — 実際の attestation 証明書チェーン生成 (改変なしで同梱)
2. **KSU WebUI overlay** (本リポジトリ) — keybox アップロード / ターゲットアプリ選択 / タイミング診断の GUI

## 機能

- ✅ **本物の key attestation** — Tricky-Store の Rust core が処理
- ✅ **KSU WebUI** — keybox.xml アップロード、対象アプリ選択を GUI で操作
- ✅ **Tricky-Store 互換ファイル配置** — `/data/adb/tricky_store/keybox.xml`, `target.txt`
- ✅ **タイミング診断** — attested vs non-attested の比較で検知耐性を測定
- ✅ **ログビューア** — モジュール動作ログを WebUI 内で確認

## ビルド

GitHub Actions が自動的に:
1. Tricky-Store の release zip をダウンロード
2. WebUI と統合スクリプトをオーバーレイ
3. 統合された zip を生成

タグ (`v*`) をプッシュすると Release が自動作成されます。

ローカルビルドは不要 (Tricky-Store の core はバイナリ同梱)。

## インストール

1. Releases から `tee-simulator-plus-v*.zip` をダウンロード (CI artifact の場合は外側の zip を解凍して中身を取り出す)
2. KernelSU Manager または Magisk Manager でフラッシュ
3. 再起動
4. KernelSU Manager → モジュール → TEE Simulator Plus → WebUI を開く
5. WebUI から keybox.xml をアップロード、対象アプリを選択

## 対応環境

- Android 10+ (API 29+)
- KernelSU 0.6.0+ (WebUI 必須)
- Magisk 24.0+ (Zygisk 有効、WebUI は KSU Manager 経由のみ)
- arm64-v8a / armeabi-v7a

## ⚠️ タイミングサイドチャネル

ソフトウェア attestation シミュレーションには原理的に計測可能なタイミング差があります:
```
attested 0.932ms non-attested 1.068ms ratio 1.146x threshold > 1.1x → Positive
```

WebUI の Diagnostics タブで自分の構成を診断できます。緩和策の詳細: [TIMING_SIDE_CHANNEL.md](module/docs/TIMING_SIDE_CHANNEL.md)

## クレジット

- **Tricky-Store**: https://github.com/5ec1cff/TrickyStore (GPL-3.0)
- **Tricky-Addon-Update-Target-List**: https://github.com/KOWX712/Tricky-Addon-Update-Target-List (UI inspiration)
- **TEESimulator**: https://github.com/JingMatrix/TEESimulator (initial design reference)

## ライセンス

GPL-3.0 (Tricky-Store core を同梱しているため)
