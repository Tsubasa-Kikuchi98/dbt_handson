# Step 8: Jinja とマクロ

## 目的

Jinja テンプレート構文を使って動的な SQL を書く方法と、再利用可能なマクロの作成・使用方法を学ぶ。

---

## 前提条件

- Step 7 が完了していること

---

## 8-1. Jinja テンプレート構文

| 構文 | 用途 | 例 |
|---|---|---|
| `{{ ... }}` | 式の出力（結果が SQL に埋め込まれる） | `{{ ref('model') }}` |
| `{% ... %}` | 制御文（出力しない） | `{% if ... %}` |
| `{# ... #}` | コメント（コンパイル結果に含まれない） | `{# memo #}` |

### 変数代入

```sql
{% set my_variable = 'some_value' %}
{% set payment_methods = ['credit_card', 'coupon', 'bank_transfer', 'gift_card'] %}
```

### for ループ

```sql
{% for method in payment_methods %}
    sum(case when payment_method = '{{ method }}' then amount else 0 end) as {{ method }}_amount
    {% if not loop.last %},{% endif %}
{% endfor %}
```

### if 文

```sql
{% if target.name == 'prod' %}
    -- prod 環境のみの処理
{% elif target.name == 'dev' %}
    -- dev 環境のみの処理
{% else %}
    -- その他
{% endif %}
```

### ホワイトスペース制御

```sql
{{- value -}}    {# 前後の空白を除去 #}
{%- if ... -%}   {# 制御文の前後の空白を除去 #}
```

---

## 8-2. 実践例: Jinja による動的 SQL

**ファイル**: `analyses/jinja_practice.sql`

```sql
{# 変数代入 #}
{% set payment_methods = ['credit_card', 'coupon', 'bank_transfer', 'gift_card'] %}

select
    order_id,
    {# for ループでカラムを動的生成 #}
    {% for method in payment_methods %}
        sum(case when payment_method = '{{ method }}' then amount else 0 end)
            as {{ method }}_amount
        {% if not loop.last %},{% endif %}
    {% endfor %}
from {{ ref('fct_orders') }}
group by order_id
```

### コンパイル結果の確認

```bash
dbt compile
```

コンパイル結果: `target/compiled/dbt_handson_project/analyses/jinja_practice.sql`

```sql
select
    order_id,
    sum(case when payment_method = 'credit_card' then amount else 0 end) as credit_card_amount,
    sum(case when payment_method = 'coupon' then amount else 0 end) as coupon_amount,
    sum(case when payment_method = 'bank_transfer' then amount else 0 end) as bank_transfer_amount,
    sum(case when payment_method = 'gift_card' then amount else 0 end) as gift_card_amount
from DATALAKE_DB.PUBLIC.FCT_ORDERS
group by order_id
```

---

## 8-3. マクロの定義と使用

### マクロの定義

**ファイル**: `macros/cents_to_dollars.sql`（例）

```sql
{% macro cents_to_dollars(column_name, scale=2) %}
    ({{ column_name }} / 100)::numeric(16, {{ scale }})
{% endmacro %}
```

### マクロの使用

```sql
select
    order_id,
    {{ cents_to_dollars('amount_cents') }} as amount
from {{ ref('stg_jaffle_shop__payments') }}
```

### コンパイル結果

```sql
select
    order_id,
    (amount_cents / 100)::numeric(16, 2) as amount
from ...
```

### ポイント

- `macros/` ディレクトリに `.sql` ファイルとして配置
- デフォルト引数をサポート（上記の `scale=2`）
- プロジェクト内のどこからでも呼び出し可能

---

## 8-4. 本プロジェクトのマクロ

**ファイル**: `macros/update_customer.sql`

```sql
{% macro update_customer() %}
    {% set sql %}
        update {{ source('jaffle_shop', 'customers') }}
        set last_name = 'Updated'
        where id = 1
    {% endset %}
    {{ run_query(sql) }}
    {{ log("Customer id=1 の last_name を 'Updated' に変更しました", info=true) }}
{% endmacro %}
```

