# Step 8: CI/CD パイプライン（GitHub Actions）

## 目的

GitHub Actions で PR 時のテスト（CI）とマージ時のデプロイ（CD）を自動化する。

---

## 前提条件

- Step 7 までが完了していること
- GitHub リポジトリが存在し、コードがプッシュ済みであること
- Snowflake に ACCOUNTADMIN 権限があること

---

## 8-1. OIDC サービスユーザーの作成

OIDC（OpenID Connect）を使うことで、GitHub Actions からパスワードなしで Snowflake に接続できる。

**実行場所**: Snowflake ワークシート（ロール: `ACCOUNTADMIN`）

```sql
-- ============================================================
-- Step 8-1: OIDC サービスユーザーの作成
-- ============================================================

CREATE USER IF NOT EXISTS github_actions_service_user
  TYPE = SERVICE
  WORKLOAD_IDENTITY = (
    TYPE = OIDC
    ISSUER = 'https://token.actions.githubusercontent.com',
    SUBJECT = 'repo:Tsubasa-Kikuchi98/dbt-handson:environment:prod'
  )
  DEFAULT_ROLE = DBT_OPERATOR
  COMMENT = 'GitHub Actions 用サービスユーザー（OIDC認証）';
```

> **重要**: `SUBJECT` のフォーマットは `repo:<org>/<repo>:environment:<environment_name>`。GitHub の Environment 名と一致させる必要がある。

### 権限の付与

```sql
-- 必要な権限の付与
GRANT ROLE DBT_OPERATOR TO USER github_actions_service_user;
GRANT ROLE DBT_DEVELOPER TO USER github_actions_service_user;
```

---

## 8-2. ネットワークポリシーの設定

GitHub Actions の IP 範囲からの接続を許可する。

```sql
-- ============================================================
-- Step 8-2: ネットワークポリシーの設定
-- ============================================================

CREATE OR REPLACE NETWORK POLICY github_actions_policy
  ALLOWED_NETWORK_RULE_LIST = ('SNOWFLAKE.NETWORK_SECURITY.GITHUBACTIONS_GLOBAL')
  BLOCKED_NETWORK_RULE_LIST = ();

ALTER USER github_actions_service_user SET NETWORK_POLICY = github_actions_policy;
```

---

## 8-3. GitHub の設定

### (a) GitHub Environment の作成

1. GitHub リポジトリ → **Settings** → **Environments**
2. **「New environment」** をクリック
3. Name: `prod` と入力
4. **「Configure environment」** をクリック
5. Protection rules（任意設定）:
   - **Required reviewers**: 本番デプロイ前にレビュー必須にする場合に設定
   - **Wait timer**: デプロイ前に待機時間を設定する場合

### (b) GitHub Secrets の設定

1. GitHub リポジトリ → **Settings** → **Secrets and variables** → **Actions**
2. 上部の **「Environment secrets」** タブを選択し、`prod` 環境を選択
3. **「New environment secret」** で以下を追加:

| Secret 名 | 値 |
|---|---|
| `SNOWFLAKE_ACCOUNT` | `MYLMWWX-IFTC_DATADRESSER_REBUILD` |
| `SNOWFLAKE_USER` | `github_actions_service_user` |

### (c) GitHub Variables の設定

同じ画面の **「Variables」** タブで以下を追加:

| Variable 名 | 値 |
|---|---|
| `SNOWFLAKE_DATABASE` | `DBT_PROJECT_DB` |
| `SNOWFLAKE_SCHEMA` | `PROD` |

---

## 8-4. CI ワークフローの作成（PR 時）

PR が作成・更新された時に、テスト用 dbt Project をデプロイしてテストを実行する。

**ファイル**: `.github/workflows/incoming_pr.yml`

以下の内容で作成する:

```yaml
name: CI - dbt Test

on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
    branches: [main]

permissions:
  contents: read
  id-token: write

jobs:
  dbt-test:
    runs-on: ubuntu-latest
    environment: prod
    env:
      SNOWFLAKE_CLI_FEATURES_ENABLE_DBT: true
      SNOWFLAKE_ACCOUNT: ${{ secrets.SNOWFLAKE_ACCOUNT }}
      SNOWFLAKE_DATABASE: ${{ vars.SNOWFLAKE_DATABASE }}
      SNOWFLAKE_SCHEMA: ${{ vars.SNOWFLAKE_SCHEMA }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install Snowflake CLI
        uses: snowflakedb/snowflake-cli-action@v2.0
        with:
          use-oidc: true

      - name: Deploy test project
        run: |
          snow dbt deploy ci_test_project \
            --source ./dbt_handson_project \
            --default-target dev \
            --external-access-integration dbt_ext_access \
            --force -x

      - name: Run dbt models
        run: |
          snow dbt execute -x ci_test_project run --target dev

      - name: Run dbt tests
        run: |
          snow dbt execute -x ci_test_project test --target dev
```

### ポイント

