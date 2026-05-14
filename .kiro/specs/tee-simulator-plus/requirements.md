# Requirements Document

## Introduction

TEE Simulator Plus は、Android 端末向けの KernelSU/Magisk モジュールとして提供される TEE (Trusted Execution Environment) attestation シミュレータである。本機能は [TEESimulator](https://github.com/JingMatrix/TEESimulator) の attestation 偽装エンジンを基盤とし、[Tricky-Addon-Update-Target-List](https://github.com/KOWX712/Tricky-Addon-Update-Target-List) が提供する KSU WebUI ベースの GUI 管理体験 (keybox 選択 / ターゲットアプリ管理) を統合する。

加えて、ハードウェア裏付け (hardware-backed) の keybox と比較してシミュレート操作に固有の遅延が生じる点を検知側が悪用しうるため、本機能は (a) 自己診断機構によりユーザーが検知耐性を測定でき、(b) 遅延補正機構により attested 経路と non-attested 経路の実行時間比 (ratio) を一定以下に抑える。

### 既知の根本的限界

ソフトウェアによる TEE シミュレーションは、ハードウェア TEE と比較して原理的に計測可能なタイミング差を生じる。これはソフトウェアシミュレータの根本的限界であり、完全な不可区別性 (indistinguishability) は達成不可能である。本モジュールは緩和策を提供するが、高度な検知者に対する完全な回避を保証しない。

## Glossary

- **TEE_Simulator_Plus**: 本仕様で定義する KernelSU/Magisk モジュール本体。以下のサブシステムを内包する。
- **Module_Installer**: KernelSU/Magisk 互換 zip 形式パッケージを介してモジュールを導入・更新・削除する処理系。`customize.sh` がインストール時のエントリポイントとなる。
- **Keybox_Store**: keybox XML ファイルおよびそのメタデータ (ハッシュ、追加日時、表示名) を保持する永続化領域。
- **Keybox_Parser**: keybox XML を内部表現にパース、および内部表現を keybox XML にシリアライズするコンポーネント。Google AVB の keybox スキーマ (ルート要素 `AndroidAttestation`、`Keybox` および `Key` 要素、PEM 形式 `PrivateKey`、PEM 形式の証明書チェーン) に従う。
- **Keybox_Manager**: Keybox_Store に対する CRUD と「現在使用中の keybox」の選択状態を管理する。
- **Target_List**: attestation フックを適用する対象 Android パッケージ名 (例: `com.google.android.gms`) の集合。
- **Target_List_Manager**: Target_List に対する追加・削除・一括インポート/エクスポートと、Tricky-Addon 互換の `target.txt` 形式での同期を行うコンポーネント。
- **Attestation_Hook**: 対象プロセス内で `keystore2` AIDL クライアント呼び出しおよび関連 JNI 経路を LSPlt によりフックし、選択中 keybox を用いた偽装 attestation 応答を生成するネイティブコンポーネント。
- **Latency_Profiler**: attested 操作と non-attested 操作の実行時間を CPU 親和性を固定して計測し、ratio (T_n ÷ T_a) と filteredBadSamples を算出する診断コンポーネント。
- **Latency_Equalizer**: 偽装 attestation 経路 (attested 経路) に意図的な待機を挿入することで、attested の所要時間を Hardware_Backed_Keybox プロファイルに近づけ、ratio を Detection_Threshold 未満に保つコンポーネント。
- **Detection_Threshold**: 検知側が "Positive" 判定するとされる ratio (= T_n ÷ T_a) の上限。本仕様の既定値は 1.1 倍とする。
- **T_a**: 1 回の attested 操作 (keystore2 attestation 呼び出し) の平均所要時間 (ミリ秒)。
- **T_n**: 1 回の non-attested 操作 (attestation を伴わない keystore2 操作) の平均所要時間 (ミリ秒)。
- **Timing_Side_Channel**: attested 経路と non-attested 経路の実行時間差を統計的に計測し、ソフトウェアシミュレーションの存在を推定する検知手法。
- **WebUI_Server**: モジュール内に同梱され、KernelSU WebUI からロードされる静的アセット (HTML/JS/CSS) と、それを駆動するローカル IPC エンドポイントの総称。
- **WebUI_Client**: KernelSU Manager 内 WebView から WebUI_Server を表示する利用者インターフェース。
- **Shell_Bridge**: WebUI_Client から `ksu.exec()` API を介してルート権限のシェルコマンドを実行し、結果を WebUI_Client に返却する通信層。
- **Detection_Test_Module**: Latency_Profiler の結果を WebUI_Client に表示し、現在構成での検知可否を判定する自己診断機構。
- **Configuration_Store**: 選択中 keybox ID、Detection_Threshold、Target_List、ログ詳細度などの設定値を保持する永続化領域。
- **Module_Log**: 本モジュールが書き出す診断ログ。`/data/adb/modules/tee-simulator-plus/logs/` 配下に保存する。
- **Sample_Count**: Latency_Profiler が 1 回の測定セッションで採取するサンプル数。
- **Hardware_Backed_Keybox**: 端末の TEE/StrongBox に格納された正規 keybox。シミュレートではない経路の参照点。
- **CPU_Pinning**: 計測精度向上のため、プロファイラスレッドを特定の CPU コアに固定する手法。
- **Jitter_Injection**: 固定値の待機時間による検知シグネチャを防ぐため、乱数ノイズを待機時間に加算する手法。
- **Pre_Warming**: JIT コンパイルやキャッシュ効果による初回計測の偏りを排除するため、計測前にダミー呼び出しを行う手法。

## Module Structure

本モジュールは以下のディレクトリ構造で配布される:

```
tee-simulator-plus/
├── META-INF/
│   └── com/google/android/
│       ├── update-binary
│       └── updater-script
├── module.prop                  # モジュールメタデータ
├── customize.sh                 # インストール時スクリプト (環境検証、ファイル配置)
├── post-fs-data.sh              # ブート初期段階スクリプト (フック準備)
├── service.sh                   # ブート完了後スクリプト (サービス起動)
├── system/                      # システムオーバーレイ (必要に応じて)
├── webroot/                     # KSU WebUI 静的アセット
│   ├── index.html
│   ├── app.js
│   ├── style.css
│   └── assets/
├── libs/                        # ネイティブライブラリ (Attestation_Hook)
│   ├── arm64-v8a/
│   └── armeabi-v7a/
├── scripts/                     # Shell_Bridge バックエンドスクリプト
│   ├── keybox_manager.sh
│   ├── target_manager.sh
│   ├── latency_profiler.sh
│   └── config_manager.sh
├── keyboxes/                    # Keybox_Store (実行時に生成)
├── config/                      # Configuration_Store
│   └── config.json
└── logs/                        # Module_Log
    └── module.log
```

## Requirements

### Requirement 1: KernelSU/Magisk モジュールとしての配布と導入

**User Story:** As an Android 端末利用者, I want TEE Simulator Plus を KernelSU または Magisk モジュールとしてインストールしたい, so that 既存のルート環境に追加コンポーネント無しで導入できる.

#### Acceptance Criteria

1. THE Module_Installer SHALL Magisk 互換 zip 形式 (`META-INF/com/google/android/update-binary`、`module.prop`、`customize.sh`、`post-fs-data.sh`、`service.sh`、`webroot/` を含む) のパッケージを生成する。
2. WHEN モジュール zip が KernelSU Manager または Magisk Manager 経由でインストールされる, THE Module_Installer SHALL `/data/adb/modules/tee-simulator-plus/` 配下にモジュールファイル一式を配置する。
3. THE `module.prop` SHALL `id=tee-simulator-plus`、`name=TEE Simulator Plus`、`version`、`versionCode`、`author`、`description`、`updateJson` の各キーを含む。
4. WHEN `customize.sh` が実行される, THE Module_Installer SHALL 端末の CPU アーキテクチャ (`arm64-v8a` または `armeabi-v7a`) を検出し、対応するネイティブライブラリのみを配置する。
5. IF KernelSU カーネルインタフェースも Magisk デーモンも検出されない, THEN THE Module_Installer SHALL インストールを中断し、`abort` メッセージに KernelSU または Magisk が必要である旨を出力する。
6. WHEN ユーザーが Manager 上でモジュールを無効化または削除する, THE TEE_Simulator_Plus SHALL 次回起動時から Attestation_Hook を読み込まない。
7. WHEN `post-fs-data.sh` が実行される, THE TEE_Simulator_Plus SHALL Attestation_Hook のネイティブライブラリを Zygisk または LSPlt 経由で対象プロセスに注入する準備を行う。
8. WHEN `service.sh` が実行される, THE TEE_Simulator_Plus SHALL Configuration_Store を読み込み、Latency_Equalizer の参照プロファイルが存在する場合はプリウォーミングを実行する。

### Requirement 2: Keybox の永続化と選択

**User Story:** As an 利用者, I want 複数の keybox を保管し、その中から 1 つを「使用中」として選択したい, so that 用途に応じて使用 keybox を切り替えられる.

#### Acceptance Criteria

1. THE Keybox_Store SHALL keybox XML ファイルを `/data/adb/modules/tee-simulator-plus/keyboxes/` 配下に SHA-256 ハッシュをファイル名 (`<hash>.xml`) としたコピーとして保存する。
2. THE Keybox_Manager SHALL 各 keybox に対して `id` (SHA-256)、`displayName`、`addedAt` (UNIX エポック秒)、`certificateSubject`、`keyAlgorithm` のメタデータを Configuration_Store に保持する。
3. WHEN 利用者が WebUI_Client から keybox ファイルをアップロードする, THE Keybox_Manager SHALL 当該ファイルを Keybox_Parser で検証してから Keybox_Store に追加する。
4. WHEN 利用者が WebUI_Client から keybox を「使用中」に設定する, THE Keybox_Manager SHALL Configuration_Store の `activeKeyboxId` を当該 keybox の `id` に更新する。
5. IF `activeKeyboxId` に対応する keybox が Keybox_Store から削除されている, THEN THE Keybox_Manager SHALL `activeKeyboxId` を未選択状態 (空文字) に変更し、WebUI_Client に通知する。
6. WHEN 利用者が WebUI_Client から keybox を削除する, THE Keybox_Manager SHALL Keybox_Store と Configuration_Store のメタデータの双方から該当エントリを除去する。
7. THE Keybox_Store SHALL ファイルパーミッションを `0600` (所有者のみ読み書き) に設定し、keybox の秘密鍵を保護する。

### Requirement 3: Keybox XML のパースとシリアライズ

**User Story:** As an 開発者, I want keybox XML を内部表現と相互変換できる, so that 検証・編集・保管の各処理が一貫した形式で行える.

#### Acceptance Criteria

1. THE Keybox_Parser SHALL 入力 XML が `AndroidAttestation/Keybox/Key` 構造、PEM 形式の `PrivateKey`、PEM 形式の `CertificateChain` を持つことを検証する。
2. WHEN Keybox_Parser が構造的に妥当な keybox XML を受け取る, THE Keybox_Parser SHALL 内部表現 (鍵アルゴリズム、秘密鍵 DER バイト列、証明書 DER バイト列リスト) を返す。
3. IF 入力 XML が必須要素または属性を欠く, THEN THE Keybox_Parser SHALL エラーコード `INVALID_KEYBOX_SCHEMA` と欠如した要素名を含む診断情報を返す。
4. IF `PrivateKey` または `Certificate` の PEM デコードに失敗する, THEN THE Keybox_Parser SHALL エラーコード `INVALID_PEM_ENCODING` を返す。
5. THE Keybox_Parser SHALL 内部表現を入力と意味的に等価な keybox XML にシリアライズする pretty printer を提供する。
6. FOR ALL Keybox_Parser が `INVALID_KEYBOX_SCHEMA` または `INVALID_PEM_ENCODING` を返さなかった入力 XML, THE Keybox_Parser SHALL `parse → print → parse` の結果が初回 `parse` の内部表現と等価になることを保証する (round-trip property)。

### Requirement 4: ターゲットアプリリストの管理

**User Story:** As an 利用者, I want attestation フックを適用するアプリを WebUI から管理したい, so that 必要なアプリだけを対象にして副作用を最小化できる.

#### Acceptance Criteria

1. THE Target_List_Manager SHALL Target_List を Configuration_Store に Android パッケージ名 (RFC 1035 準拠のドット区切り文字列) の集合として保存する。
2. WHEN 利用者が WebUI_Client からインストール済みアプリ一覧を要求する, THE Shell_Bridge SHALL `pm list packages -3` 相当の情報 (パッケージ名、アプリ名) を返却する。
3. WHEN 利用者が WebUI_Client でパッケージを Target_List に追加する, THE Target_List_Manager SHALL Configuration_Store を更新し、対象パッケージの次回起動から Attestation_Hook の対象とする。
4. WHEN 利用者が WebUI_Client でパッケージを Target_List から除外する, THE Target_List_Manager SHALL Configuration_Store を更新し、対象パッケージの次回起動から Attestation_Hook を適用しない。
5. THE Target_List_Manager SHALL Tricky-Addon 互換形式 (`target.txt`、1 行 1 パッケージ名、`#` をコメント開始記号とする) でのインポートおよびエクスポートを提供する。
6. IF Target_List に同一パッケージ名が重複して追加される, THEN THE Target_List_Manager SHALL 集合のままとし重複登録を行わない。
7. WHEN 利用者が WebUI_Client で検索文字列を入力する, THE WebUI_Client SHALL パッケージ名またはアプリ名に対する部分一致フィルタリングを提供する。

### Requirement 5: KSU WebUI による管理画面

**User Story:** As an 利用者, I want KernelSU WebUI 上で keybox 選択・ターゲット管理・診断を実行したい, so that ターミナル操作なしで本機能を運用できる.

#### Acceptance Criteria

1. THE WebUI_Server SHALL `/data/adb/modules/tee-simulator-plus/webroot/` 配下に静的アセット (`index.html`、JavaScript、CSS) を配置する。
2. WHEN KernelSU Manager がモジュールを WebUI 対応として認識する, THE WebUI_Client SHALL `index.html` を WebView でロードする。
3. THE WebUI_Client SHALL 以下の画面セクションを提供する: (a) Keybox 一覧と選択パネル、(b) ターゲットアプリ一覧と切替パネル、(c) 遅延診断パネル (Detection_Test_Module)、(d) ステータスパネル (モジュール有効/無効、使用中 keybox、Target_List 件数)、(e) ログビューア (Module_Log 末尾表示)。
4. WHEN WebUI_Client が永続化操作 (keybox 追加、選択、削除、Target_List 編集、設定変更) を実行する, THE Shell_Bridge SHALL `ksu.exec()` API を介してルート権限でバックエンドスクリプトを実行し、結果を JSON 形式で WebUI_Client へ返却する。
5. IF Shell_Bridge が Configuration_Store の更新に失敗する, THEN THE WebUI_Server SHALL エラー応答 (`status` フィールドに数値エラーコード、`message` に原因) を返却し、Module_Log に詳細を記録する。
6. THE WebUI_Client SHALL Material Design 3 準拠のダークテーマを既定とし、KernelSU Manager の外観と調和する UI を提供する。

### Requirement 6: Shell Bridge バックエンド

**User Story:** As an WebUI 開発者, I want WebUI_Client からルート権限の操作を安全に実行したい, so that keybox 管理やシステム情報取得を WebView 内から行える.

#### Acceptance Criteria

1. THE Shell_Bridge SHALL `ksu.exec()` JavaScript API を介して `/data/adb/modules/tee-simulator-plus/scripts/` 配下のシェルスクリプトを実行する。
2. WHEN WebUI_Client がコマンドを発行する, THE Shell_Bridge SHALL コマンド名とパラメータを JSON でエンコードし、対応するスクリプトに引数として渡す。
3. THE Shell_Bridge SHALL 各スクリプトの標準出力を JSON 形式で返却し、`{"status": 0, "data": ...}` (成功) または `{"status": <非ゼロ>, "message": "..."}` (失敗) の構造を保証する。
4. IF Shell_Bridge に未定義のコマンド名が渡される, THEN THE Shell_Bridge SHALL `{"status": 400, "message": "Unknown command"}` を返却する。
5. THE Shell_Bridge SHALL 実行可能なコマンドをホワイトリスト方式で制限し、任意のシェルコマンド実行を許可しない。
6. WHEN Shell_Bridge がスクリプトを実行する, THE Shell_Bridge SHALL 実行タイムアウトを 30 秒に設定し、超過時にプロセスを終了して `{"status": 408, "message": "Timeout"}` を返却する。

### Requirement 7: Attestation 経路のフック (TEESimulator ベース)

**User Story:** As an 利用者, I want Target_List のアプリで keystore2 attestation 呼び出しを偽装した keybox に差し替えたい, so that 選択中 keybox を用いた attestation 応答が得られる.

#### Acceptance Criteria

1. WHEN 対象アプリプロセスが zygote から fork される, THE Attestation_Hook SHALL Zygisk/LSPlt を用いて `keystore2` の attestation 関連経路 (`generateKey`、`attestKey`) をフックする。
2. WHILE 対象プロセスのパッケージ名が Target_List に含まれる, THE Attestation_Hook SHALL `attestKey` 呼び出しを傍受し、Keybox_Manager から取得した使用中 keybox による証明書チェーンを応答として返す。
3. IF Target_List に含まれないプロセスにフックがロードされる, THEN THE Attestation_Hook SHALL 当該プロセスでフックを解除し、元の関数ポインタへ復帰する。
4. IF 使用中 keybox が未選択 (`activeKeyboxId` が空) である, THEN THE Attestation_Hook SHALL `attestKey` 呼び出しを偽装せず、元の実装にパススルーする。
5. WHEN Attestation_Hook が偽装応答を生成する, THE Attestation_Hook SHALL 応答に含まれる証明書チェーンを使用中 keybox の `CertificateChain` から構築し、`AttestationApplicationId` 拡張領域を呼び出し元プロセスのパッケージ署名から導出する。
6. THE Attestation_Hook SHALL TEESimulator のフックロジック (keybox 注入、証明書チェーン構築、attestation extension 生成) を保持し、上流の更新を追従可能な構造とする。

### Requirement 8: 遅延プロファイラによる自己診断

**User Story:** As an 利用者, I want 自分の構成が遅延ベースの検知に対してどの程度脆弱かを WebUI から測定したい, so that 検知される前に構成を見直せる.

#### Acceptance Criteria

1. WHEN 利用者が WebUI_Client から診断を実行する, THE Latency_Profiler SHALL CPU_Pinning を 1 コアに固定した上で attested 経路と non-attested 経路をそれぞれ `Sample_Count` 回計測する。
2. THE Latency_Profiler SHALL 計測前に Pre_Warming として 50 回のダミー呼び出しを実行し、JIT コンパイルおよびキャッシュ効果を安定化させる。
3. THE Latency_Profiler SHALL 各経路の計測結果について上位および下位 5% の外れ値を除外し、除外されたサンプル件数 `filteredBadSamples` を `除外件数/Sample_Count` の分数表記 (例: `20/500`) で出力する。
4. THE Latency_Profiler SHALL 平均 attested 時間 `T_a` (ミリ秒)、平均 non-attested 時間 `T_n` (ミリ秒)、差分 `diff = T_a − T_n`、比 `ratio = T_n ÷ T_a` を出力する。
5. WHEN `ratio` が Detection_Threshold を超過する, THE Detection_Test_Module SHALL 判定を `Positive` として WebUI_Client に赤色で表示する。
6. WHILE `ratio` が Detection_Threshold 以下である, THE Detection_Test_Module SHALL 判定を `Negative` として WebUI_Client に緑色で表示する。
7. THE Detection_Test_Module SHALL 1 回の診断結果を Module_Log に次の書式で記録する: `Register timer <cpuBinding> attested <T_a>ms non-attested <T_n>ms diff <diff>ms ratio <ratio>x filteredBadSamples=<除外件数>/<Sample_Count> threshold > <Detection_Threshold>x <判定>`。
8. THE Latency_Profiler SHALL `Sample_Count` の既定値を 500 とし、利用者が WebUI_Client から 100 から 5000 の範囲で変更できるよう構成する。
9. THE Latency_Profiler SHALL Detection_Threshold の既定値を 1.1 とし、利用者が WebUI_Client から 1.01 以上 2.0 以下の範囲で変更できるよう構成する。

### Requirement 9: 遅延補正による検知回避

**User Story:** As an 利用者, I want 偽装した attestation 経路の実行時間が hardware-backed 経路と統計的に区別しにくくなるよう自動調整したい, so that 遅延ベース検知で `Positive` 判定されにくくなる.

#### Acceptance Criteria

1. WHEN Attestation_Hook が偽装応答を返そうとする, THE Latency_Equalizer SHALL 当該応答の返却前に attested 経路の計測値 `T_a` を Hardware_Backed_Keybox の参照プロファイルに整合させるための待機時間を挿入する。
2. WHILE Latency_Equalizer が有効である, THE Latency_Equalizer SHALL 偽装 attested 経路の所要時間 `T_a_simulated` を `T_n ÷ Detection_Threshold` 以上となるよう調整し、結果として `ratio = T_n ÷ T_a_simulated` を Detection_Threshold 以下に保つ。
3. THE Latency_Equalizer SHALL Hardware_Backed_Keybox の参照プロファイル (平均 `T_a`、標準偏差、サンプル分布) を Configuration_Store に保存し、利用者が WebUI_Client から再計測できるよう構成する。
4. IF 参照プロファイルが未取得である, THEN THE Latency_Equalizer SHALL 待機時間を挿入せず、Module_Log に参照プロファイル未取得の警告を記録する。
5. WHERE 利用者が WebUI_Client で「Latency_Equalizer を無効化」を選択している, THE Attestation_Hook SHALL 待機時間を挿入せずに偽装応答を返却する。
6. THE Latency_Equalizer SHALL Jitter_Injection として挿入する待機時間に乱数ジッタ (参照プロファイルの標準偏差以下の範囲) を加算し、固定値による検知シグネチャを残さない。
7. THE Latency_Equalizer SHALL CPU_Pinning を用いて待機時間計算の精度を確保する。

### Requirement 10: タイミングサイドチャネル検知ベクターの文書化

**User Story:** As an 利用者および開発者, I want ソフトウェア TEE シミュレーションの検知可能性と限界を理解したい, so that 本モジュールの適用範囲と残存リスクを正しく評価できる.

#### Acceptance Criteria

1. THE TEE_Simulator_Plus SHALL モジュール同梱ドキュメント (`/data/adb/modules/tee-simulator-plus/docs/TIMING_SIDE_CHANNEL.md`) に Timing_Side_Channel 検知ベクターの技術的説明を含める。
2. THE ドキュメント SHALL 以下の項目を記載する: (a) 検知原理 (attested vs non-attested の実行時間比較)、(b) 検知例 (`attested 0.932ms non-attested 1.068ms ratio 1.146x threshold > 1.1x → Positive`)、(c) 根本的限界 (ソフトウェアシミュレーションはハードウェア TEE と完全に不可区別にはなれない)。
3. THE ドキュメント SHALL 緩和策として以下を記載する: (a) Jitter_Injection (乱数ノイズ挿入)、(b) CPU_Pinning (CPU 親和性固定による計測安定化)、(c) Pre_Warming (JIT/キャッシュ安定化)、(d) Latency_Equalizer (参照プロファイルベースの待機時間調整)。
4. THE ドキュメント SHALL 各緩和策の有効性と限界を記載し、「完全な不可区別性は達成不可能」であることを明記する。
5. THE WebUI_Client SHALL ステータスパネルに Timing_Side_Channel に関する簡潔な警告文 (「本モジュールはタイミング分析による検知を完全に防ぐことはできません」) を常時表示する。
6. WHEN Detection_Test_Module の判定が `Positive` である, THE WebUI_Client SHALL 検知リスクの説明と推奨アクション (Latency_Equalizer の有効化、Sample_Count の増加、Detection_Threshold の確認) を表示する。

### Requirement 11: 設定の永続化と移行

**User Story:** As an 利用者, I want 端末再起動およびモジュール更新後にも設定を保持したい, so that 構成のやり直しが不要になる.

#### Acceptance Criteria

1. THE Configuration_Store SHALL `/data/adb/modules/tee-simulator-plus/config/config.json` に JSON 形式で設定を保存する。
2. WHEN モジュールが起動する, THE TEE_Simulator_Plus SHALL Configuration_Store から `activeKeyboxId`、`targetList`、`detectionThreshold`、`sampleCount`、`latencyEqualizerEnabled`、`logLevel`、`referenceProfile` を読み込む。
3. WHEN モジュール更新により `config.json` のスキーマバージョンが変化する, THE TEE_Simulator_Plus SHALL 旧スキーマから新スキーマへの移行を行い、移行前ファイルを `config.json.bak` として保存する。
4. IF `config.json` のパースに失敗する, THEN THE TEE_Simulator_Plus SHALL 既定値で起動し、Module_Log にパース失敗の旨を記録する。
5. THE Configuration_Store SHALL `config.json` のファイルパーミッションを `0600` に設定する。

### Requirement 12: ログ記録と診断

**User Story:** As an 利用者, I want モジュールの動作ログを参照したい, so that 不具合や検知発生時の原因を特定できる.

#### Acceptance Criteria

1. THE Module_Log SHALL `/data/adb/modules/tee-simulator-plus/logs/module.log` にタイムスタンプとログレベル付きで追記する。
2. THE TEE_Simulator_Plus SHALL ログレベル `ERROR`、`WARN`、`INFO`、`DEBUG` を提供し、利用者が WebUI_Client から選択できるよう構成する。
3. WHEN Module_Log のサイズが 5 MB を超過する, THE TEE_Simulator_Plus SHALL 当該ファイルを `module.log.1` にローテートし、新規ログを `module.log` に書き出す。
4. WHILE ログレベルが `DEBUG` 未満に設定されている, THE Attestation_Hook SHALL 個別 attestation 呼び出しの詳細 (パッケージ名、所要時間) をログ出力しない。
5. IF Module_Log への書き込みが失敗する, THEN THE TEE_Simulator_Plus SHALL Android `logcat` (`tag=TEESimulatorPlus`) にフォールバックして同等の情報を出力する。
6. WHEN 利用者が WebUI_Client からログを閲覧する, THE WebUI_Client SHALL Module_Log の末尾 200 行を表示し、リアルタイム更新 (5 秒間隔ポーリング) を提供する。

### Requirement 13: 互換性

**User Story:** As an 利用者, I want 本モジュールが自分の端末環境で動作するか事前に確認したい, so that 非対応環境での導入を避けられる.

#### Acceptance Criteria

1. THE TEE_Simulator_Plus SHALL Android 10 (API 29) 以上の端末で動作する。
2. THE TEE_Simulator_Plus SHALL KernelSU 0.6.0 以上で動作する。
3. THE TEE_Simulator_Plus SHALL Magisk 24.0 以上 (Zygisk 有効) で動作する。
4. THE TEE_Simulator_Plus SHALL `arm64-v8a` および `armeabi-v7a` アーキテクチャをサポートする。
5. IF 端末の Android バージョンが API 29 未満である, THEN THE Module_Installer SHALL インストールを中断し、対応 Android バージョンを示すメッセージを出力する。
6. WHEN KernelSU 環境で動作する, THE TEE_Simulator_Plus SHALL WebUI 機能を完全に提供する。
7. WHEN Magisk 環境で動作する, THE TEE_Simulator_Plus SHALL Attestation_Hook 機能を提供し、WebUI は KernelSU Manager が利用可能な場合のみ提供する。
8. THE TEE_Simulator_Plus SHALL SELinux enforcing モードで動作し、必要な SELinux ポリシーを `sepolicy.rule` として同梱する。

## Correctness Properties

以下は本モジュールの正確性を検証するためのプロパティである。

### CP-1: Keybox Parser Round-Trip (往復変換)

**Property:** 有効な keybox XML に対して `parse(print(parse(xml)))` は `parse(xml)` と等価である。
**Pattern:** Round Trip
**Applicable to:** Requirement 3, Acceptance Criteria 6

### CP-2: Target_List 集合不変量

**Property:** Target_List への追加操作後、Target_List の要素数は操作前以上かつ操作前 +1 以下である (重複追加時は変化しない)。
**Pattern:** Invariant
**Applicable to:** Requirement 4, Acceptance Criteria 6

### CP-3: Latency_Equalizer 比率保証

**Property:** Latency_Equalizer が有効かつ参照プロファイルが存在する場合、`T_n ÷ T_a_simulated` は Detection_Threshold 以下である。
**Pattern:** Invariant
**Applicable to:** Requirement 9, Acceptance Criteria 2

### CP-4: Configuration_Store 冪等性

**Property:** 同一の設定値で Configuration_Store を 2 回書き込んだ場合、`config.json` の内容は 1 回書き込んだ場合と同一である。
**Pattern:** Idempotence
**Applicable to:** Requirement 11

### CP-5: Shell_Bridge 応答構造

**Property:** Shell_Bridge の全応答は `{"status": <number>, ...}` 構造を持ち、status=0 の場合は `data` フィールドを、status≠0 の場合は `message` フィールドを含む。
**Pattern:** Invariant
**Applicable to:** Requirement 6, Acceptance Criteria 3

### CP-6: Keybox_Store ファイル名一貫性

**Property:** Keybox_Store に保存された全ファイルについて、ファイル名 (拡張子除く) はファイル内容の SHA-256 ハッシュと一致する。
**Pattern:** Invariant
**Applicable to:** Requirement 2, Acceptance Criteria 1

### CP-7: Target_List インポート/エクスポート往復

**Property:** Target_List を `target.txt` にエクスポートし、空の Target_List にインポートした結果は元の Target_List と等価である。
**Pattern:** Round Trip
**Applicable to:** Requirement 4, Acceptance Criteria 5
