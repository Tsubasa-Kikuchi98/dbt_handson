# dbt Projects on Snowflake ハンズオン — 手順書

## 概要

Snowflake のネイティブ dbt 統合を学ぶハンズオンの詳細手順書。
dbt プロジェクトを Snowflake 上のオブジェクトとしてデプロイ・実行・スケジューリング・監視する方法をカバーする。

## 前提

- dbt Core ハンズオン（Step 1〜11）を完了していること
- Snowflake アカウントに ACCOUNTADMIN 権限があること
- GitHub アカウントを持っていること

## ステップ一覧

| Step | タイトル | ファイル | 内容 |
|---|---|---|---|
| 1 | [コンセプトの理解](step01_concept.md) | `step01_concept.md` | 従来方式 vs 新方式、7ステップワークフロー、制限事項 |
| 2 | [環境セットアップ](step02_setup.md) | `step02_setup.md` | DB/スキーマ作成、GitHub接続、API Integration、External Access |
| 3 | [Workspace の作成と操作](step03_workspace.md) | `step03_workspace.md` | Git リポジトリ接続、Workspace 作成、dbt 実行 |
| 4 | [スキーマ生成のカスタマイズ](step04_schema_customization.md) | `step04_schema_customization.md` | generate_schema_name マクロ、dev/prod スキーマ解決 |
| 5 | [デプロイ](step05_deploy.md) | `step05_deploy.md` | Workspace/SQL/CLI の3つのデプロイ方法 |
| 6 | [実行とスケジューリング](step06_execute_schedule.md) | `step06_execute_schedule.md` | EXECUTE DBT PROJECT、Snowflake Task、Cron スケジュール |
| 7 | [アクセス制御](step07_access_control.md) | `step07_access_control.md` | ロール設計、権限付与、テスト |
| 8 | [CI/CD パイプライン](step08_cicd.md) | `step08_cicd.md` | OIDC認証、GitHub Actions、CI/CD ワークフロー |
| 9 | [監視とオブザーバビリティ](step09_monitoring.md) | `step09_monitoring.md` | Snowsight 監視、ログ取得、アーティファクト管理 |
| 10 | [依存関係の管理](step10_dependencies.md) | `step10_dependencies.md` | dbt deps、パッケージバージョン管理、ネットワーク設定 |

## 進め方

1. Step 1 から順番に進める
2. 各ステップ末尾の **確認チェックリスト** を完了してから次へ進む
3. 疑問点はその都度解消する

## トラブルシューティング（共通）

| エラー | 原因 | 対処法 |
|---|---|---|
| `dbt deps` 失敗 | External Access Integration 未設定 | `dbt_ext_access` を作成・紐づけ |
| スキーマエラー | ターゲットスキーマが存在しない | `CREATE SCHEMA` で事前作成 |
| ソーステーブルが見つからない | クロスデータベースアクセス権限不足 | ソース DB への `USAGE` + `SELECT` 付与 |
| GitHub Actions 認証エラー | OIDC の SUBJECT 不一致 | `repo:<org>/<repo>:environment:<env>` 形式を確認 |
| パッケージ互換性エラー | dbt バージョン不一致（1.11 vs 1.9） | パッケージバージョンを 1.9 互換に固定 |
| Task が実行されない | `SUSPENDED` 状態 | `ALTER TASK ... RESUME;` を実行 |
| `CREATE DBT PROJECT` 権限エラー | ロールに権限不足 | `GRANT CREATE DBT PROJECT ON SCHEMA ...` |
