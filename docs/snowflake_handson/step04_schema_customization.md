# Step 4: スキーマ生成のカスタマイズ

## 目的

dev / prod 環境でスキーマ名が適切に解決されるよう `generate_schema_name` マクロをカスタマイズする。

---

## 前提条件

- Step 3 が完了していること（Workspace が動作し、dev 環境でモデルが実行できること）

---

## 4-1. デフォルトの動作を理解する

dbt のデフォルトでは、モデルに `schema` 設定（カスタムスキーマ）を指定した場合:

```
結果のスキーマ名 = target.schema + "_" + custom_schema_name
```

### 具体例

| ターゲット | custom_schema | 結果のスキーマ |
|---|---|---|
| dev (`schema: DEV`) | なし | `DEV` |
| dev (`schema: DEV`) | `marts` | `DEV_marts` |
| prod (`schema: PROD`) | なし | `PROD` |
| prod (`schema: PROD`) | `marts` | `PROD_marts` |

### 問題点

- prod 環境では `PROD_marts` ではなく、単に `marts` というスキーマ名にしたい
- dev 環境では開発者同士の衝突を防ぐためプレフィックス付きでよい

---

## 4-2. generate_schema_name マクロの作成

**ファイル**: `dbt_handson_project/macros/generate_schema_name.sql`

以下の内容で作成する:

```sql
{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}

    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ default_schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}

{%- endmacro %}
```

### マクロのロジック

```
custom_schema が未指定の場合:
  → target.schema をそのまま使う（DEV or PROD）

custom_schema が指定されていて、prod ターゲットの場合:
  → custom_schema_name をそのまま使う（例: "marts"）

custom_schema が指定されていて、dev ターゲットの場合:
  → target.schema + "_" + custom_schema_name（例: "DEV_marts"）
```

### 結果のスキーマ名

| 環境 | custom_schema 指定あり | custom_schema 指定なし |
|---|---|---|
| dev | `DEV_<custom_schema>` | `DEV` |
| prod | `<custom_schema>` | `PROD` |

---

## 4-3. prod 用スキーマの事前作成

prod 環境でカスタムスキーマを使う場合、スキーマは **事前に作成** しておく必要がある（dbt は自動作成しない場合がある）。

**実行場所**: Snowflake ワークシート（ロール: `ACCOUNTADMIN`）

```sql
-- ============================================================
-- Step 4-3: prod 用スキーマの事前作成
-- ============================================================

-- 現在のプロジェクトではカスタムスキーマは snapshots のみ
-- 将来的に staging / marts などを分ける場合に備えて作成
CREATE SCHEMA IF NOT EXISTS DBT_PROJECT_DB.STAGING;
CREATE SCHEMA IF NOT EXISTS DBT_PROJECT_DB.INTERMEDIATE;
CREATE SCHEMA IF NOT EXISTS DBT_PROJECT_DB.MARTS;
CREATE SCHEMA IF NOT EXISTS DBT_PROJECT_DB.SNAPSHOTS;
```

> **現時点のプロジェクト**: `schema` 設定を使っているのはスナップショット（`snapshots` スキーマ）のみ。他のモデルは `schema` を未指定なので `DEV` / `PROD` スキーマ直下に作成される。

---

## 4-4. 変更をコミット・プッシュ

**実行場所**: ローカルターミナル

```bash
cd /c/Users/tsuba/dbt_handson
git add dbt_handson_project/macros/generate_schema_name.sql
git commit -m "Add generate_schema_name macro for prod schema resolution"
git push origin main
```

---

## 4-5. 動作確認

### Workspace で確認

1. Workspace で Git の最新を取得（Fetch / Pull）
2. コンパイルして確認:

```
dbt compile --target dev
```

3. `target/compiled/` 内のモデル SQL を確認し、スキーマが正しく解決されていることを確認する

### ローカルでの確認（任意）

```bash
cd /c/Users/tsuba/dbt_handson/dbt_handson_project

# dev ターゲットでコンパイル
dbt compile --target dev

# コンパイル結果の確認（例: fct_orders）
cat target/compiled/dbt_handson_project/models/marts/fct_orders.sql
```

スキーマ名が `DEV` になっていることを確認する。

---

## 確認チェックリスト

- [ ] `generate_schema_name` マクロが `macros/` に作成されている
- [ ] prod 用スキーマ（STAGING, INTERMEDIATE, MARTS, SNAPSHOTS）が事前に作成されている
- [ ] dev ターゲットでコンパイルすると `DEV` スキーマが使われる
- [ ] prod ターゲットでコンパイルすると custom_schema がそのまま使われる
- [ ] 変更が GitHub にプッシュされている
