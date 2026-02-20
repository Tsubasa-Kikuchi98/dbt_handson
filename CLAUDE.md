# dbt Core ハンズオン

## 概要
dbt core を初歩から実践的に学ぶハンズオン。アダプターは Snowflake を使用。
最新バージョン (v1.11) の新機能までカバーする。

## 環境
- Python 3.12.2
- dbt-core 1.11.5
- dbt-snowflake 1.11.2

## 参考ドキュメント
- 公式ドキュメント: https://docs.getdbt.com/
- v1.11 アップグレードガイド: https://docs.getdbt.com/docs/dbt-versions/core-upgrade/upgrading-to-v1.11
- GitHub: https://github.com/dbt-labs/dbt-core

---

## カリキュラム

### Step 1: プロジェクトの初期化

#### 1-1. dbt init によるプロジェクト作成
- `dbt init` コマンドでプロジェクトの雛形を生成
- プロジェクト名の命名（snake_case）

#### 1-2. dbt_project.yml の理解
- `name`: プロジェクト名
- `version`: プロジェクトバージョン
- `require-dbt-version`: dbt バージョン制約
- `profile`: 接続プロファイル名
- `model-paths` / `seed-paths` / `test-paths` / `macro-paths` / `snapshot-paths` / `analysis-paths` / `docs-paths`: 各リソースのディレクトリ指定
- `vars`: プロジェクト変数
- モデルごとのデフォルト設定（マテリアライゼーション、スキーマなど）

#### 1-3. ディレクトリ構成
| ディレクトリ | 役割 |
|---|---|
| models/ | SQL/Python モデル、スキーマ定義 |
| seeds/ | CSV データ |
| snapshots/ | スナップショット定義 |
| tests/ | singular テスト |
| macros/ | マクロ定義 |
| analyses/ | 分析用SQL（コンパイルのみ、実行されない） |
| functions/ | UDF 定義 (v1.11+) |
| target/ | コンパイル・実行結果の出力先 |
| dbt_packages/ | インストールしたパッケージ |

#### 1-4. profiles.yml と接続設定
- `~/.dbt/profiles.yml` の構造
- Snowflake 固有の設定（account, user, password, role, warehouse, database, schema）
- 認証方式（password / keypair / SSO）
- ターゲット（dev / prod）の使い分け

#### 1-5. 接続確認
- `dbt debug` で接続テスト
- 各項目（dbt version, profiles.yml, dbt_project.yml, connection）の確認

---

### Step 2: 最初のモデルを作る

#### 2-1. SQL モデルの基本
- models/ ディレクトリに `.sql` ファイルを作成
- モデル名 = ファイル名（大文字小文字を区別）
- 1ファイル = 1つの SELECT 文

#### 2-2. dbt run によるモデル実行
- `dbt run` でモデルをビルド
- SELECT 文が `CREATE VIEW AS` または `CREATE TABLE AS` にラップされる
- アトミックな置換（ダウンタイムなし）
- スキーマの自動作成

#### 2-3. マテリアライゼーション
| 種類 | 説明 | 用途 |
|---|---|---|
| **view** (デフォルト) | ビューとして作成 | シンプルな変換、常に最新データが必要な場合 |
| **table** | テーブルとして作成 | BIツールからの高速クエリ、重い変換 |
| **ephemeral** | CTE として展開（DBに作成されない） | 軽量な中間処理、1-2つの下流モデルのみ |
| **incremental** | 差分のみ追加・更新 | 大規模データ、イベントデータ（Step 7で詳述） |
| **materialized_view** | マテリアライズドビュー | 自動リフレッシュが必要な場合 |

- Snowflake では materialized_view の代わりに **Dynamic Table** を使用

#### 2-4. config ブロック
- モデル内での設定: `{{ config(materialized="table") }}`
- dbt_project.yml でのディレクトリ単位設定
- 設定の優先順位: ファイル内 > schema.yml > dbt_project.yml

#### 2-5. ref() 関数
- `{{ ref('model_name') }}` でモデル間の依存を宣言
- DAG（有向非巡回グラフ）の自動構築
- 環境ごとのスキーマ解決（dev / prod）
- 2引数構文: `{{ ref('package_name', 'model_name') }}`

#### 2-6. モデルの設定オプション
- `schema`: カスタムスキーマ
- `alias`: テーブル/ビュー名のオーバーライド
- `database`: 出力先データベース
- `tags`: タグ付け（選択実行に利用）
- `pre-hook` / `post-hook`: ビルド前後のSQL実行
- `grants`: オブジェクトレベルの権限設定
- `persist_docs`: ドキュメントの永続化
- `meta`: カスタムメタデータ

