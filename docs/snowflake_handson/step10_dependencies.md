# Step 10: 依存関係の管理

## 目的

dbt パッケージの依存関係を Snowflake 環境で適切に管理する方法を理解する。

---

## 前提条件

- Step 5 以降が完了していること（dbt Project がデプロイ・実行可能な状態）

---

## 10-1. dbt deps の2つの実行方法

| 方法 | 実行場所 | External Access Integration | メリット | デメリット |
|---|---|---|---|---|
| **Snowflake 内** | Workspace / EXECUTE | **必要** | Snowflake 完結 | ネットワーク設定が必要 |
| **ローカル / CI** | 外部 | **不要** | ネットワーク制限なし | `dbt_packages/` のサイズ分デプロイが遅くなる |

---

## 10-2. 方法A: Snowflake 内で dbt deps を実行

### デプロイ時に自動実行（推奨）

`EXTERNAL_ACCESS_INTEGRATIONS` を指定してデプロイすると、`dbt deps` が自動的に実行される。

#### SQL でのデプロイ

```sql
-- ============================================================
-- Step 10-2a: External Access Integration 付きデプロイ（SQL）
-- ============================================================

CREATE OR REPLACE DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson
  FROM 'snow://workspace/DBT_PROJECT_DB.DEV.dbt_handson_workspace/versions/live'
  DEFAULT_TARGET = 'prod'
  EXTERNAL_ACCESS_INTEGRATIONS = (dbt_ext_access);
```

#### CLI でのデプロイ

```bash
export SNOWFLAKE_CLI_FEATURES_ENABLE_DBT=true

snow dbt deploy dbt_handson \
  --source ./dbt_handson_project \
  --default-target prod \
  --external-access-integration dbt_ext_access \
  --force
```

### Workspace 内で手動実行

Workspace のターミナルで:

```
dbt deps
```

> **注意**: Workspace に External Access Integration が紐づいている必要がある。

---

## 10-3. 方法B: ローカルで dbt deps → パッケージごとデプロイ

External Access Integration を使わずに、ローカルでパッケージをインストールしてから丸ごとデプロイする方法。

### 手順

```bash
# 1. ローカルでパッケージをインストール
cd /c/Users/tsuba/dbt_handson/dbt_handson_project
dbt deps

# 2. dbt_packages/ を含めてデプロイ
export SNOWFLAKE_CLI_FEATURES_ENABLE_DBT=true

snow dbt deploy dbt_handson \
  --source ./dbt_handson_project \
  --default-target prod \
  --install-local-deps \
  --force
```

### ポイント

| 項目 | 説明 |
|---|---|
| `--install-local-deps` | ローカルの `dbt_packages/` を含めてデプロイする |
| メリット | `dbt_ext_access` が不要 |
| デメリット | `dbt_packages/` が大きい場合はデプロイに時間がかかる |

---

## 10-4. パッケージのバージョン管理

### 現在の packages.yml

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: ">=1.3.0"
  - package: calogica/dbt_expectations
    version: ">=0.10.0"
```

### バージョン固定（推奨）

本番環境の安定性を確保するため、バージョンを固定する:

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: "1.3.0"              # >= ではなく固定バージョン
  - package: calogica/dbt_expectations
    version: "0.10.4"             # >= ではなく固定バージョン
```

### dbt バージョン互換性に関する注意

> **重要**: Snowflake 上の dbt は **v1.9 系**。ローカルの v1.11 で動くパッケージが Snowflake 上で動かない場合がある。

確認方法:
1. 各パッケージの GitHub リポジトリで `require-dbt-version` を確認
2. パッケージの changelog で v1.9 対応状況を確認
3. 不安な場合は Workspace 上で `dbt compile` してみる

---

## 10-5. ネットワークルールの拡張

パッケージのダウンロード先によっては、ネットワークルールにホストを追加する必要がある。

```sql
-- ============================================================
-- Step 10-5: ネットワークルールの拡張
-- ============================================================

USE SCHEMA DBT_PROJECT_DB.INTEGRATIONS;

-- 追加のホストが必要な場合
CREATE OR REPLACE NETWORK RULE dbt_network_rule
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = (
    'hub.getdbt.com',              -- dbt Hub（Hub パッケージ用）
    'codeload.github.com',         -- GitHub（コードダウンロード用）
    'github.com',                  -- GitHub（Git パッケージ用）
    'raw.githubusercontent.com'    -- GitHub Raw（一部パッケージで必要）
  );

-- External Access Integration を再作成（ネットワークルール更新を反映）
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION dbt_ext_access
  ALLOWED_NETWORK_RULES = (DBT_PROJECT_DB.INTEGRATIONS.dbt_network_rule)
  ENABLED = TRUE;
```

### どのホストが必要かの判断

| パッケージの種類 | 必要なホスト |
|---|---|
| Hub パッケージ (`package:`) | `hub.getdbt.com`, `codeload.github.com` |
| Git パッケージ (`git:`) | `github.com`, `codeload.github.com` |
| プライベート Git パッケージ | `github.com` + 認証設定 |

---

## 10-6. クロスプロジェクト依存の対処法

`packages.yml` で `local: ../other_project` を使ったローカル依存は Snowflake 上では**非対応**。

### ワークアラウンド

依存プロジェクトをプロジェクトルート内にコピーする:

```bash
# 1. local_packages ディレクトリを作成
mkdir -p dbt_handson_project/local_packages

# 2. 依存プロジェクトをコピー
cp -R ../other_project ./dbt_handson_project/local_packages/other_project
```

```yaml
# packages.yml（修正後）
packages:
  - package: dbt-labs/dbt_utils
    version: ">=1.3.0"
  - package: calogica/dbt_expectations
    version: ">=0.10.0"
  - local: local_packages/other_project
```

> **注意**: コピーしたプロジェクトは Git 管理対象に含まれるため、`.gitignore` で除外するか、CI/CD パイプラインでコピーステップを追加するか検討すること。

---

## 10-7. package-lock.yml について

`dbt deps` 実行後に `package-lock.yml` が生成される。このファイルにはインストールされたパッケージの正確なバージョンが記録される。

### 推奨

- `package-lock.yml` を **Git にコミット**して、チーム全員が同じバージョンを使えるようにする
- CI/CD パイプラインでも同じバージョンが使われることを保証する

```bash
git add dbt_handson_project/package-lock.yml
git commit -m "Lock package versions"
git push origin main
```

---

## 確認チェックリスト

- [ ] パッケージ依存の2つの管理方法（Snowflake 内 / ローカル）を理解した
- [ ] External Access Integration を使った自動 deps が動作する
- [ ] `--install-local-deps` を使った手動デプロイが動作する
- [ ] パッケージのバージョン互換性（dbt 1.9 系）を確認した
- [ ] ネットワークルールの拡張方法を理解した
- [ ] `package-lock.yml` が Git にコミットされている
