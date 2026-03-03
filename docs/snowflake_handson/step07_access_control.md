# Step 7: アクセス制御

## 目的

dbt Projects on Snowflake に対する適切なロール設計と権限管理を行う。

---

## 前提条件

- Step 6 が完了していること（dbt Project Object がデプロイ・実行済み）

---

## 7-1. 権限の種類

| 操作 | 必要な権限 | GRANT 対象 |
|---|---|---|
| dbt Project 作成 | `CREATE DBT PROJECT` | スキーマに対して |
| 変更・削除 | `OWNERSHIP` | dbt Project オブジェクトに対して |
| 実行・ファイルアクセス | `USAGE` | dbt Project オブジェクトに対して |
| Snowsight で閲覧 | `MONITOR` | dbt Project オブジェクトに対して |

---

## 7-2. ロールの作成

**実行場所**: Snowflake ワークシート（ロール: `ACCOUNTADMIN`）

```sql
-- ============================================================
-- Step 7-2: ロールの作成
-- ============================================================

CREATE ROLE IF NOT EXISTS DBT_DEVELOPER;
CREATE ROLE IF NOT EXISTS DBT_OPERATOR;
CREATE ROLE IF NOT EXISTS ANALYST;

-- ロール階層の設定（SYSADMIN の下に配置）
GRANT ROLE DBT_DEVELOPER TO ROLE SYSADMIN;
GRANT ROLE DBT_OPERATOR TO ROLE SYSADMIN;
GRANT ROLE ANALYST TO ROLE SYSADMIN;
```

### ロール設計

| ロール | 用途 | 主な権限 |
|---|---|---|
| `DBT_DEVELOPER` | DEV 環境での開発・テスト | dbt Project 作成、モデル実行 |
| `DBT_OPERATOR` | PROD 環境での運用・監視 | dbt Project 実行、監視 |
| `ANALYST` | データの閲覧のみ | PROD データの SELECT、プロジェクト監視 |

---

## 7-3. DBT_DEVELOPER ロールの権限付与

```sql
-- ============================================================
-- Step 7-3: DBT_DEVELOPER ロールの権限
-- ============================================================

-- ウェアハウスの使用権限
GRANT USAGE ON WAREHOUSE ADMIN_WH TO ROLE DBT_DEVELOPER;

-- データベースへのアクセス
GRANT USAGE ON DATABASE DBT_PROJECT_DB TO ROLE DBT_DEVELOPER;
GRANT USAGE ON SCHEMA DBT_PROJECT_DB.DEV TO ROLE DBT_DEVELOPER;

-- DEV スキーマでの dbt Project 作成権限
GRANT CREATE DBT PROJECT ON SCHEMA DBT_PROJECT_DB.DEV TO ROLE DBT_DEVELOPER;

-- DEV スキーマでのオブジェクト作成権限（dbt run で必要）
GRANT CREATE TABLE ON SCHEMA DBT_PROJECT_DB.DEV TO ROLE DBT_DEVELOPER;
GRANT CREATE VIEW ON SCHEMA DBT_PROJECT_DB.DEV TO ROLE DBT_DEVELOPER;

-- ソースデータの読み取り権限
GRANT USAGE ON DATABASE JAFFLE_SHOP_RAW TO ROLE DBT_DEVELOPER;
GRANT USAGE ON SCHEMA JAFFLE_SHOP_RAW.JAFFLE_SHOP TO ROLE DBT_DEVELOPER;
GRANT SELECT ON ALL TABLES IN SCHEMA JAFFLE_SHOP_RAW.JAFFLE_SHOP TO ROLE DBT_DEVELOPER;
```

---

## 7-4. DBT_OPERATOR ロールの権限付与

```sql
-- ============================================================
-- Step 7-4: DBT_OPERATOR ロールの権限
-- ============================================================

GRANT USAGE ON WAREHOUSE ADMIN_WH TO ROLE DBT_OPERATOR;
GRANT USAGE ON DATABASE DBT_PROJECT_DB TO ROLE DBT_OPERATOR;
GRANT USAGE ON SCHEMA DBT_PROJECT_DB.PROD TO ROLE DBT_OPERATOR;

-- PROD プロジェクトの実行・監視権限
GRANT USAGE ON DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson TO ROLE DBT_OPERATOR;
GRANT MONITOR ON DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson TO ROLE DBT_OPERATOR;

-- PROD スキーマでの dbt Project 作成権限（デプロイ用）
GRANT CREATE DBT PROJECT ON SCHEMA DBT_PROJECT_DB.PROD TO ROLE DBT_OPERATOR;

-- PROD スキーマでのオブジェクト作成権限（dbt run で必要）
GRANT CREATE TABLE ON SCHEMA DBT_PROJECT_DB.PROD TO ROLE DBT_OPERATOR;
GRANT CREATE VIEW ON SCHEMA DBT_PROJECT_DB.PROD TO ROLE DBT_OPERATOR;

-- ソースデータの読み取り権限
GRANT USAGE ON DATABASE JAFFLE_SHOP_RAW TO ROLE DBT_OPERATOR;
GRANT USAGE ON SCHEMA JAFFLE_SHOP_RAW.JAFFLE_SHOP TO ROLE DBT_OPERATOR;
GRANT SELECT ON ALL TABLES IN SCHEMA JAFFLE_SHOP_RAW.JAFFLE_SHOP TO ROLE DBT_OPERATOR;
```

