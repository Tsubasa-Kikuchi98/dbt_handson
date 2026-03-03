# Step 4: モデルの階層設計（staging / intermediate / mart）

## 目的

モデルを3層構造（staging → intermediate → mart）で設計し、再利用性とメンテナンス性の高いプロジェクト構成を作る。

---

## 前提条件

- Step 3 が完了していること（ソース定義が作成済み）

---

## 4-1. 3層構造の考え方

| 層 | 命名規則 | マテリアライゼーション | 役割 |
|---|---|---|---|
| **staging** | `stg_<source>__<table>` | view | ソースデータの軽い変換（リネーム、型変換） |
| **intermediate** | `int_<entity>_<verb>` | ephemeral / view | ビジネスロジックの中間処理（結合、集約） |
| **mart** | `fct_` / `dim_` | table / incremental | 最終的な分析用テーブル |

### なぜ3層にするのか

- **staging**: ソースの変更を吸収する緩衝層。全モデルの起点
- **intermediate**: 複雑なロジックを分割して理解しやすくする
- **mart**: BI ツールやアナリストが直接参照するテーブル

---

## 4-2. ディレクトリ構成の作成

```bash
cd /c/Users/tsuba/dbt_handson/dbt_handson_project

# ディレクトリの作成
mkdir -p models/staging/jaffle_shop
mkdir -p models/intermediate
mkdir -p models/marts
```

最終的な構成:

```
models/
├── staging/
│   └── jaffle_shop/
│       ├── _jaffle_shop__sources.yml       # ソース定義（Step 3 で作成済み）
│       ├── _jaffle_shop__models.yml        # staging モデルの schema
│       ├── stg_jaffle_shop__customers.sql
│       ├── stg_jaffle_shop__orders.sql
│       └── stg_jaffle_shop__payments.sql
├── intermediate/
│   ├── _int__models.yml
│   └── int_orders_joined.sql
└── marts/
    ├── _mart__models.yml
    ├── fct_orders.sql
    └── dim_customers.sql
```

---

## 4-3. Staging モデルの作成

### stg_jaffle_shop__customers.sql

**ファイル**: `models/staging/jaffle_shop/stg_jaffle_shop__customers.sql`

```sql
with source as (

    select * from {{ source('jaffle_shop', 'customers') }}

),

renamed as (

    select
        id as customer_id,
        first_name,
        last_name

    from source

)

select * from renamed
```

### stg_jaffle_shop__orders.sql

**ファイル**: `models/staging/jaffle_shop/stg_jaffle_shop__orders.sql`

```sql
with source as (

    select * from {{ source('jaffle_shop', 'orders') }}

),

renamed as (

    select
        id as order_id,
        user_id as customer_id,
        order_date,
        status

    from source

)

select * from renamed
```

### stg_jaffle_shop__payments.sql

**ファイル**: `models/staging/jaffle_shop/stg_jaffle_shop__payments.sql`

```sql
with source as (

    select * from {{ source('jaffle_shop', 'payments') }}

),

renamed as (

    select
        id as payment_id,
        order_id,
        payment_method,
        amount as amount_cents

    from source

)

select * from renamed
```

### Staging モデルのポイント

- `source()` 関数でソースを参照
- カラム名のリネーム（`id` → `customer_id` など）
- 型変換が必要な場合はここで行う
- ビジネスロジックは含めない（軽い変換のみ）

---

## 4-4. Staging モデルの schema.yml

**ファイル**: `models/staging/jaffle_shop/_jaffle_shop__models.yml`

```yaml
version: 2

models:
  - name: stg_jaffle_shop__customers
    description: "顧客マスタの staging モデル。カラム名を統一。"
    columns:
      - name: customer_id
        description: "顧客の一意識別子"
        data_tests:
          - unique
          - not_null

  - name: stg_jaffle_shop__orders
    description: "注文データの staging モデル。カラム名を統一。"
    columns:
      - name: order_id
        description: "注文の一意識別子"
        data_tests:
          - unique
          - not_null
      - name: customer_id
        description: "注文した顧客のID"
        data_tests:
          - not_null

  - name: stg_jaffle_shop__payments
    description: "支払データの staging モデル。カラム名を統一、金額はセント単位。"
    columns:
      - name: payment_id
        description: "支払の一意識別子"
        data_tests:
          - unique
          - not_null
```

---

## 4-5. Intermediate モデルの作成

**ファイル**: `models/intermediate/int_orders_joined.sql`

```sql
{{
    config(
        materialized='ephemeral'
    )
}}

with orders as (

    select * from {{ ref('stg_jaffle_shop__orders') }}

),

payments as (

    select * from {{ ref('stg_jaffle_shop__payments') }}

),

orders_with_payments as (

    select
        orders.order_id,
        orders.customer_id,
        orders.order_date,
        orders.status,
        payments.payment_method,
        payments.amount_cents

    from orders
    left join payments on orders.order_id = payments.order_id

)

select * from orders_with_payments
```

### Intermediate モデルの schema.yml

**ファイル**: `models/intermediate/_int__models.yml`

```yaml
version: 2

models:
  - name: int_orders_joined
    description: "注文と支払を結合した中間モデル。"
    columns:
      - name: order_id
        description: "注文の一意識別子"
      - name: customer_id
        description: "顧客ID"
```

### ephemeral の動作

