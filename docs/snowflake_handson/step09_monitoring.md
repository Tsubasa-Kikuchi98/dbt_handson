# Step 9: 監視とオブザーバビリティ

## 目的

dbt プロジェクトの実行状況を Snowsight と SQL で監視する方法を習得する。

---

## 前提条件

- Step 6 以降が完了していること（dbt Project が少なくとも 1 回実行済みであること）
- 監視設定が有効化されていること（Step 2-7 で設定済み）

---

## 9-1. Snowsight での監視（GUI）

### 操作手順

1. Snowsight にログイン
2. 左メニュー → **Transformation** → **dbt Projects**
3. `dbt_handson` プロジェクトをクリック

### 確認できる情報

| 項目 | 説明 |
|---|---|
| 実行履歴 | 過去の実行一覧（成功/失敗、所要時間） |
| モデルステータス | 各モデルの実行結果 |
| クエリ詳細 | 実行された SQL の詳細（クエリID付き） |
| バージョン情報 | デプロイされたバージョン一覧 |

> **必要な権限**: `MONITOR` 権限。Step 7 で ANALYST ロールにも付与済み。

---

## 9-2. 実行履歴の取得（SQL）

**実行場所**: Snowflake ワークシート

```sql
-- ============================================================
-- Step 9-2: 実行履歴の取得
-- ============================================================

-- dbt Project の実行履歴を取得
SELECT
    query_id,
    object_name,
    query_text,
    status,
    query_start_time,
    query_end_time,
    DATEDIFF('second', query_start_time, query_end_time) AS duration_seconds
FROM TABLE(INFORMATION_SCHEMA.DBT_PROJECT_EXECUTION_HISTORY())
WHERE object_name = 'DBT_HANDSON'
ORDER BY query_end_time DESC
LIMIT 20;
```

### 結果の見方

| カラム | 説明 |
|---|---|
| `query_id` | 実行のクエリID（ログ取得やアーティファクト取得に使用） |
| `object_name` | dbt Project 名 |
| `query_text` | 実行された `EXECUTE DBT PROJECT` 文 |
| `status` | `SUCCESS` / `FAILED` |
| `query_start_time` | 実行開始日時 |
| `query_end_time` | 実行終了日時 |
| `duration_seconds` | 所要時間（秒） |

---

## 9-3. ログの取得

### 最新の実行ログを表示

```sql
-- ============================================================
-- Step 9-3: ログの取得
-- ============================================================

-- 最新の実行クエリIDを取得
SET latest_query_id = (
    SELECT query_id
    FROM TABLE(INFORMATION_SCHEMA.DBT_PROJECT_EXECUTION_HISTORY())
    WHERE object_name = 'DBT_HANDSON'
    ORDER BY query_end_time DESC
    LIMIT 1
);

-- dbt ログを表示
SELECT SYSTEM$GET_DBT_LOG($latest_query_id);
```

### ログの内容

ログには `dbt run` の標準出力と同等の内容が含まれる:

```
Running with dbt=1.9.4
Found X models, Y tests, Z snapshots, ...

Concurrency: 1 threads (target='prod')

1 of N OK created sql table model PROD.FCT_ORDERS .............. [SUCCESS 1 in 2.34s]
2 of N OK created sql view model PROD.STG_JAFFLE_SHOP__CUSTOMERS  [SUCCESS 1 in 1.12s]
...

Finished running N table models, M view models in 0 hours 0 minutes and X.XX seconds.

Completed successfully
Done. PASS=N WARN=0 ERROR=0 SKIP=0 TOTAL=N
```

### 特定のクエリIDを指定してログを取得

```sql
-- 特定のクエリIDでログを取得
SELECT SYSTEM$GET_DBT_LOG('01abcdef-0123-4567-89ab-cdef01234567');
```

---

## 9-4. アーティファクトの取得

### アーティファクトフォルダのパス

```sql
-- ============================================================
-- Step 9-4a: アーティファクトフォルダのパスを取得
-- ============================================================

SELECT SYSTEM$LOCATE_DBT_ARTIFACTS($latest_query_id);
```

**返されるパスの例:**
```
snow://dbt/DBT_PROJECT_DB.PROD.DBT_HANDSON/results/<query_id>/
```

### ZIP アーカイブの URL

```sql
-- ============================================================
-- Step 9-4b: ZIP アーカイブのURLを取得
-- ============================================================

SELECT SYSTEM$LOCATE_DBT_ARCHIVE($latest_query_id);
```

### アーティファクトに含まれるファイル

| ファイル | 説明 |
|---|---|
| `manifest.json` | DAG、モデルプロパティ、リネージ情報 |
| `run_results.json` | 各モデルの実行結果（成功/失敗、行数、所要時間） |
| `catalog.json` | テーブル/カラム情報（`dbt docs generate` 実行時のみ） |
| `sources.json` | ソース鮮度チェック結果（`dbt source freshness` 実行時のみ） |