---

### Step 3: ソースの定義

#### 3-1. ソースとは
- ELツールによってウェアハウスにロード済みのデータを定義
- `sources:` キーで YAML ファイルに記述

#### 3-2. source() 関数
- `{{ source('source_name', 'table_name') }}` でソーステーブルを参照
- フルパス（database.schema.table）への自動解決
- DAG 上でのリネージ可視化

#### 3-3. ソースの設定項目
- `name`: ソース識別子
- `database`: データベース名
- `schema`: スキーマ名（省略時は name がスキーマ名になる）
- `tables`: テーブルのリスト
- `identifier`: 実際のテーブル名がソース定義名と異なる場合のマッピング
- `quoting`: 識別子のクオート設定（Snowflake の大文字小文字区別に重要）
- `description`: ドキュメント記述
- `columns`: カラムレベルのドキュメント・テスト

#### 3-4. Source Freshness
- `loaded_at_field`: データロード時刻のカラム指定
- `freshness`: 鮮度チェックの閾値
  - `warn_after: {count: 12, period: hour}`
  - `error_after: {count: 24, period: hour}`
- `filter`: フルスキャンを防ぐフィルタ条件
- `dbt source freshness` コマンドで実行
- 結果は `target/sources.json` に出力

#### 3-5. ソースの選択実行
- `dbt test --select source:source_name`
- `dbt run --select source:source_name+`（下流モデルの実行）
- `dbt build --select source_status:fresher+`

---

### Step 4: モデルの階層設計（staging / intermediate / mart）

#### 4-1. 3層構造の考え方
| 層 | 命名規則 | マテリアライゼーション | 役割 |
|---|---|---|---|
| **staging** | `stg_<source>__<table>` | view | ソースデータの軽い変換（リネーム、型変換） |
| **intermediate** | `int_<entity>_<verb>` | ephemeral / view | ビジネスロジックの中間処理（結合、集約） |
| **mart** | `fct_` / `dim_` | table / incremental | 最終的な分析用テーブル（ファクト / ディメンション） |

#### 4-2. ディレクトリ構成例
```
models/
├── staging/
│   └── jaffle_shop/
│       ├── _jaffle_shop__sources.yml
│       ├── _jaffle_shop__models.yml
│       ├── stg_jaffle_shop__customers.sql
│       └── stg_jaffle_shop__orders.sql
├── intermediate/
│   ├── _int__models.yml
│   └── int_orders_pivoted.sql
└── marts/
    ├── _mart__models.yml
    ├── fct_orders.sql
    └── dim_customers.sql
```

#### 4-3. schema.yml（モデルプロパティ）
- `description`: モデル・カラムの説明
- `columns`: カラム定義、テスト、説明
- `data_tests`: テスト定義
- `tags`: タグ付け
- `meta`: カスタムメタデータ

#### 4-4. グループとアクセス制御
- `groups:` でチーム単位のグループ定義
- アクセス修飾子:
  - `public`: どこからでも参照可能
  - `protected` (デフォルト): 同プロジェクト内から参照可能
  - `private`: 同グループ内のみ参照可能

#### 4-5. モデルコントラクト
- `contract: {enforced: true}` でスキーマを強制
- カラム名・データ型の一致を検証
- コントラクト違反はコンパイルエラー
- 制約（constraints）: `not_null`, `unique`, `primary_key`, `foreign_key`, `check`
- 対応マテリアライゼーション: table, view, incremental

---

### Step 5: テスト

#### 5-1. データテスト（Generic Tests）
- 組み込みジェネリックテスト:
  - `unique`: 重複なし
  - `not_null`: NULL なし
  - `accepted_values`: 許容値リスト
  - `relationships`: 参照整合性
- schema.yml の `data_tests:` キーで定義
- パッケージ提供テスト（dbt-utils, dbt-expectations）

#### 5-2. Singular テスト
- `tests/` ディレクトリに `.sql` ファイルを作成
- 失敗レコードを返す SELECT 文
- 0行 = テスト成功
- パラメータ化なし、1回限りのアサーション

