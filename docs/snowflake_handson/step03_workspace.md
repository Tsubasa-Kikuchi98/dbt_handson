# Step 3: Workspace の作成と操作

## 目的

Snowsight 上に Workspace を作成し、GitHub リポジトリと接続して dbt の開発・実行を行う。

---

## 前提条件

- Step 2 が完了していること（データベース、スキーマ、API Integration、External Access Integration が作成済み）
- GitHub リポジトリに最新のコードがプッシュ済みであること
- `dbt_handson_project/profiles.yml` がリポジトリに含まれていること

---

## 3-1. Git リポジトリオブジェクトの作成

**実行場所**: Snowflake ワークシート（ロール: `ACCOUNTADMIN`）

```sql
-- ============================================================
-- Step 3-1: Git リポジトリオブジェクトの作成
-- ============================================================

USE SCHEMA DBT_PROJECT_DB.INTEGRATIONS;

CREATE OR REPLACE GIT REPOSITORY dbt_handson_repo
  API_INTEGRATION = github_api_integration
  GIT_CREDENTIALS = DBT_PROJECT_DB.INTEGRATIONS.github_secret
  ORIGIN = 'https://github.com/Tsubasa-Kikuchi98/dbt-handson.git';
```

> **注意**: リポジトリ URL は実際の URL に置き換えてください。

**確認コマンド:**

```sql
-- リポジトリ一覧の確認
SHOW GIT REPOSITORIES IN SCHEMA DBT_PROJECT_DB.INTEGRATIONS;

-- リポジトリの最新をフェッチ
ALTER GIT REPOSITORY DBT_PROJECT_DB.INTEGRATIONS.dbt_handson_repo FETCH;
```

---

## 3-2. Workspace の作成（Snowsight GUI）

### 操作手順

1. Snowsight にログイン
2. 左メニュー → **Projects** → **Workspaces**
3. 右上の **「+ Create Workspace」** → **「From Git repository」** を選択
4. 以下を入力:

| 項目 | 値 |
|---|---|
| Workspace name | `dbt_handson_workspace` |
| Git repository | `DBT_PROJECT_DB.INTEGRATIONS.dbt_handson_repo` |
| Branch | `main` |
| Subdirectory | `dbt_handson_project` |
| Database | `DBT_PROJECT_DB` |
| Schema | `DEV` |

5. **「Create」** をクリック

> **ポイント**: `Subdirectory` は dbt プロジェクトが格納されているディレクトリを指定する。リポジトリルートに `dbt_project.yml` がある場合は空欄でよいが、今回はサブディレクトリ `dbt_handson_project` に格納されているため指定が必要。

---

## 3-3. Workspace 内での dbt deps 実行

Workspace が開いたら、左側にファイルツリーが表示される。

### 操作手順

1. 画面下部のターミナル（またはコマンドパレット）で以下を実行:

```
dbt deps
```

**期待される結果:**
```
Installing dbt-labs/dbt_utils
  Installed from version 1.3.0
  Updated version available: x.x.x

Installing calogica/dbt_expectations
  Installed from version 0.10.x
  ...

Installing calogica/dbt_date
  Installed from version x.x.x
  ...
```

### トラブルシューティング

| エラー | 原因 | 対処法 |
|---|---|---|
| ネットワークエラー | External Access Integration 未設定 | Workspace 設定で `dbt_ext_access` を紐づける |
| パッケージバージョンエラー | dbt 1.9 との互換性 | `packages.yml` のバージョン制約を確認・調整 |

---

## 3-4. dbt compile で DAG を確認

```
dbt compile
```

### 確認ポイント

- コンパイルがエラーなく完了すること
- Workspace 上で **DAG がグラフィカルに表示**されること
- ソース → ステージング → 中間 → マートの依存関係が正しいこと
- 各モデルをクリックするとコンパイル済み SQL が確認できること

---

## 3-5. dbt run で dev 環境にモデルを構築

```
dbt run --target dev
```

### 期待される結果

`DBT_PROJECT_DB.DEV` スキーマに以下のオブジェクトが作成される:

| オブジェクト | 種類 | 説明 |
|---|---|---|
| `STG_JAFFLE_SHOP__CUSTOMERS` | view | 顧客ステージング |
| `STG_JAFFLE_SHOP__ORDERS` | view | 注文ステージング |
| `STG_JAFFLE_SHOP__PAYMENTS` | view | 支払いステージング |
| `FCT_ORDERS` | table | 注文ファクト |
| `FCT_ORDERS_DAILY` | table (incremental) | 日次注文ファクト |
| `DIM_CUSTOMERS` | table | 顧客ディメンション |

> `int_orders_joined` は ephemeral マテリアライゼーションのため、DB上にオブジェクトは作成されない。

### 確認コマンド（Snowflake ワークシート）

```sql
USE SCHEMA DBT_PROJECT_DB.DEV;
SHOW TABLES;
SHOW VIEWS;

-- データの確認
SELECT * FROM DBT_PROJECT_DB.DEV.FCT_ORDERS LIMIT 10;
SELECT * FROM DBT_PROJECT_DB.DEV.DIM_CUSTOMERS LIMIT 10;
SELECT COUNT(*) AS row_count FROM DBT_PROJECT_DB.DEV.FCT_ORDERS;
```

---

## 3-6. dbt test でテスト実行

```
dbt test --target dev
```

### 期待される結果

すべてのテストがパスすること:
- ジェネリックテスト（unique, not_null, accepted_values, relationships）
- シングラーテスト（`assert_fct_orders_amount_is_positive`）
- ユニットテスト（`test_fct_orders_amount_conversion`）

---

## 3-7. dbt build で一括実行

```
dbt build --target dev
```

### 実行順序

1. **seed**: `payment_method_mapping` のロード
2. **ユニットテスト**: `test_fct_orders_amount_conversion` の実行
3. **モデル実行**: DAG 順にモデルをビルド
4. **スナップショット**: `snp_jaffle_shop__customers` の実行
5. **データテスト**: ジェネリック・シングラーテストの実行

---

## 3-8. コード編集と Git 操作（Workspace 上）

Workspace では以下の Git 操作が可能:

| 操作 | 方法 |
|---|---|
| ファイル編集 | エディタで直接編集 |
| 変更の diff 確認 | Git パネルで変更を確認 |
| コミット | Git パネルからコミットメッセージを入力してコミット |
| プッシュ | コミット後にプッシュ（プライベートリポのみ） |
| ブランチ切り替え | Git パネルでブランチを選択 |

> **注意**: パブリックリポジトリの場合、プッシュは非対応。

---

## 確認チェックリスト

- [ ] Git リポジトリオブジェクトが作成されている
- [ ] Workspace が Snowsight 上に作成されている
- [ ] `dbt deps` でパッケージがインストールできた
- [ ] `dbt compile` でエラーなくコンパイルでき、DAG が表示された
- [ ] `dbt run --target dev` で DEV スキーマにオブジェクトが作成された
- [ ] `dbt test` でテストが通った
- [ ] `dbt build` で一括実行が成功した