---

## 9-5. アーティファクトをステージにコピー

長期保存や外部ツールとの連携のため、アーティファクトを Snowflake ステージにコピーできる。

```sql
-- ============================================================
-- Step 9-5: アーティファクトのステージへのコピー
-- ============================================================

-- 保存用ステージの作成（初回のみ）
CREATE OR REPLACE STAGE DBT_PROJECT_DB.PROD.dbt_artifacts_stage
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

-- アーティファクトをステージにコピー
-- 注意: <query_id> を実際のクエリIDに置き換えること
COPY FILES
  INTO @DBT_PROJECT_DB.PROD.dbt_artifacts_stage/results/
  FROM 'snow://dbt/DBT_PROJECT_DB.PROD.DBT_HANDSON/results/<query_id>/';

-- コピーされたファイルの確認
LIST @DBT_PROJECT_DB.PROD.dbt_artifacts_stage/results/;
```

### 活用例

```sql
-- ステージ上の run_results.json を読み取り
SELECT $1
FROM @DBT_PROJECT_DB.PROD.dbt_artifacts_stage/results/run_results.json
(FILE_FORMAT => (TYPE = 'JSON'));
```

---

## 9-6. 失敗時のデバッグフロー

dbt 実行が失敗した場合のデバッグ手順:

### ステップ 1: 失敗した実行を特定

```sql
-- 失敗した実行の一覧
SELECT query_id, status, query_text, query_start_time
FROM TABLE(INFORMATION_SCHEMA.DBT_PROJECT_EXECUTION_HISTORY())
WHERE object_name = 'DBT_HANDSON'
  AND status != 'SUCCESS'
ORDER BY query_end_time DESC
LIMIT 5;
```

### ステップ 2: ログで詳細を確認

```sql
-- 失敗したクエリIDを設定
SET failed_query_id = '<上で取得した query_id>';

-- ログを表示（エラーメッセージが含まれる）
SELECT SYSTEM$GET_DBT_LOG($failed_query_id);
```

### ステップ 3: アーティファクトで run_results.json を確認

```sql
-- アーティファクトの場所を取得
SELECT SYSTEM$LOCATE_DBT_ARTIFACTS($failed_query_id);
```

### ステップ 4: 修正してリデプロイ → 再実行

1. ローカルまたは Workspace でコードを修正
2. 再デプロイ（Step 5 の手順）
3. 再実行（Step 6 の手順）

### よくある失敗原因

| 原因 | ログに含まれるキーワード | 対処法 |
|---|---|---|
| SQL 構文エラー | `Compilation Error` | モデルの SQL を修正 |
| テーブル/ビューが見つからない | `Object does not exist` | ソースや上流モデルの存在を確認 |
| 権限不足 | `Insufficient privileges` | ロールに必要な権限を付与 |
| スキーマが存在しない | `Schema does not exist` | スキーマを事前作成 |
| パッケージ未インストール | `Compilation Error`, `dispatch` | `dbt deps` を実行 |
| dbt バージョン互換性 | `require-dbt-version` | `dbt_project.yml` の制約を確認 |

---

## 9-7. 定期的な監視クエリ（運用向け）

定期的に実行して運用状態を把握するクエリ:

```sql
-- ============================================================
-- Step 9-7: 運用監視クエリ
-- ============================================================

-- 直近24時間の実行サマリー
SELECT
    DATE_TRUNC('hour', query_start_time) AS execution_hour,
    COUNT(*) AS total_executions,
    SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) AS success_count,
    SUM(CASE WHEN status != 'SUCCESS' THEN 1 ELSE 0 END) AS failure_count,
    AVG(DATEDIFF('second', query_start_time, query_end_time)) AS avg_duration_sec
FROM TABLE(INFORMATION_SCHEMA.DBT_PROJECT_EXECUTION_HISTORY())
WHERE object_name = 'DBT_HANDSON'
  AND query_start_time >= DATEADD('hour', -24, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 1 DESC;
```

---

## 確認チェックリスト

- [ ] Snowsight の Transformation → dbt Projects で実行履歴が見える
- [ ] `DBT_PROJECT_EXECUTION_HISTORY()` で実行履歴を SQL で取得できる
- [ ] `SYSTEM$GET_DBT_LOG()` でログを取得できる
- [ ] `SYSTEM$LOCATE_DBT_ARTIFACTS()` でアーティファクトパスを取得できる
- [ ] `SYSTEM$LOCATE_DBT_ARCHIVE()` で ZIP アーカイブ URL を取得できる
- [ ] アーティファクトをステージにコピーできる
- [ ] 失敗時のデバッグフローを理解した
