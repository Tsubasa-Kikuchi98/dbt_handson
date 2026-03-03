# Step 2: 環境セットアップ

## 目的

Snowflake 側にデータベース・スキーマ・統合オブジェクトを作成し、dbt Projects on Snowflake を使う準備を整える。

---

## 前提情報

| 項目 | 値 |
|---|---|
| Snowflake アカウント | `MYLMWWX-IFTC_DATADRESSER_REBUILD` |
| Snowflake ユーザー | `KIKUCHI_TSUBASA` |
| 現在のロール | `ACCOUNTADMIN` |
| 現在のウェアハウス | `ADMIN_WH` |
| dbt プロジェクトパス | `c:\Users\tsuba\dbt_handson\dbt_handson_project\` |
| GitHub ユーザー | `Tsubasa-Kikuchi98` |

> **注意**: `<your_github_pat>` や `<your_repo>` などのプレースホルダーは実際の値に置き換えてください。

---

## 2-1. データベースとスキーマの作成

**実行場所**: Snowflake ワークシート（ロール: `ACCOUNTADMIN`）

```sql
-- ============================================================
-- Step 2-1: データベースとスキーマの作成
-- ============================================================

-- dbt Projects on Snowflake 用のデータベース
CREATE DATABASE IF NOT EXISTS DBT_PROJECT_DB;

-- 統合オブジェクト（シークレット、API Integration等）用スキーマ
CREATE SCHEMA IF NOT EXISTS DBT_PROJECT_DB.INTEGRATIONS;

-- 開発環境用スキーマ
CREATE SCHEMA IF NOT EXISTS DBT_PROJECT_DB.DEV;

-- 本番環境用スキーマ
CREATE SCHEMA IF NOT EXISTS DBT_PROJECT_DB.PROD;
```

**確認コマンド:**

```sql
SHOW SCHEMAS IN DATABASE DBT_PROJECT_DB;
```

**期待される結果**: `INTEGRATIONS`, `DEV`, `PROD`, `PUBLIC`, `INFORMATION_SCHEMA` の5スキーマが表示される。

---

## 2-2. GitHub リポジトリの準備

**実行場所**: ローカルターミナル

既にリポジトリが存在する前提。まだ GitHub にプッシュされていない場合:

```bash
cd /c/Users/tsuba/dbt_handson
git remote -v
```

リモートが設定されていることを確認する。設定されていない場合:

```bash
git remote add origin https://github.com/Tsubasa-Kikuchi98/dbt-handson.git
git push -u origin main
```

---

## 2-3. profiles.yml をプロジェクトルートに配置

**重要**: Workspace で dbt を実行するには、`profiles.yml` が **プロジェクトディレクトリのルート**（`dbt_handson_project/` 直下）に必要。

**実行場所**: ローカルでファイルを作成

`dbt_handson_project/profiles.yml` を以下の内容で作成する:

```yaml
dbt_handson_project:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: "placeholder"
      user: "placeholder"
      warehouse: ADMIN_WH
      database: DBT_PROJECT_DB
      schema: DEV
      role: ACCOUNTADMIN
    prod:
      type: snowflake
      account: "placeholder"
      user: "placeholder"
      warehouse: ADMIN_WH
      database: DBT_PROJECT_DB
      schema: PROD
      role: ACCOUNTADMIN
```

> **ポイント**: `account` と `user` は `"placeholder"` でよい。Workspace 実行時は Snowsight にログイン中のユーザー情報が使われる。

**変更をコミット・プッシュ:**

```bash
cd /c/Users/tsuba/dbt_handson
git add dbt_handson_project/profiles.yml
git commit -m "Add profiles.yml for Snowflake Workspace"
git push origin main
```

---

## 2-4. ソースデータの準備

現在のプロジェクトは `JAFFLE_SHOP_RAW.JAFFLE_SHOP` スキーマのデータを参照している。`DBT_PROJECT_DB` 環境で動かすには、ソースデータが参照できる必要がある。

### 方法A: クロスデータベース参照をそのまま使う（推奨）

ソース定義 (`_jaffle_shop__sources.yml`) に `database: JAFFLE_SHOP_RAW` が指定されているため、`DBT_PROJECT_DB` からでもクロスデータベースで参照可能。**追加作業不要。**

### 方法B: データをコピーする場合

```sql
-- 必要に応じてソースデータを DBT_PROJECT_DB にコピー
CREATE SCHEMA IF NOT EXISTS DBT_PROJECT_DB.JAFFLE_SHOP;

CREATE TABLE DBT_PROJECT_DB.JAFFLE_SHOP.CUSTOMERS AS
  SELECT * FROM JAFFLE_SHOP_RAW.JAFFLE_SHOP.CUSTOMERS;

