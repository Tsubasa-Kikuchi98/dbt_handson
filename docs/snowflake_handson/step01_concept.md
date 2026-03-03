# Step 1: コンセプトの理解

## 目的

dbt Projects on Snowflake の仕組みと、従来の dbt Core ワークフローとの違いを理解する。

---

## 1-1. 従来方式 vs 新方式

### 従来方式（dbt Core）

```
ローカル PC / CI環境
  ↓ dbt run
Snowflake にテーブル/ビュー作成
```

- dbt の実行環境は Snowflake の **外部**
- `profiles.yml` で接続情報を管理
- スケジューリングは Airflow / cron / CI ツール等で別途用意

### 新方式（dbt Projects on Snowflake）

```
dbt プロジェクト → Snowflake オブジェクトとしてデプロイ
                    → Snowflake 内で EXECUTE
                    → Snowflake Task でスケジューリング
```

- dbt プロジェクト自体が Snowflake の **ファーストクラスオブジェクト**
- `CREATE DBT PROJECT` / `EXECUTE DBT PROJECT` という SQL 文で操作
- スケジューリングは Snowflake Task でネイティブに実行

---

## 1-2. 7ステップワークフロー

| # | ステップ | やること |
|---|---|---|
| 1 | プロジェクト準備 | `dbt_project.yml` + `profiles.yml` + モデルを揃える |
| 2 | 依存パッケージ | `dbt deps` でパッケージインストール |
| 3 | デプロイ | `CREATE DBT PROJECT` で Snowflake オブジェクトとして登録 |
| 4 | 実行 | `EXECUTE DBT PROJECT` で Snowflake 内で dbt を実行 |
| 5 | スケジューリング | Snowflake Task で定期実行 |
| 6 | CI/CD | GitHub Actions で自動デプロイ |
| 7 | 監視 | Snowsight / システム関数でモニタリング |

---

## 1-3. 主要コンポーネント

| コンポーネント | 説明 |
|---|---|
| **dbt Project Object** | スキーマレベルの Snowflake オブジェクト。dbt ソースファイルを格納しバージョン管理される |
| **Workspace** | Snowsight 上の Web IDE。Git リポジトリと接続して dbt を開発・テスト・実行できる |
| **Snowflake Task** | dbt プロジェクトの定期実行スケジューラー |
| **Snowflake CLI (`snow`)** | コマンドラインからのデプロイ・実行ツール。CI/CD に最適 |

---

## 1-4. 制限事項（事前把握）

| 制限 | 内容 |
|---|---|
| dbt バージョン | **dbt-core 1.9.4 / dbt-snowflake 1.9.2**（ローカルの 1.11 ではない） |
| `env_var()` | **非対応**。`--vars` フラグで代替する |
| ファイル数上限 | プロジェクト内 **20,000 ファイル**まで |
| `dbt docs serve` | **非対応**（`docs generate` は可能） |
| リアルタイム出力 | コマンド完了後にのみ出力を確認可能 |
| `--state` フラグ | **非対応**（Slim CI は工夫が必要） |

---

## 1-5. バージョニングの仕組み

- デプロイごとにバージョンが自動作成される（`VERSION$1`, `VERSION$2`, ...）
- `CREATE OR REPLACE` を使うとバージョン番号はリセットされる
- 特殊参照: `LAST`（最新）, `FIRST`（最古）
- 例: `EXECUTE DBT PROJECT my_project VERSION = LAST ARGS = 'run';`

---

## 確認チェックリスト

- [ ] 従来方式と新方式の違いを理解した
- [ ] 7ステップワークフローの全体像を把握した
- [ ] 制限事項（特に dbt バージョンが 1.9 系である点）を認識した
