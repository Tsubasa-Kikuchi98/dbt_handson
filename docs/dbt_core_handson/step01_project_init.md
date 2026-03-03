# Step 1: プロジェクトの初期化

## 目的

dbt プロジェクトの雛形を生成し、Snowflake への接続設定を行い、正常に接続できることを確認する。

---

## 前提条件

- Python 3.12 がインストール済みであること
- `dbt-core` と `dbt-snowflake` がインストール済みであること
- Snowflake アカウントを持っていること

---

## 1-1. dbt init によるプロジェクト作成

**実行場所**: ローカルターミナル

```bash
cd /c/Users/tsuba/dbt_handson
dbt init dbt_handson_project
```

### 対話式プロンプト

以下の質問に答える:

| 質問 | 回答 |
|---|---|
| Which database would you like to use? | `snowflake` を選択 |
| account | `MYLMWWX-IFTC_DATADRESSER_REBUILD` |
| user | `KIKUCHI_TSUBASA` |
| authentication type | `password` を選択 |
| password | Snowflake のパスワード |
| role | `ACCOUNTADMIN` |
| warehouse | `ADMIN_WH` |
| database | `DATALAKE_DB` |
| schema | `PUBLIC` |
| threads | `1` |

### 生成される構造

```
dbt_handson_project/
├── dbt_project.yml          # プロジェクト設定
├── README.md                # プロジェクト説明
├── models/
│   └── example/             # サンプルモデル（後で削除）
│       ├── my_first_dbt_model.sql
│       └── my_second_dbt_model.sql
├── analyses/                # 分析用SQL
├── macros/                  # マクロ
├── seeds/                   # CSVデータ
├── snapshots/               # スナップショット
└── tests/                   # テスト
```

---

## 1-2. dbt_project.yml の理解

**ファイル**: `dbt_handson_project/dbt_project.yml`

```yaml
name: 'dbt_handson_project'
version: '1.0.0'

profile: 'dbt_handson_project'

model-paths: ["models"]
analysis-paths: ["analyses"]
test-paths: ["tests"]
seed-paths: ["seeds"]
macro-paths: ["macros"]
snapshot-paths: ["snapshots"]

clean-targets:
  - "target"
  - "dbt_packages"

models:
  dbt_handson_project:
    +materialized: view
```

### 主要な設定項目

| 項目 | 説明 | 設定値 |
|---|---|---|
| `name` | プロジェクト名（snake_case） | `dbt_handson_project` |
| `version` | プロジェクトバージョン | `1.0.0` |
| `profile` | 接続プロファイル名（profiles.yml の名前と一致） | `dbt_handson_project` |
| `model-paths` | モデルファイルの格納先 | `["models"]` |
| `analysis-paths` | 分析SQLの格納先 | `["analyses"]` |
| `test-paths` | singular テストの格納先 | `["tests"]` |
| `seed-paths` | CSV データの格納先 | `["seeds"]` |
| `macro-paths` | マクロの格納先 | `["macros"]` |
| `snapshot-paths` | スナップショットの格納先 | `["snapshots"]` |
| `clean-targets` | `dbt clean` で削除するディレクトリ | `target/`, `dbt_packages/` |
| `models` | モデルのデフォルト設定 | 全モデルを view でマテリアライズ |

---

## 1-3. ディレクトリ構成

| ディレクトリ | 役割 |
|---|---|
| `models/` | SQL/Python モデル、スキーマ定義（YAML） |
| `seeds/` | CSV データ（マスタテーブルなど） |
| `snapshots/` | SCD Type 2 スナップショット定義 |
| `tests/` | singular テスト（カスタム SQL テスト） |
| `macros/` | 再利用可能な Jinja マクロ |
| `analyses/` | 分析用 SQL（コンパイルのみ、実行されない） |
| `target/` | コンパイル・実行結果の出力先（Git 管理外） |
| `dbt_packages/` | インストールしたパッケージ（Git 管理外） |
| `logs/` | 実行ログ（Git 管理外） |

---

## 1-4. profiles.yml と接続設定

`dbt init` 実行時に `~/.dbt/profiles.yml` が自動生成される。

**ファイル**: `~/.dbt/profiles.yml`

```yaml
dbt_handson_project:
  outputs:
    dev:
      type: snowflake
      account: MYLMWWX-IFTC_DATADRESSER_REBUILD
      user: KIKUCHI_TSUBASA
      password: '<your_password>'
      role: ACCOUNTADMIN
      warehouse: ADMIN_WH
      database: DATALAKE_DB
      schema: PUBLIC
      threads: 1
  target: dev
```

### 主要な設定項目

| 項目 | 説明 |
|---|---|
| `type` | アダプター種別（`snowflake`） |
| `account` | Snowflake アカウント識別子 |
| `user` | ユーザー名 |
| `password` | パスワード（本番では `env_var` やキーペア認証を推奨） |
| `role` | 使用するロール |
| `warehouse` | 使用するウェアハウス |
| `database` | デフォルトデータベース |
| `schema` | デフォルトスキーマ |
| `threads` | 並列スレッド数 |
| `target` | デフォルトターゲット（`dev`） |

### ターゲットの使い分け

```yaml
dbt_handson_project:
  target: dev            # デフォルトターゲット
  outputs:
    dev:                 # 開発環境
      schema: DEV
      ...
    prod:                # 本番環境
      schema: PROD
      ...
```

- `dbt run` → dev ターゲットを使用
- `dbt run --target prod` → prod ターゲットを使用

---

## 1-5. 接続確認

```bash
cd /c/Users/tsuba/dbt_handson/dbt_handson_project
dbt debug
```

### 期待される出力

```
  dbt version: 1.11.5
  python version: 3.12.2
  ...
  Using profiles dir at ~/.dbt
  Using profiles.yml file at ~/.dbt/profiles.yml
  Using dbt_project.yml file at /path/to/dbt_handson_project/dbt_project.yml

Configuration:
  profiles.yml file [OK found and valid]
  dbt_project.yml file [OK found and valid]
  ...

Required dependencies:
  - git [OK found]

Connection:
  account: MYLMWWX-IFTC_DATADRESSER_REBUILD
  user: KIKUCHI_TSUBASA
  ...
  Connection test: [OK connection ok]

All checks passed!
```

### 確認ポイント

| 項目 | 期待される結果 |
|---|---|
| dbt version | `1.11.5` |
| profiles.yml | `OK found and valid` |
| dbt_project.yml | `OK found and valid` |
| Connection test | `OK connection ok` |

### トラブルシューティング

| エラー | 原因 | 対処法 |
|---|---|---|
| `profiles.yml file [ERROR not found]` | profiles.yml が見つからない | `~/.dbt/profiles.yml` の存在を確認 |
| `Connection test: [ERROR]` | 接続情報が不正 | account, user, password を確認 |
| `Warehouse not found` | ウェアハウスが存在しない | Snowflake でウェアハウス名を確認 |

---

## 1-6. サンプルモデルの削除

初期生成された `models/example/` は不要なので削除する:

```bash
rm -rf dbt_handson_project/models/example
```

---

## 確認チェックリスト

- [ ] `dbt init` でプロジェクトが生成されている
- [ ] `dbt_project.yml` の内容を理解した
- [ ] ディレクトリ構成を理解した
- [ ] `~/.dbt/profiles.yml` に接続情報が設定されている
- [ ] `dbt debug` で全チェックがパスした
- [ ] サンプルモデル（`models/example/`）を削除した