CREATE TABLE DBT_PROJECT_DB.JAFFLE_SHOP.ORDERS AS
  SELECT * FROM JAFFLE_SHOP_RAW.JAFFLE_SHOP.ORDERS;

CREATE TABLE DBT_PROJECT_DB.JAFFLE_SHOP.PAYMENTS AS
  SELECT * FROM JAFFLE_SHOP_RAW.JAFFLE_SHOP.PAYMENTS;
```

> この方法を選ぶ場合は、ソース定義の `database` を `DBT_PROJECT_DB` に変更する必要がある。

---

## 2-5. API Integration の作成（GitHub 接続用）

**実行場所**: Snowflake ワークシート（ロール: `ACCOUNTADMIN`）

### (a) GitHub Personal Access Token (PAT) の取得

1. GitHub → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)**
2. **「Generate new token (classic)」** をクリック
3. 以下を設定:
   - **Note**: `snowflake-workspace-access`
   - **Expiration**: 90 days（または任意）
   - **Scopes**: `repo`（リポジトリ全アクセス）にチェック
4. **「Generate token」** をクリックし、トークンをコピー

> **注意**: トークンはこの画面でしか表示されない。必ずコピーして安全な場所に保存すること。

### (b) シークレットの作成

```sql
-- ============================================================
-- Step 2-5b: GitHub シークレットの作成
-- ============================================================

USE SCHEMA DBT_PROJECT_DB.INTEGRATIONS;

CREATE OR REPLACE SECRET github_secret
  TYPE = PASSWORD
  USERNAME = 'Tsubasa-Kikuchi98'
  PASSWORD = '<ここに GitHub PAT を貼り付け>';
```

> **注意**: `<ここに GitHub PAT を貼り付け>` を実際のトークンに置き換えること。

### (c) API Integration の作成

```sql
-- ============================================================
-- Step 2-5c: API Integration の作成
-- ============================================================

CREATE OR REPLACE API INTEGRATION github_api_integration
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/Tsubasa-Kikuchi98/')
  ALLOWED_AUTHENTICATION_SECRETS = (DBT_PROJECT_DB.INTEGRATIONS.github_secret)
  ENABLED = TRUE;
```

**確認コマンド:**

```sql
DESCRIBE API INTEGRATION github_api_integration;
```

---

## 2-6. External Access Integration の作成（dbt deps 用）

dbt パッケージ（dbt-utils, dbt-expectations）を Snowflake 内でダウンロードするために、外部ネットワークへのアクセスを許可する。

**実行場所**: Snowflake ワークシート（ロール: `ACCOUNTADMIN`）

```sql
-- ============================================================
-- Step 2-6: External Access Integration の作成
-- ============================================================

USE SCHEMA DBT_PROJECT_DB.INTEGRATIONS;

-- ネットワークルール: dbt Hub と GitHub のホストを許可
CREATE OR REPLACE NETWORK RULE dbt_network_rule
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('hub.getdbt.com', 'codeload.github.com');

-- External Access Integration の作成
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION dbt_ext_access
  ALLOWED_NETWORK_RULES = (DBT_PROJECT_DB.INTEGRATIONS.dbt_network_rule)
  ENABLED = TRUE;
```

**確認コマンド:**

```sql
DESCRIBE EXTERNAL ACCESS INTEGRATION dbt_ext_access;
```

---

## 2-7. 監視の有効化

**実行場所**: Snowflake ワークシート（ロール: `ACCOUNTADMIN`）

```sql
-- ============================================================
-- Step 2-7: 監視レベルの設定
-- ============================================================

-- DEV スキーマ
ALTER SCHEMA DBT_PROJECT_DB.DEV SET LOG_LEVEL = 'INFO';
ALTER SCHEMA DBT_PROJECT_DB.DEV SET TRACE_LEVEL = 'ALWAYS';
ALTER SCHEMA DBT_PROJECT_DB.DEV SET METRIC_LEVEL = 'ALL';

-- PROD スキーマ
ALTER SCHEMA DBT_PROJECT_DB.PROD SET LOG_LEVEL = 'INFO';
ALTER SCHEMA DBT_PROJECT_DB.PROD SET TRACE_LEVEL = 'ALWAYS';
ALTER SCHEMA DBT_PROJECT_DB.PROD SET METRIC_LEVEL = 'ALL';
```

---

## 確認チェックリスト

- [ ] `DBT_PROJECT_DB` データベースと 3 スキーマ（INTEGRATIONS, DEV, PROD）が作成されている
- [ ] GitHub リポジトリにコードがプッシュされている
- [ ] `dbt_handson_project/profiles.yml` がプロジェクトルートに配置されている
- [ ] GitHub PAT を取得し、Snowflake シークレットに登録した
- [ ] `github_api_integration` が作成されている
- [ ] `dbt_ext_access` External Access Integration が作成されている
- [ ] DEV / PROD スキーマの監視設定が有効になっている