#### 5-3. テストの設定
- `severity`: `warn` または `error`
- `warn_if` / `error_if`: 失敗行数の閾値（例: `">10"`）
- `where`: テスト対象のフィルタ条件
- `limit`: 返却行数の上限
- `store_failures`: 失敗レコードをテーブルに保存（`dbt_test__audit` スキーマ）
- `store_failures_as`: 保存形式（table / view）
- `tags`: テストのタグ付け

#### 5-4. テスト実行
- `dbt test`: 全テスト実行
- `dbt test --select model_name`: モデル指定
- `dbt test --select test_type:data`: データテストのみ
- `dbt test --select test_type:unit`: ユニットテストのみ
- `dbt test --select source:source_name`: ソースのテスト

#### 5-5. ユニットテスト (v1.8+)
- SQLモデルのロジックを静的データで検証（ウェアハウスのデータに依存しない）
- schema.yml に `unit_tests:` で定義

```yaml
unit_tests:
  - name: test_order_total
    description: "注文合計の計算ロジックを検証"
    model: fct_orders
    given:
      - input: ref('stg_orders')
        rows:
          - {order_id: 1, quantity: 2, unit_price: 100}
    expect:
      rows:
        - {order_id: 1, total: 200}
```

- 入力データ形式: dict / CSV / SQL
- `overrides:` でマクロ・変数・環境変数をオーバーライド
- `fixture` ファイル（tests/fixtures/）で外部データ定義
- 制限事項: SQL モデルのみ、同プロジェクトのモデルのみ、materialized_view 非対応
- `dbt build` 時: ユニットテスト → モデル実行 → データテスト の順で実行

---

### Step 6: seeds と snapshots

#### 6-1. Seeds
- `seeds/` に CSV ファイルを配置
- `dbt seed` でウェアハウスにテーブルとしてロード
- `ref()` で他モデルから参照可能
- 適切な用途: マスタデータ、マッピングテーブル、除外リスト
- 不適切な用途: 大規模データ、本番データ、機密情報
- 設定:
  - `column_types`: カラム型の明示指定（例: 先頭ゼロ保持の `varchar`）
  - `quote_columns`: カラム名のクオート
  - `+schema`: 出力先スキーマ
- `dbt seed --full-refresh`: カラム構成が変わった場合に必要（drop cascade → 再作成）
- `dbt seed --select seed_name`: 個別実行

#### 6-2. Snapshots（SCD Type 2）
- ソーステーブルの変更履歴を追跡
- スナップショットメタカラム:
  - `dbt_valid_from`: この版の有効開始日時
  - `dbt_valid_to`: この版の有効終了日時（現行レコードは NULL）
  - `dbt_scd_id`: スナップショット行の一意ID
  - `dbt_updated_at`: ソースの更新日時
  - `dbt_is_deleted`: 削除フラグ（`hard_deletes='new_record'` 時）

#### 6-3. スナップショット戦略
| 戦略 | 設定 | 説明 |
|---|---|---|
| **timestamp** (推奨) | `updated_at` | 更新日時カラムで変更を検知。スキーマ変更に強い |
| **check** | `check_cols` | 指定カラムの値比較で変更を検知。`updated_at` がない場合に使用 |

#### 6-4. スナップショットの設定
- `unique_key`: 行の一意キー（必須）
- `strategy`: `timestamp` または `check`
- `updated_at`: タイムスタンプカラム（timestamp 戦略時）
- `check_cols`: 監視カラムリスト or `'all'`（check 戦略時）
- `dbt_valid_to_current`: 現行レコードの `dbt_valid_to` 値（例: `'9999-12-31'`）(v1.9+)
- `hard_deletes`: 削除の追跡方法（`'new_record'`）
- `snapshot_meta_column_names`: メタカラム名のカスタマイズ

#### 6-5. スキーマ進化
- 新カラムの追加: 自動対応
- varchar サイズの拡張: 自動対応
- カラム削除・型変更: 非対応（履歴データ保護のため）

---

### Step 7: インクリメンタルモデル

#### 7-1. 基本概念
- 前回実行以降の新規・変更データのみを処理
- 大規模テーブル（数百万〜数十億行）やコストの高い変換に有効
- `{{ config(materialized='incremental') }}` で設定

#### 7-2. is_incremental() マクロ
- 増分実行時のみ TRUE を返す条件:
  - マテリアライゼーションが incremental
  - 対象テーブルがすでに存在
  - `--full-refresh` フラグなし
  - dbt が非初回実行

```sql
{{ config(materialized='incremental') }}
select * from {{ source('app', 'events') }}
{% if is_incremental() %}
  where event_time > (select max(event_time) from {{ this }})
{% endif %}
```

