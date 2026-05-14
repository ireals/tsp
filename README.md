# TEE Simulator Plus

[JingMatrix/TEESimulator](https://github.com/JingMatrix/TEESimulator) を fork し、KSU WebUI と Latency Equalizer を組み込んだ Android key attestation シミュレータ。

## 構成

このモジュールは2つの部分から成ります:

1. **TEESimulator core** ([JingMatrix/TEESimulator](https://github.com/JingMatrix/TEESimulator) v3.2+) — 実際の attestation 証明書チェーン生成 (Latency Equalizer patch 込み)
2. **KSU WebUI overlay** (本リポジトリ) — keybox アップロード、対象アプリ選択、タイミング診断、Latency Equalizer 設定の GUI

## 機能

- ✅ **本物の key attestation** — TEESimulator の Kotlin core が処理
- ✅ **Tricky-Store 互換** — `/data/adb/tricky_store/keybox.xml`, `target.txt`
- ✅ **KSU WebUI** — keybox.xml アップロード、対象アプリ選択を GUI で操作
- ✅ **タイミング診断** — attested vs non-attested の比較で検知耐性を測定
- ✅ **Latency Equalizer** — `AttestationPatcher.kt` に注入された Kotlin パッチがリアルタイムで `Thread.sleep()` を挿入し、検知閾値を回避
- ✅ **ログビューア** — モジュール動作ログを WebUI 内で確認

## ビルド

GitHub Actions が自動的に:
1. TEESimulator のソース (main ブランチ) を clone
2. `apply_latency_patch.py` で `AttestationPatcher.kt` に Latency Equalizer を注入
3. Gradle で TEESimulator モジュール zip をビルド
4. WebUI と統合スクリプトをオーバーレイ
5. 完成版 zip を artifact として出力

タグ (`v*`) をプッシュすると Release が自動作成されます。

## インストール

1. Releases から `tee-simulator-plus-v*.zip` をダウンロード (CI artifact の場合は外側の zip を解凍して中身を取り出す)
2. KernelSU Manager または Magisk Manager でフラッシュ
3. 再起動
4. KernelSU Manager → モジュール → TEE Simulator Plus → WebUI を開く
5. WebUI から keybox.xml をアップロード、対象アプリを選択
6. Diagnostics タブで「キャリブレーション」→ 結果に応じて Latency Equalizer を有効化

## Latency Equalizer の使い方

1. **Diagnostics タブ → 実行** で attested vs non-attested の ratio を測定
2. ratio が threshold (1.1) を超えていれば「Positive (検知の可能性)」
3. **キャリブレーション** で参照プロファイルを取得
4. **Latency Equalizer カード** で:
   - 有効化チェック
   - 参照時間 (キャリブレーション結果の `T_n`)
   - 標準偏差 (キャリブレーション結果の `σ`)
   - 検知閾値 (デフォルト 1.1)
5. **設定を保存** → `/data/adb/tricky_store/equalizer.conf` に書き込まれ、TEESimulator daemon が次回 attestation 時に読み込んで `Thread.sleep()` を挿入

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

Latency Equalizer は `Thread.sleep()` で attested 経路に意図的な待機を挿入し、ratio を threshold 以下に保ちます。ただし高度な検知者 (分散・尖度・自己相関を見るもの) には完全には対応できません。詳細: [TIMING_SIDE_CHANNEL.md](module/docs/TIMING_SIDE_CHANNEL.md)

## クレジット

- **TEESimulator**: https://github.com/JingMatrix/TEESimulator (GPL-3.0) — 本モジュールの core
- **Tricky-Addon-Update-Target-List**: https://github.com/KOWX712/Tricky-Addon-Update-Target-List (UI inspiration)

## ライセンス

GPL-3.0 (TEESimulator core を fork しているため)
