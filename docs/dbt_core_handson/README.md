# dbt Core ハンズオン — 手順書

## 概要

dbt Core を初歩から実践的に学ぶハンズオンの詳細手順書。
アダプターは Snowflake を使用し、最新バージョン (v1.11) の新機能までカバーする。

## 環境

| 項目 | 値 |
|---|---|
| Python | 3.12.2 |
| dbt-core | 1.11.5 |
| dbt-snowflake | 1.11.2 |
| Snowflake アカウント | `MYLMWWX-IFTC_DATADRESSER_REBUILD` |
| ウェアハウス | `ADMIN_WH` |
| データベース | `DATALAKE_DB` |

## ステップ一覧

| Step | タイトル | ファイル | 内容 |
|---|---|---|---|
| 1 | [プロジェクトの初期化](step01_project_init.md) | `step01_project_init.md` | dbt init、dbt_project.yml、profiles.yml、dbt debug |
| 2 | [最初のモデルを作る](step02_first_model.md) | `step02_first_model.md` | SQL モデル、dbt run、マテリアライゼーション、config、ref() |
| 3 | [ソースの定義](step03_sources.md) | `step03_sources.md` | source()、ソース YAML、Source Freshness |
| 4 | [モデルの階層設計](step04_layer_design.md) | `step04_layer_design.md` | staging / intermediate / mart、3層構造、schema.yml |
| 5 | [テスト](step05_testing.md) | `step05_testing.md` | ジェネリック・シングラー・ユニットテスト |
| 6 | [Seeds と Snapshots](step06_seeds_snapshots.md) | `step06_seeds_snapshots.md` | CSV ロード、SCD Type 2、check/timestamp 戦略 |
| 7 | [インクリメンタルモデル](step07_incremental.md) | `step07_incremental.md` | is_incremental()、merge/append、microbatch |
| 8 | [Jinja とマクロ](step08_jinja_macros.md) | `step08_jinja_macros.md` | Jinja 構文、マクロ定義、組み込みコンテキスト、Hooks |
| 9 | [UDF (v1.11)](step09_udf.md) | `step09_udf.md` | functions/ ディレクトリ、SQL/Python UDF、function() マクロ |
| 10 | [パッケージ管理](step10_packages.md) | `step10_packages.md` | packages.yml、dbt deps、dbt-utils、dbt-expectations |
| 11 | [ドキュメントと運用](step11_docs_operations.md) | `step11_docs_operations.md` | docs、Analyses、Exposures、dbt build、ノード選択構文 |

## 進め方

1. Step 1 から順番に進める
2. 各ステップ末尾の **確認チェックリスト** を完了してから次へ進む
3. 各ステップで実際にコマンドを実行して動作を確認する
4. 疑問点はその都度解消する

## プロジェクト構成（完成形）

```
dbt_handson_project/
├── dbt_project.yml
├── packages.yml
├── package-lock.yml
├── models/
│   ├── staging/
│   │   └── jaffle_shop/
│   │       ├── _jaffle_shop__sources.yml
│   │       ├── _jaffle_shop__models.yml
│   │       ├── stg_jaffle_shop__customers.sql
│   │       ├── stg_jaffle_shop__orders.sql
│   │       └── stg_jaffle_shop__payments.sql
│   ├── intermediate/
│   │   ├── _int__models.yml
│   │   └── int_orders_joined.sql
│   └── marts/
│       ├── _mart__models.yml
│       ├── fct_orders.sql
│       ├── fct_orders_daily.sql
│       ├── dim_customers.sql
│       └── exposures.yml
├── seeds/
│   └── payment_method_mapping.csv
├── tests/
│   └── assert_fct_orders_amount_is_positive.sql
├── snapshots/
│   └── snp_jaffle_shop__customers.sql
├── macros/
│   └── update_customer.sql
├── analyses/
│   └── jinja_practice.sql
└── dbt_packages/
    ├── dbt_utils/
    ├── dbt_expectations/
    └── dbt_date/
```

## 主要コマンド一覧

| コマンド | 説明 |
|---|---|
| `dbt init` | プロジェクト初期化 |
| `dbt debug` | 接続テスト |
| `dbt run` | モデル実行 |
| `dbt test` | テスト実行 |
| `dbt build` | 一括実行（seed + model + snapshot + test） |
| `dbt seed` | CSV をテーブルにロード |
| `dbt snapshot` | スナップショット実行 |
| `dbt compile` | SQL コンパイル（実行なし） |
| `dbt deps` | パッケージインストール |
| `dbt clean` | target/ と dbt_packages/ を削除 |
| `dbt docs generate` | ドキュメント生成 |
| `dbt docs serve` | ドキュメントサイト起動 |
| `dbt source freshness` | ソース鮮度チェック |
| `dbt run-operation` | マクロを直接実行 |
| `dbt ls` | ノード選択結果のプレビュー |
| `dbt retry` | 失敗バッチの再実行 |