- DB 上にテーブル/ビューは作成されない
- 下流モデルの SQL 内で **CTE（Common Table Expression）** として展開される
- 用途: 軽量な中間処理、1-2 の下流モデルのみが参照する場合

---

## 4-6. Mart モデルの作成

### fct_orders.sql（ファクトテーブル）

**ファイル**: `models/marts/fct_orders.sql`

```sql
{{
    config(
        materialized='table'
    )
}}

with orders_joined as (
    select * from {{ ref('int_orders_joined') }}
),

final as (
    select
        order_id,
        customer_id,
        order_date,
        status,
        payment_method,
        amount_cents / 100.0 as amount
    from orders_joined
)

select * from final
```

### dim_customers.sql（ディメンションテーブル）

**ファイル**: `models/marts/dim_customers.sql`

```sql
{{
    config(
        materialized='table'
    )
}}

with customers as (

    select * from {{ ref('stg_jaffle_shop__customers') }}

),

orders as (

    select * from {{ ref('int_orders_joined') }}

),

customer_orders as (

    select
        customer_id,
        min(order_date) as first_order_date,
        max(order_date) as most_recent_order_date,
        count(order_id) as number_of_orders,
        sum(amount_cents) / 100.0 as lifetime_value

    from orders
    group by customer_id

),

final as (

    select
        customers.customer_id,
        customers.first_name,
        customers.last_name,
        customer_orders.first_order_date,
        customer_orders.most_recent_order_date,
        coalesce(customer_orders.number_of_orders, 0) as number_of_orders,
        coalesce(customer_orders.lifetime_value, 0) as lifetime_value

    from customers
    left join customer_orders using (customer_id)

)

select * from final
```

### Mart モデルの schema.yml

**ファイル**: `models/marts/_mart__models.yml`

```yaml
version: 2

models:
  - name: fct_orders
    description: "注文ファクトテーブル。1行 = 1注文。"
    columns:
      - name: order_id
        description: "注文の一意識別子"
        data_tests:
          - unique
          - not_null
      - name: customer_id
        description: "顧客ID"
        data_tests:
          - not_null
          - relationships:
              to: ref('dim_customers')
              field: customer_id
      - name: amount
        description: "支払金額（ドル）"
        data_tests:
          - not_null:
              config:
                severity: warn

  - name: dim_customers
    description: "顧客ディメンションテーブル。属性と注文の集約値を含む。"
    columns:
      - name: customer_id
        description: "顧客の一意識別子"
        data_tests:
          - unique
          - not_null
      - name: number_of_orders
        description: "累計注文回数"
      - name: lifetime_value
        description: "累計支払額（ドル）"
```

---

## 4-7. 全モデルのビルドと確認

```bash
dbt run
```

### 期待される出力

```
1 of 5 OK created sql view model PUBLIC.STG_JAFFLE_SHOP__CUSTOMERS ... [SUCCESS]
2 of 5 OK created sql view model PUBLIC.STG_JAFFLE_SHOP__ORDERS ...... [SUCCESS]
3 of 5 OK created sql view model PUBLIC.STG_JAFFLE_SHOP__PAYMENTS .... [SUCCESS]
4 of 5 OK created sql table model PUBLIC.FCT_ORDERS .................. [SUCCESS]
5 of 5 OK created sql table model PUBLIC.DIM_CUSTOMERS ............... [SUCCESS]
```

> `int_orders_joined` は ephemeral のためリストに表示されない。

### データ確認（Snowflake ワークシート）

```sql
SELECT * FROM DATALAKE_DB.PUBLIC.FCT_ORDERS LIMIT 10;
SELECT * FROM DATALAKE_DB.PUBLIC.DIM_CUSTOMERS LIMIT 10;

-- DAG の確認: fct_orders が何行あるか
SELECT COUNT(*) FROM DATALAKE_DB.PUBLIC.FCT_ORDERS;
```

---

## 4-8. グループとアクセス制御（参考）

### グループの定義

```yaml
groups:
  - name: analytics
    owner:
      name: Analytics Team
      email: analytics@example.com
```

### アクセス修飾子

| 修飾子 | 説明 |
|---|---|
| `public` | どこからでも参照可能 |
| `protected`（デフォルト） | 同プロジェクト内から参照可能 |
| `private` | 同グループ内のみ参照可能 |

```yaml
models:
  - name: fct_orders
    access: public
    group: analytics
```

---

## 4-9. モデルコントラクト（参考）

```yaml
models:
  - name: fct_orders
    config:
      contract:
        enforced: true
    columns:
      - name: order_id
        data_type: number
      - name: customer_id
        data_type: number
      - name: amount
        data_type: number(16, 2)
```

- `contract: {enforced: true}` でスキーマを強制
- カラム名・データ型の一致を検証（不一致はコンパイルエラー）
- 対応マテリアライゼーション: `table`, `view`, `incremental`

---

## 確認チェックリスト

- [ ] 3層構造（staging / intermediate / mart）の役割を理解した
- [ ] staging モデル 3 つを作成した
- [ ] intermediate モデル（ephemeral）を作成した
- [ ] mart モデル（fct_orders, dim_customers）を作成した
- [ ] 各層の schema.yml を作成した
- [ ] `dbt run` で全モデルが正常にビルドされた
- [ ] Snowflake でデータが確認できた