#### 7-3. incremental_strategy
| 戦略 | 説明 | Snowflake対応 |
|---|---|---|
| **append** | 新規レコードを追加のみ | ○ |
| **merge** | MERGE文で挿入・更新 | ○ |
| **delete+insert** | 削除後に挿入 | ○ |
| **microbatch** | 時間ベースのバッチ処理 (v1.9+) | ○（delete+insert） |

- `unique_key`: マージ時のキーカラム
- `on_schema_change`: スキーマ変更時の挙動（`ignore`, `fail`, `append_new_columns`, `sync_all_columns`）
- `incremental_predicates`: マージ条件の追加述語
- `full_refresh`: `--full-refresh` フラグでフルリビルド

#### 7-4. microbatch 戦略 (v1.9+)
- 大規模時系列データを時間ベースのバッチに分割して処理
- 各バッチが独立・冪等（失敗バッチのみリトライ可能）
- `is_incremental()` ブロック不要

設定パラメータ:
| パラメータ | 必須 | 説明 |
|---|---|---|
| `event_time` | ○ | 時間カラム名（UTCと仮定） |
| `batch_size` | ○ | バッチ粒度: `hour` / `day` / `month` / `year` |
| `begin` | ○ | 処理開始日（初回・フルリフレッシュ時の起点） |
| `lookback` | × | 遅延レコード対応のバッチ数（デフォルト: 1） |
| `concurrent_batches` | × | 並列バッチ実行（true / false） |

- バックフィル: `dbt run --event-time-start "2024-01-01" --event-time-end "2024-02-01"`
- リトライ: `dbt retry` で失敗バッチのみ再処理
- 推奨: `full_refresh: false` で `--full-refresh` を無視し、バックフィルで代替

---

### Step 8: Jinja とマクロ

#### 8-1. Jinja テンプレート構文
| 構文 | 用途 | 例 |
|---|---|---|
| `{{ ... }}` | 式の出力 | `{{ ref('model') }}` |
| `{% ... %}` | 制御文（出力しない） | `{% if ... %}` |
| `{# ... #}` | コメント | `{# memo #}` |

- `for` ループ: `{% for item in list %}...{% endfor %}`
- `if` 文: `{% if condition %}...{% elif %}...{% else %}...{% endif %}`
- 変数代入: `{% set var_name = value %}`
- ホワイトスペース制御: `{{- ... -}}` で前後の空白を除去

#### 8-2. マクロの定義と使用
```sql
{% macro cents_to_dollars(column_name, scale=2) %}
    ({{ column_name }} / 100)::numeric(16, {{ scale }})
{% endmacro %}
```
- macros/ に `.sql` ファイルとして配置
- デフォルト引数のサポート
- パッケージのマクロ: `{{ dbt_utils.star(from=ref('model')) }}`

#### 8-3. dbt 組み込みコンテキスト
| 関数/変数 | 説明 |
|---|---|
| `ref()` | モデル参照 |
| `source()` | ソース参照 |
| `config()` | モデル設定 |
| `var()` | プロジェクト変数の参照 |
| `env_var()` | 環境変数の参照 |
| `target` | 現在のターゲット情報（name, schema, database など） |
| `this` | 現在のモデルのリレーション |
| `log()` | デバッグ出力 |
| `return()` | マクロから値を返す |
| `run_query()` | SQLを実行して結果を取得 |
| `adapter` | アダプター固有の機能呼び出し |

#### 8-4. Operations
- `dbt run-operation macro_name --args '{key: value}'`
- マクロを直接コマンドラインから実行
- run_query や statement ブロックで明示的にSQLを実行する必要あり

#### 8-5. Hooks
| フック | タイミング |
|---|---|
| `pre-hook` | モデル/seed/snapshot のビルド前 |
| `post-hook` | モデル/seed/snapshot のビルド後 |
| `on-run-start` | dbt コマンド開始時 |
| `on-run-end` | dbt コマンド終了時 |

- 用途: 権限管理、ウェアハウス操作、監査ログ、外部テーブル管理

---

### Step 9: ユーザー定義関数（UDF） (v1.11 新機能)

#### 9-1. UDF の基本
- dbt が UDF をファーストクラスリソースとしてサポート
- `functions/` ディレクトリに定義ファイルを配置
- YAML で設定を記述

#### 9-2. UDF の参照
- `{{ function('function_name') }}` マクロでモデルから参照
- `dbt build` の実行時に UDF がウェアハウスに作成される