### マクロで使える関数

| 関数 | 説明 |
|---|---|
| `run_query(sql)` | SQL を実行して結果を Agate テーブルとして取得 |
| `log(message, info=true)` | デバッグメッセージを出力 |
| `return(value)` | マクロから値を返す |

---

## 8-5. dbt 組み込みコンテキスト

モデルやマクロ内で使える組み込み関数・変数:

| 関数/変数 | 説明 | 例 |
|---|---|---|
| `ref()` | モデル参照 | `{{ ref('model') }}` |
| `source()` | ソース参照 | `{{ source('src', 'tbl') }}` |
| `config()` | モデル設定 | `{{ config(materialized='table') }}` |
| `var()` | プロジェクト変数の参照 | `{{ var('start_date') }}` |
| `env_var()` | 環境変数の参照 | `{{ env_var('DB_PASSWORD') }}` |
| `target` | 現在のターゲット情報 | `{{ target.name }}`, `{{ target.schema }}` |
| `this` | 現在のモデルのリレーション | `{{ this }}` |
| `log()` | デバッグ出力 | `{{ log('msg', info=true) }}` |
| `return()` | マクロから値を返す | `{{ return(result) }}` |
| `run_query()` | SQL を実行して結果取得 | `{{ run_query(sql) }}` |
| `adapter` | アダプター固有の機能 | `{{ adapter.get_columns_in_relation(this) }}` |

### var() の使い方

`dbt_project.yml` で定義:

```yaml
vars:
  start_date: '2024-01-01'
```

モデル内で使用:

```sql
where order_date >= '{{ var("start_date") }}'
```

コマンドラインでオーバーライド:

```bash
dbt run --vars '{start_date: "2023-01-01"}'
```

---

## 8-6. Operations

マクロをコマンドラインから直接実行する機能。

```bash
dbt run-operation update_customer
```

引数付き:

```bash
dbt run-operation my_macro --args '{key: value}'
```

> **注意**: Operation ではモデルのビルドは行われない。マクロ内で `run_query()` や `statement` ブロックを使って明示的に SQL を実行する必要がある。

---

## 8-7. Hooks

モデルのビルド前後や dbt コマンドの開始・終了時に自動実行される SQL。

| フック | タイミング |
|---|---|
| `pre-hook` | モデル/seed/snapshot のビルド前 |
| `post-hook` | モデル/seed/snapshot のビルド後 |
| `on-run-start` | dbt コマンド開始時 |
| `on-run-end` | dbt コマンド終了時 |

### モデル内で定義

```sql
{{ config(
    post_hook="GRANT SELECT ON {{ this }} TO ROLE ANALYST"
) }}
```

### dbt_project.yml で定義

```yaml
on-run-start:
  - "ALTER WAREHOUSE ADMIN_WH SET WAREHOUSE_SIZE = 'LARGE'"

on-run-end:
  - "ALTER WAREHOUSE ADMIN_WH SET WAREHOUSE_SIZE = 'XSMALL'"
```

### 用途例

- 権限管理（GRANT）
- ウェアハウスサイズの動的変更
- 監査ログの記録
- テーブルのクラスタリングキー設定

---

## 確認チェックリスト

- [ ] Jinja の3つの構文（`{{ }}`, `{% %}`, `{# #}`）を理解した
- [ ] for ループ、if 文、変数代入の書き方を理解した
- [ ] `analyses/jinja_practice.sql` を作成し、`dbt compile` で結果を確認した
- [ ] マクロの定義方法と使い方を理解した
- [ ] 組み込みコンテキスト（ref, source, var, target, this 等）を理解した
- [ ] `dbt run-operation` でマクロを直接実行できた
- [ ] Hooks（pre-hook, post-hook, on-run-start, on-run-end）の概念を理解した
