# Step 6: 実行とスケジューリング

## 目的

デプロイした dbt Project を Snowflake 上で実行し、Snowflake Task で定期実行をスケジューリングする。

---

## 前提条件

- Step 5 が完了していること（dbt Project Object がデプロイ済み）

---

## 6-1. SQL での実行

**実行場所**: Snowflake ワークシート（ロール: `ACCOUNTADMIN`）

### dbt run（dev ターゲット）

```sql
-- ============================================================
-- Step 6-1a: dbt run（dev ターゲット）
-- ============================================================

EXECUTE DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson
  ARGS = 'run --target dev';
```

> **注意**: 実行には時間がかかる場合がある。結果はコマンド完了後に表示される（リアルタイム出力は非対応）。

### dbt build（prod ターゲット）

```sql
-- ============================================================
-- Step 6-1b: dbt build（prod ターゲット）
-- ============================================================

EXECUTE DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson
  ARGS = 'build --target prod';
```

### dbt test

```sql
-- ============================================================
-- Step 6-1c: dbt test
-- ============================================================

EXECUTE DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson
  ARGS = 'test --target prod';
```

### 特定モデルのみ実行

```sql
-- fct_orders とその上流のみ実行
EXECUTE DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson
  ARGS = 'run --target prod --select +fct_orders';
```

### 特定バージョンで実行

```sql
-- VERSION$1 で実行
EXECUTE DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson
  VERSION = 'VERSION$1'
  ARGS = 'run --target prod';

-- 最新バージョンで実行
EXECUTE DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson
  VERSION = LAST
  ARGS = 'run --target prod';
```

### vars の渡し方

`env_var()` が非対応のため、変数は `--vars` で渡す:

```sql
EXECUTE DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson
  ARGS = 'run --target prod --vars ''{my_var: my_value}''';
```

> **注意**: SQL 内の文字列リテラルではシングルクォートをエスケープするため `''` を使う。

---

## 6-2. Snowflake CLI での実行

**実行場所**: ローカルターミナル

```bash
export SNOWFLAKE_CLI_FEATURES_ENABLE_DBT=true

# dbt run
snow dbt execute dbt_handson run --target dev

# dbt build
snow dbt execute dbt_handson build --target prod

# dbt test
snow dbt execute dbt_handson test --target prod

# 特定モデルのみ
snow dbt execute dbt_handson run --target prod -- --select +fct_orders
```

---

## 6-3. 実行結果の確認

**実行場所**: Snowflake ワークシート

```sql
-- ============================================================
-- Step 6-3: 実行結果の確認
-- ============================================================

-- 最近の EXECUTE DBT PROJECT の履歴
SELECT query_id, query_text, status, start_time, end_time,
       DATEDIFF('second', start_time, end_time) AS duration_sec
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text LIKE '%EXECUTE DBT PROJECT%'
ORDER BY start_time DESC
LIMIT 10;

-- PROD スキーマのオブジェクトを確認
USE SCHEMA DBT_PROJECT_DB.PROD;
SHOW TABLES;
SHOW VIEWS;

-- データの確認
SELECT COUNT(*) AS row_count FROM DBT_PROJECT_DB.PROD.FCT_ORDERS;
SELECT COUNT(*) AS row_count FROM DBT_PROJECT_DB.PROD.DIM_CUSTOMERS;
SELECT * FROM DBT_PROJECT_DB.PROD.FCT_ORDERS LIMIT 10;
```

---

## 6-4. Snowflake Task によるスケジューリング

**実行場所**: Snowflake ワークシート（ロール: `ACCOUNTADMIN`）

### 基本的な定期実行タスク（インターバル指定）

```sql
-- ============================================================
-- Step 6-4a: 定期実行タスクの作成（6時間ごと）
-- ============================================================

CREATE OR REPLACE TASK DBT_PROJECT_DB.PROD.run_dbt_handson
  WAREHOUSE = ADMIN_WH
  SCHEDULE = '360 MINUTE'
AS
  EXECUTE DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson
    ARGS = 'build --target prod';
```

### 依存タスク（メインタスクの後にテスト実行）

