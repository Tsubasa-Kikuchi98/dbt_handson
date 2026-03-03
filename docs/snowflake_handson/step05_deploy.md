# Step 5: デプロイ

## 目的

dbt プロジェクトを Snowflake の **dbt Project Object** としてデプロイする。

---

## 前提条件

- Step 4 までが完了していること
- Workspace が正常に動作し、`dbt build` が成功すること
- GitHub に最新のコードがプッシュ済みであること

---

## 5-1. デプロイの3つの方法（概要）

| 方法 | 用途 | 難易度 |
|---|---|---|
| **Snowsight（Workspace）** | 開発時の手動デプロイ | 簡単 |
| **SQL コマンド** | 自動化・スクリプト化 | 中程度 |
| **Snowflake CLI（`snow`）** | CI/CD パイプライン | 中程度 |

---

## 5-2. 方法A: Workspace からデプロイ（最も簡単）

### 操作手順

1. Snowsight → **Projects** → **Workspaces** → `dbt_handson_workspace` を開く
2. 右上の **「Connect」** ボタンをクリック
3. **「Deploy dbt project」** を選択
4. 以下を入力:

| 項目 | 値 |
|---|---|
| Database | `DBT_PROJECT_DB` |
| Schema | `PROD` |
| Project name | `dbt_handson` |
| Default target | `prod` |
| External Access Integration | `dbt_ext_access` |

5. **「Deploy」** をクリック

> **ポイント**: この操作で `VERSION$1` が自動作成される。

---

## 5-3. 方法B: SQL コマンドでデプロイ

**実行場所**: Snowflake ワークシート（ロール: `ACCOUNTADMIN`）

### 初回デプロイ（VERSION$1 が作成される）

```sql
-- ============================================================
-- Step 5-3a: 初回デプロイ（SQL）
-- ============================================================

CREATE DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson
  FROM 'snow://workspace/DBT_PROJECT_DB.DEV.dbt_handson_workspace/versions/live'
  DEFAULT_TARGET = 'prod'
  EXTERNAL_ACCESS_INTEGRATIONS = (dbt_ext_access)
  COMMENT = 'dbt ハンズオンプロジェクト';
```

> **注意**: Workspace のパスは環境によって異なる場合がある。Workspace の画面で確認すること。

### バージョン追加（VERSION$2 以降）

コード変更後に新しいバージョンを追加する場合:

```sql
-- ============================================================
-- Step 5-3b: バージョン追加
-- ============================================================

ALTER DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson
  ADD VERSION
  FROM 'snow://workspace/DBT_PROJECT_DB.DEV.dbt_handson_workspace/versions/live';
```

### 上書きデプロイ（バージョンリセット）

バージョン履歴をリセットして最初からやり直す場合:

```sql
-- ============================================================
-- Step 5-3c: 上書きデプロイ（VERSION$1 にリセット）
-- ============================================================

CREATE OR REPLACE DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson
  FROM 'snow://workspace/DBT_PROJECT_DB.DEV.dbt_handson_workspace/versions/live'
  DEFAULT_TARGET = 'prod'
  EXTERNAL_ACCESS_INTEGRATIONS = (dbt_ext_access)
  COMMENT = 'dbt ハンズオンプロジェクト';
```

---

## 5-4. 方法C: Snowflake CLI でデプロイ

### (a) Snowflake CLI のインストール（まだの場合）

```bash
pip install snowflake-cli
```

### (b) Snowflake CLI の接続設定

```bash
snow connection add
```

対話式プロンプトで以下を入力:

| 項目 | 値 |
|---|---|
| Connection name | `default` |
| Account | `MYLMWWX-IFTC_DATADRESSER_REBUILD` |
| User | `KIKUCHI_TSUBASA` |
| Password | （Snowflake パスワード） |
| Role | `ACCOUNTADMIN` |
| Warehouse | `ADMIN_WH` |
| Database | `DBT_PROJECT_DB` |
| Schema | `PROD` |

**接続テスト:**

```bash
snow connection test
```

**期待される結果:**
```
+- -+
| key              | value                  |
+------------------+------------------------+
| Connection name  | default                |
| Status           | OK                     |
| ...              |                        |
+------------------+------------------------+
```

### (c) CLI でデプロイ

```bash
# dbt 機能を有効化（環境変数）
export SNOWFLAKE_CLI_FEATURES_ENABLE_DBT=true

# デプロイ
snow dbt deploy dbt_handson \
  --source ./dbt_handson_project \
  --default-target prod \
  --external-access-integration dbt_ext_access \
  --force
```

> **`--force`**: 既存プロジェクトを上書きする場合に必要。初回デプロイ時は不要。

---

## 5-5. ソースファイルの配置場所（参考）

デプロイ元として指定できるソース:

| ソース | FROM 句の例 | 用途 |
|---|---|---|
| Workspace | `'snow://workspace/.../versions/live'` | Workspace から直接 |
| Git リポジトリステージ | `'@db.schema.git_stage/branches/main/path'` | Git ブランチ指定 |
| 既存 dbt Project | `'snow://dbt/db.schema.project/versions/last'` | 別プロジェクトから複製 |
| 内部ステージ | `'@db.schema.stage/path'` | ステージにアップロード済みファイル |

---

## 5-6. デプロイの確認

**実行場所**: Snowflake ワークシート

```sql
-- ============================================================
-- Step 5-6: デプロイの確認
-- ============================================================

-- デプロイされた dbt Project の一覧
SHOW DBT PROJECTS IN DATABASE DBT_PROJECT_DB;

-- 特定プロジェクトの詳細
DESCRIBE DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson;

-- バージョン一覧
SHOW VERSIONS IN DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson;

-- プロジェクト内のファイル一覧
SELECT * FROM TABLE(
  DBT_PROJECT_DB.PROD.dbt_handson!LIST_FILES()
);
```

### 期待される結果

- `SHOW DBT PROJECTS` に `dbt_handson` が表示される
- `SHOW VERSIONS` に `VERSION$1` が表示される
- `LIST_FILES()` にモデル、マクロ、設定ファイルが一覧表示される

---

## 確認チェックリスト

- [ ] いずれかの方法で dbt Project Object がデプロイされている
- [ ] `SHOW DBT PROJECTS` でプロジェクトが表示される
- [ ] `DESCRIBE DBT PROJECT` でプロジェクト詳細が確認できる
- [ ] `SHOW VERSIONS` でバージョンが確認できる
- [ ] `LIST_FILES()` でプロジェクトファイルが確認できる