| 項目 | 説明 |
|---|---|
| `id-token: write` | OIDC トークンの取得に必要な権限 |
| `environment: prod` | GitHub Environment `prod` を使用（Secrets/Variables の参照先） |
| `-x` フラグ | 一時的な接続を使用（OIDC トークンベースの認証に必要） |
| `ci_test_project` | テスト用の一時的な dbt Project 名（本番とは別） |
| `--force` | 前回の CI で作成された同名プロジェクトを上書き |

---

## 8-5. CD ワークフローの作成（マージ時）

main ブランチへのマージ時に、本番環境にデプロイする。

**ファイル**: `.github/workflows/deploy_prod.yml`

以下の内容で作成する:

```yaml
name: CD - Deploy to Production

on:
  push:
    branches: [main]

permissions:
  contents: read
  id-token: write

jobs:
  dbt-deploy:
    runs-on: ubuntu-latest
    environment: prod
    env:
      SNOWFLAKE_CLI_FEATURES_ENABLE_DBT: true
      SNOWFLAKE_ACCOUNT: ${{ secrets.SNOWFLAKE_ACCOUNT }}
      SNOWFLAKE_DATABASE: ${{ vars.SNOWFLAKE_DATABASE }}
      SNOWFLAKE_SCHEMA: ${{ vars.SNOWFLAKE_SCHEMA }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install Snowflake CLI
        uses: snowflakedb/snowflake-cli-action@v2.0
        with:
          use-oidc: true

      - name: Deploy to production
        run: |
          snow dbt deploy dbt_handson \
            --source ./dbt_handson_project \
            --default-target prod \
            --external-access-integration dbt_ext_access \
            --force -x

      - name: Run dbt build in production
        run: |
          snow dbt execute -x dbt_handson build --target prod
```

---

## 8-6. ディレクトリ構成

ワークフローファイルの配置場所:

```
dbt_handson/
├── .github/
│   └── workflows/
│       ├── incoming_pr.yml      ← CI ワークフロー
│       └── deploy_prod.yml      ← CD ワークフロー
├── dbt_handson_project/
│   └── ...
└── ...
```

---

## 8-7. ファイルのコミット・プッシュ

**実行場所**: ローカルターミナル

```bash
cd /c/Users/tsuba/dbt_handson

# ディレクトリの作成
mkdir -p .github/workflows

# ファイルを作成した後:
git add .github/workflows/incoming_pr.yml
git add .github/workflows/deploy_prod.yml
git commit -m "Add CI/CD workflows for dbt Projects on Snowflake"
git push origin main
```

---

## 8-8. CI/CD の動作確認

### CI のテスト

1. 新しいブランチを作成:
   ```bash
   git checkout -b test/ci-pipeline
   ```

2. 何か軽微な変更を加える（例: モデルにコメントを追加）:
   ```bash
   # 例: fct_orders.sql の先頭にコメントを追加
   ```

3. コミット・プッシュ:
   ```bash
   git add .
   git commit -m "Test CI pipeline"
   git push origin test/ci-pipeline
   ```

4. GitHub で main ブランチに対して **Pull Request** を作成

5. GitHub リポジトリの **Actions** タブで CI ワークフローの実行を確認

6. 全ステップが緑（成功）になることを確認

### CD のテスト

1. 上記の Pull Request を **Merge** する

2. GitHub リポジトリの **Actions** タブで CD ワークフローが自動実行されることを確認

3. Snowflake で確認:
   ```sql
   SHOW DBT PROJECTS IN SCHEMA DBT_PROJECT_DB.PROD;
   SHOW VERSIONS IN DBT PROJECT DBT_PROJECT_DB.PROD.dbt_handson;
   ```

4. 新バージョンがデプロイされていることを確認

### トラブルシューティング

| エラー | 原因 | 対処法 |
|---|---|---|
| `Error: OIDC token` | OIDC 設定の不一致 | サービスユーザーの SUBJECT とリポジトリ/Environment 名を確認 |
| `Insufficient privileges` | ロールの権限不足 | サービスユーザーに必要な権限を付与 |
| `Network policy` エラー | IP 制限 | ネットワークポリシーを確認 |
| `dbt deps` 失敗 | External Access Integration | `dbt_ext_access` が有効であることを確認 |

---

## 確認チェックリスト

- [ ] OIDC サービスユーザー `github_actions_service_user` が作成されている
- [ ] ネットワークポリシー `github_actions_policy` が設定されている
- [ ] GitHub Environment `prod` が作成されている
- [ ] GitHub Secrets（`SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`）が設定されている
- [ ] GitHub Variables（`SNOWFLAKE_DATABASE`, `SNOWFLAKE_SCHEMA`）が設定されている
- [ ] `.github/workflows/incoming_pr.yml` が作成・プッシュされている
- [ ] `.github/workflows/deploy_prod.yml` が作成・プッシュされている
- [ ] PR 作成時に CI ワークフローが自動実行される
- [ ] main マージ時に CD ワークフローが自動実行される