```sql
-- ============================================================
-- Step 6-4b: 依存タスクの作成（build 後にテスト）
-- ============================================================

CREATE OR REPLACE TASK DBT_PROJECT_DB.PROD.test_dbt_handson
  WAREHOUSE = ADMIN_WH
  AFTER DBT_PROJECT_DB.PROD.run_dbt_handson
AS
  EXECUTE DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson
    ARGS = 'test --target prod';
```

### タスクの有効化

```sql
-- ============================================================
-- Step 6-4c: タスクの有効化
-- ============================================================

-- 重要: 子タスクから先に RESUME する
ALTER TASK DBT_PROJECT_DB.PROD.test_dbt_handson RESUME;
ALTER TASK DBT_PROJECT_DB.PROD.run_dbt_handson RESUME;
```

> **重要**: タスクはデフォルトで `SUSPENDED` 状態。`RESUME` しないと実行されない。**子タスクから先に有効化**すること。

---

## 6-5. Cron スケジュール

### 毎日午前2時（JST）に実行

```sql
-- ============================================================
-- Step 6-5: Cron スケジュールのタスク
-- ============================================================

CREATE OR REPLACE TASK DBT_PROJECT_DB.PROD.nightly_dbt_build
  WAREHOUSE = ADMIN_WH
  SCHEDULE = 'USING CRON 0 2 * * * Asia/Tokyo'
AS
  EXECUTE DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson
    ARGS = 'build --target prod';

-- タスクを有効化
ALTER TASK DBT_PROJECT_DB.PROD.nightly_dbt_build RESUME;
```

### Cron 式のリファレンス

```
┌───────────── 分 (0 - 59)
│ ┌───────────── 時 (0 - 23)
│ │ ┌───────────── 日 (1 - 31)
│ │ │ ┌───────────── 月 (1 - 12)
│ │ │ │ ┌───────────── 曜日 (0 - 6, 日曜 = 0)
│ │ │ │ │
│ │ │ │ │
* * * * *
```

| 例 | Cron 式 | 説明 |
|---|---|---|
| 毎日午前2時 (JST) | `0 2 * * * Asia/Tokyo` | 日次バッチ |
| 平日午前6時 (JST) | `0 6 * * 1-5 Asia/Tokyo` | 営業日のみ |
| 毎時0分 | `0 * * * * UTC` | 1時間ごと |
| 毎月1日午前0時 | `0 0 1 * * Asia/Tokyo` | 月次バッチ |

---

## 6-6. タスクの管理

```sql
-- ============================================================
-- Step 6-6: タスクの管理
-- ============================================================

-- タスク一覧の確認
SHOW TASKS IN SCHEMA DBT_PROJECT_DB.PROD;

-- タスクの実行履歴
SELECT *
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
  SCHEDULED_TIME_RANGE_START => DATEADD('hour', -24, CURRENT_TIMESTAMP()),
  TASK_NAME => 'RUN_DBT_HANDSON'
))
ORDER BY scheduled_time DESC;

-- タスクの一時停止（メンテナンス時など）
-- 重要: 親タスクから先に SUSPEND する
ALTER TASK DBT_PROJECT_DB.PROD.run_dbt_handson SUSPEND;
ALTER TASK DBT_PROJECT_DB.PROD.test_dbt_handson SUSPEND;

-- タスクの再開
ALTER TASK DBT_PROJECT_DB.PROD.test_dbt_handson RESUME;
ALTER TASK DBT_PROJECT_DB.PROD.run_dbt_handson RESUME;

-- タスクの手動実行（スケジュール外で即座に実行）
EXECUTE TASK DBT_PROJECT_DB.PROD.run_dbt_handson;

-- タスクの削除（不要になった場合）
-- DROP TASK DBT_PROJECT_DB.PROD.test_dbt_handson;
-- DROP TASK DBT_PROJECT_DB.PROD.run_dbt_handson;
```

---

## 確認チェックリスト

- [ ] `EXECUTE DBT PROJECT` で dbt run が正常に完了した
- [ ] PROD スキーマにテーブル/ビューが作成された
- [ ] `dbt test` がパスした
- [ ] Snowflake Task が作成されている
- [ ] Task が `RESUME` 状態になっている
- [ ] `SHOW TASKS` でタスクが確認できる
- [ ] タスクの実行履歴が確認できる
