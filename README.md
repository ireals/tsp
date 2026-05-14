# TEE Simulator Plus

TEE attestation シミュレータ + KSU WebUI 管理画面。[TEESimulator](https://github.com/JingMatrix/TEESimulator) をベースに、[Tricky-Addon](https://github.com/KOWX712/Tricky-Addon-Update-Target-List) の機能を統合。

## 機能

- **カスタム Keybox 管理** — 複数の keybox.xml を保管・選択・切替
- **ターゲットアプリ管理** — attestation フックを適用するアプリを選択
- **KSU WebUI** — KernelSU Manager 内で GUI 操作
- **遅延プロファイラ** — タイミングサイドチャネル検知の自己診断
- **遅延イコライザー** — ジッター注入による検知回避

## ビルド

### 必要環境
- Android NDK r26d 以上

### ローカルビルド
```bash
export ANDROID_NDK_HOME=/path/to/ndk
./build.sh
```

### GitHub CI
`main` ブランチへの push または tag (`v*`) で自動ビルド。  
Artifacts から `tee-simulator-plus-module` zip をダウンロード可能。

## インストール

1. Releases から `.zip` をダウンロード
2. KernelSU Manager または Magisk Manager でインストール
3. 再起動
4. KernelSU Manager → モジュール → TEE Simulator Plus → WebUI を開く

## 対応環境

- Android 10+ (API 29+)
- KernelSU 0.6.0+ (WebUI 完全対応)
- Magisk 24.0+ (Zygisk 有効、WebUI は KSU Manager 経由のみ)
- arm64-v8a / armeabi-v7a

## ⚠️ 既知の制限

ソフトウェア TEE シミュレーションは、ハードウェア TEE と比較して原理的に計測可能なタイミング差を生じます。  
タイミングサイドチャネル検知（例: `ratio 1.146x > threshold 1.1x → Positive`）に対する完全な不可区別性は達成不可能です。  
詳細: [TIMING_SIDE_CHANNEL.md](module/docs/TIMING_SIDE_CHANNEL.md)

## ライセンス

MIT