---

## 7-5. ANALYST ロールの権限付与

```sql
-- ============================================================
-- Step 7-5: ANALYST ロールの権限
-- ============================================================

GRANT USAGE ON WAREHOUSE ADMIN_WH TO ROLE ANALYST;
GRANT USAGE ON DATABASE DBT_PROJECT_DB TO ROLE ANALYST;
GRANT USAGE ON SCHEMA DBT_PROJECT_DB.PROD TO ROLE ANALYST;

-- プロジェクトの閲覧のみ
GRANT MONITOR ON DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson TO ROLE ANALYST;

-- PROD データの読み取り
GRANT SELECT ON ALL TABLES IN SCHEMA DBT_PROJECT_DB.PROD TO ROLE ANALYST;
GRANT SELECT ON ALL VIEWS IN SCHEMA DBT_PROJECT_DB.PROD TO ROLE ANALYST;

-- 今後作成されるオブジェクトにも自動で権限付与
GRANT SELECT ON FUTURE TABLES IN SCHEMA DBT_PROJECT_DB.PROD TO ROLE ANALYST;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA DBT_PROJECT_DB.PROD TO ROLE ANALYST;
```

---

## 7-6. ユーザーへのロール付与

```sql
-- ============================================================
-- Step 7-6: ユーザーへのロール付与
-- ============================================================

GRANT ROLE DBT_DEVELOPER TO USER KIKUCHI_TSUBASA;
GRANT ROLE DBT_OPERATOR TO USER KIKUCHI_TSUBASA;
GRANT ROLE ANALYST TO USER KIKUCHI_TSUBASA;
```

---

## 7-7. 実行時のロール解決

| コンテキスト | ロール解決順序 |
|---|---|
| SQL / CLI | 接続ロール → `profiles.yml` の `role` |
| Workspace | 選択ロール → `profiles.yml` の `role` + セカンダリロール |
| Task | タスクオーナーの権限（個人ユーザーに紐づかない） |

> **重要**: Task で `EXECUTE DBT PROJECT` を実行する場合、Task のオーナーロールが十分な権限を持っている必要がある。

---

## 7-8. 権限のテスト

```sql
-- ============================================================
-- Step 7-8: 権限のテスト
-- ============================================================

-- ----- DBT_DEVELOPER ロールでテスト -----
USE ROLE DBT_DEVELOPER;
USE WAREHOUSE ADMIN_WH;

-- DEV スキーマのテーブルが見えるか確認
SELECT * FROM DBT_PROJECT_DB.DEV.FCT_ORDERS LIMIT 5;
-- → 成功するはず

-- PROD スキーマのテーブルにはアクセスできないはず
-- SELECT * FROM DBT_PROJECT_DB.PROD.FCT_ORDERS LIMIT 5;
-- → エラーになるはず（PROD スキーマの USAGE 権限がない）


-- ----- DBT_OPERATOR ロールでテスト -----
USE ROLE DBT_OPERATOR;

-- PROD プロジェクトの情報が見えるか確認
SHOW DBT PROJECTS IN SCHEMA DBT_PROJECT_DB.PROD;
-- → dbt_handson が表示されるはず

-- 実行ができるか確認（軽量なコマンドで）
EXECUTE DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson
  ARGS = 'ls --target prod';
-- → モデル一覧が表示されるはず


-- ----- ANALYST ロールでテスト -----
USE ROLE ANALYST;

-- PROD データの読み取りのみ可能であることを確認
SELECT * FROM DBT_PROJECT_DB.PROD.FCT_ORDERS LIMIT 5;
-- → 成功するはず

-- dbt Project の実行はできないはず
-- EXECUTE DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson ARGS = 'run';
-- → 権限エラーになるはず


-- ----- ACCOUNTADMIN に戻す -----
USE ROLE ACCOUNTADMIN;
```

---

## 確認チェックリスト

- [ ] `DBT_DEVELOPER`, `DBT_OPERATOR`, `ANALYST` ロールが作成されている
- [ ] ロール階層が `SYSADMIN` の下に配置されている
- [ ] 各ロールに適切な権限が付与されている
- [ ] ユーザーに全ロールが付与されている
- [ ] DBT_DEVELOPER で DEV 環境にアクセスできる
- [ ] DBT_OPERATOR で PROD プロジェクトを実行・監視できる
- [ ] ANALYST で PROD データを閲覧のみできる（実行不可）