#### 9-3. UDF の機能
- SQL UDF / Python UDF のサポート
- デフォルト引数
- 豊富な設定オプション
- プロジェクト横断でのポータビリティ

---

### Step 10: パッケージ管理

#### 10-1. packages.yml
- `packages.yml` または `dependencies.yml` に依存パッケージを定義
- `dbt deps` でインストール（`dbt_packages/` に展開）
- `dbt clean` でパッケージ削除

#### 10-2. パッケージの種類
| 種類 | 説明 |
|---|---|
| **Hub パッケージ** | dbt Hub から取得（推奨）。セマンティックバージョニング |
| **Git パッケージ** | Git リポジトリから取得。revision でバージョン固定 |
| **ローカルパッケージ** | ローカルパスから参照。モノレポ向け |
| **プライベートパッケージ** | トークンまたはネイティブ連携で認証 |

#### 10-3. 代表的なパッケージ
- `dbt-utils`: ユーティリティマクロ集（surrogate_key, pivot, star など）
- `dbt-expectations`: Great Expectations 風のテスト
- `dbt-date`: 日付ユーティリティ
- `codegen`: コード自動生成（staging モデル、YAML スキーマ）

---

### Step 11: ドキュメントと運用

#### 11-1. ドキュメント記述
- YAML の `description:` キーでモデル・カラムを説明
- Docs ブロック: `{% docs block_name %}...{% enddocs %}` で Markdown ドキュメント
- `{{ doc("block_name") }}` で YAML から参照
- `__overview__` ブロックでトップページをカスタマイズ

#### 11-2. ドキュメント生成・閲覧
- `dbt docs generate`: manifest.json + catalog.json を生成
- `dbt docs serve`: ローカルでドキュメントサイトを起動
- DAG の可視化、カラム情報、テスト情報の確認

#### 11-3. Analyses
- `analyses/` ディレクトリに `.sql` ファイルを配置
- `dbt compile` でコンパイルされるが実行はされない
- `ref()` を使った環境非依存のアドホッククエリに利用
- コンパイル結果: `target/compiled/{project}/analyses/`

#### 11-4. Exposures
- ダッシュボードやアプリなど、dbt の下流の利用先を定義
- YAML の `exposures:` キーで記述
- プロパティ: `type`（dashboard, notebook, analysis, ml, application）、`owner`、`maturity`、`depends_on`、`url`
- `dbt run -s +exposure:exposure_name` で関連リソースを選択実行

#### 11-5. dbt build
- モデル実行 + テスト + snapshot + seed + UDF をDAG順に一括実行
- テスト失敗時に下流モデルを自動スキップ
- ユニットテスト → モデル実行 → データテスト の順序
- `--empty` フラグ: スキーマのみの空実行（データ読み込みなし）

#### 11-6. ノード選択構文
| 構文 | 説明 | 例 |
|---|---|---|
| モデル名 | 単一モデル | `dbt run -s my_model` |
| `+` | 上流/下流の展開 | `-s +my_model+` |
| `@` | 上流+下流すべて | `-s @my_model` |
| スペース区切り | 和集合（OR） | `-s model_a model_b` |
| カンマ区切り | 積集合（AND） | `-s path:marts,tag:nightly` |
| `--exclude` | 除外 | `--exclude my_model` |
| `tag:` | タグで選択 | `-s tag:nightly` |
| `path:` | パスで選択 | `-s path:models/marts` |
| `config:` | 設定値で選択 | `-s config.materialized:table` |
| `test_type:` | テスト種別 | `-s test_type:unit` |
| `source:` | ソース | `-s source:jaffle_shop` |
| `state:` | 変更状態 | `-s state:modified` |

- `dbt ls --select "..."` で選択結果をプレビュー（実行なし）

#### 11-7. config.meta_get() / config.meta_require() (v1.11)
- `meta` に格納したカスタム設定値をマクロやフック内から取得
- `config.meta_get('key', default)`: 任意キー取得（デフォルト値あり）
- `config.meta_require('key')`: 必須キー取得（未設定時エラー）

---

## 進め方
- ステップバイステップで一つずつ進める
- 各ステップで実際にコマンドを実行して動作を確認する
- 疑問点はその都度解消しながら進める

## Claudeの動作ルール
- ファイルの作成・編集は Claude が直接行わない
- 実行すべきコマンドや手順を案内するだけにする（ユーザー自身が実行する）