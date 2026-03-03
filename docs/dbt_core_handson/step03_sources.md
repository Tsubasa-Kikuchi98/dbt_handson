# Step 3: ソースの定義

## 目的

EL ツールでウェアハウスにロード済みのテーブルを「ソース」として定義し、`source()` 関数でモデルから参照する。ソースの鮮度チェックも学ぶ。

---

## 前提条件

- Step 2 が完了していること
- Snowflake に `JAFFLE_SHOP_RAW.JAFFLE_SHOP` スキーマと以下のテーブルが存在すること:
  - `CUSTOMERS`
  - `ORDERS`
  - `PAYMENTS`

---

## 3-1. ソースとは

- EL ツール（Fivetran, Airbyte 等）によってウェアハウスにロード済みのデータを定義するもの
- YAML ファイルの `sources:` キーで記述する
- dbt が管理する「モデル」とは異なり、dbt が作成するのではなく外部で用意されたデータ

### メリット

- テーブルのフルパス（`database.schema.table`）をハードコードせずに参照できる
- DAG 上でリネージが可視化される
- 鮮度チェック（freshness）ができる
- ソースに対してテストが書ける

---

## 3-2. ソース定義ファイルの作成

**ファイル**: `models/staging/jaffle_shop/_jaffle_shop__sources.yml`

> ファイル名の慣習: `_<source_name>__sources.yml`（先頭 `_` でソート順を上に）

```yaml
version: 2

sources:
  - name: jaffle_shop
    description: "Jaffle Shop のソースデータ（ELツールでロード済みを想定）"
    database: JAFFLE_SHOP_RAW
    schema: JAFFLE_SHOP

    tables:
      - name: customers
        description: "顧客マスタ"
        columns:
          - name: id
            description: "顧客の一意識別子"
            data_tests:
              - unique
              - not_null

      - name: orders
        description: "注文データ"
        loaded_at_field: "_etl_loaded_at"
        freshness:
          warn_after: {count: 12, period: hour}
          error_after: {count: 24, period: hour}
        columns:
          - name: id
            description: "注文の一意識別子"
            data_tests:
              - unique
              - not_null
          - name: user_id
            description: "注文した顧客のID"
            data_tests:
              - not_null
              - relationships:
                  to: source('jaffle_shop', 'customers')
                  field: id
          - name: status
            description: "注文ステータス"
            data_tests:
              - accepted_values:
                  values: ['completed', 'returned', 'return_pending', 'placed', 'shipped']

      - name: payments
        description: "支払データ（金額はセント単位）"
        columns:
          - name: id
            description: "支払の一意識別子"
            data_tests:
              - unique
              - not_null
          - name: order_id
            description: "対応する注文のID"
            data_tests:
              - not_null
              - relationships:
                  to: source('jaffle_shop', 'orders')
                  field: id
          - name: payment_method
            description: "支払方法"
            data_tests:
              - accepted_values:
                  values: ['credit_card', 'coupon', 'bank_transfer', 'gift_card']
```

---

## 3-3. source() 関数

### 基本構文

```sql
{{ source('source_name', 'table_name') }}
```

### 使用例

```sql
-- Before: ハードコード
select * from JAFFLE_SHOP_RAW.JAFFLE_SHOP.CUSTOMERS

-- After: source() を使用
select * from {{ source('jaffle_shop', 'customers') }}
```

### コンパイル結果

```sql
select * from JAFFLE_SHOP_RAW.JAFFLE_SHOP.CUSTOMERS
```

dbt が `database` + `schema` + `table name` をフルパスに自動解決する。

---

## 3-4. ソースの設定項目

| 項目 | 説明 |
|---|---|
| `name` | ソース識別子（`source()` の第1引数で使用） |
| `database` | データベース名 |
| `schema` | スキーマ名（省略時は `name` がスキーマ名になる） |
| `tables` | テーブルのリスト |
| `identifier` | 実際のテーブル名がソース定義名と異なる場合のマッピング |
| `quoting` | 識別子のクオート設定（Snowflake の大文字小文字区別に重要） |
| `description` | ドキュメント記述 |
| `columns` | カラムレベルのドキュメント・テスト |

### identifier の使用例

実際のテーブル名が `RAW_CUSTOMERS` だが、dbt 上では `customers` として参照したい場合:

```yaml
tables:
  - name: customers
    identifier: RAW_CUSTOMERS
```

---

## 3-5. Source Freshness（鮮度チェック）

ソースデータがどれだけ新しいかをチェックする機能。

### 設定

```yaml
tables:
  - name: orders
    loaded_at_field: "_etl_loaded_at"  # データロード時刻のカラム
    freshness:
      warn_after: {count: 12, period: hour}   # 12時間以上古いと警告
      error_after: {count: 24, period: hour}  # 24時間以上古いとエラー
```

### 実行

```bash
dbt source freshness
```

### 期待される出力

```
Running with dbt=1.11.5
Found 3 sources, ...

1 of 1 WARN freshness of jaffle_shop.orders ........ [WARN in 1.23s]

Done.
```

### 結果ファイル

結果は `target/sources.json` に出力される。

> **注意**: `loaded_at_field` が設定されているテーブルのみ鮮度チェックの対象になる。

---

## 3-6. ソースの選択実行

```bash
# ソースに定義されたテストのみ実行
dbt test --select source:jaffle_shop

# ソースの下流モデルを実行（+ は下流を意味する）
dbt run --select source:jaffle_shop+

# 鮮度チェックOKのソースの下流のみ実行
dbt build --select source_status:fresher+
```

---

## 確認チェックリスト

- [ ] ソース定義ファイル（`_jaffle_shop__sources.yml`）を作成した
- [ ] `source()` 関数の構文と動作を理解した
- [ ] `database`, `schema`, `tables` の設定を理解した
- [ ] `dbt source freshness` で鮮度チェックを実行した
- [ ] ソースに対するテスト（unique, not_null, relationships, accepted_values）を定義した
