# Step 5: テスト

## 目的

データの品質を保証するために、ジェネリックテスト・シングラーテスト・ユニットテストの3種類のテストを学ぶ。

---

## 前提条件

- Step 4 が完了していること（3層モデルがビルド済み）

---

## 5-1. データテスト（Generic Tests）

schema.yml の `data_tests:` キーで定義する、パラメータ化されたテスト。

### 組み込みジェネリックテスト

| テスト | 説明 | 例 |
|---|---|---|
| `unique` | 重複なし | 主キーカラムに適用 |
| `not_null` | NULL なし | 必須カラムに適用 |
| `accepted_values` | 許容値リスト | ステータスカラムなど |
| `relationships` | 参照整合性 | 外部キーの参照先が存在するか |

### 定義例（schema.yml）

```yaml
version: 2

models:
  - name: fct_orders
    columns:
      - name: order_id
        data_tests:
          - unique
          - not_null
      - name: customer_id
        data_tests:
          - not_null
          - relationships:
              to: ref('dim_customers')
              field: customer_id
      - name: amount
        data_tests:
          - not_null:
              config:
                severity: warn
```

### ソースに対するテスト

ソース定義にも同様にテストを書ける（Step 3 の `_jaffle_shop__sources.yml` で既に定義済み）:

```yaml
sources:
  - name: jaffle_shop
    tables:
      - name: orders
        columns:
          - name: status
            data_tests:
              - accepted_values:
                  values: ['completed', 'returned', 'return_pending', 'placed', 'shipped']
```

---

## 5-2. Singular テスト

`tests/` ディレクトリに `.sql` ファイルを作成する、1回限りのカスタムテスト。

### ルール

- **失敗レコードを返す SELECT 文**を書く
- **0行 = テスト成功**、1行以上 = テスト失敗
- パラメータ化なし（特定のモデルに固有のアサーション）

### 作成例

**ファイル**: `tests/assert_fct_orders_amount_is_positive.sql`

```sql
-- fct_orders の amount が負でないことを検証する
-- 失敗行（負の金額の注文）が返されたらテスト失敗
{{
    config(
        severity='warn',
        warn_if='>0',
        error_if='>10',
        store_failures=true
    )
}}
select
    order_id,
    amount
from {{ ref('fct_orders') }}
where amount < 0
```

---

## 5-3. テストの設定オプション

### config で指定できる設定

| 設定 | 説明 | 例 |
|---|---|---|
| `severity` | `warn` または `error` | `severity: warn` |
| `warn_if` | 警告の閾値（失敗行数） | `warn_if: '>0'` |
| `error_if` | エラーの閾値（失敗行数） | `error_if: '>10'` |
| `where` | テスト対象のフィルタ条件 | `where: "status != 'cancelled'"` |
| `limit` | 返却行数の上限 | `limit: 100` |
| `store_failures` | 失敗レコードをテーブルに保存 | `store_failures: true` |
| `store_failures_as` | 保存形式 | `store_failures_as: table` |
| `tags` | テストのタグ付け | `tags: ['nightly']` |

### store_failures の動作

`store_failures: true` を設定すると、テスト失敗時に `dbt_test__audit` スキーマにテーブルが作成され、失敗レコードが保存される。

```sql
-- 失敗レコードの確認
SELECT * FROM DATALAKE_DB.dbt_test__audit.assert_fct_orders_amount_is_positive;
```

### schema.yml でのテスト設定

```yaml
columns:
  - name: amount
    data_tests:
      - not_null:
          config:
            severity: warn
            where: "status = 'completed'"
```

---

## 5-4. テストの実行

```bash
# 全テスト実行
dbt test

# 特定モデルのテストのみ
dbt test --select fct_orders

# データテストのみ
dbt test --select test_type:data

# ユニットテストのみ
dbt test --select test_type:unit

# ソースのテスト
dbt test --select source:jaffle_shop

# タグ指定
dbt test --select tag:nightly
```

### 期待される出力

```
Running with dbt=1.11.5
Found X tests, ...

1 of N PASS unique_fct_orders_order_id .................. [PASS in 0.87s]
2 of N PASS not_null_fct_orders_order_id ................ [PASS in 0.65s]
3 of N PASS not_null_fct_orders_customer_id ............. [PASS in 0.72s]
4 of N WARN not_null_fct_orders_amount .................. [WARN in 0.68s]
5 of N PASS relationships_fct_orders_customer_id ....... [PASS in 1.12s]
...

Finished running N tests in X.XX seconds.
Done. PASS=N WARN=M ERROR=0 SKIP=0 TOTAL=N
```

---

## 5-5. ユニットテスト (v1.8+)

SQL モデルのロジックを**静的データ**で検証する。ウェアハウスのデータに依存しない。

### 定義場所

schema.yml に `unit_tests:` キーで定義する。

### 作成例

**ファイル**: `models/marts/_mart__models.yml` に追記

```yaml
unit_tests:
  - name: test_fct_orders_amount_conversion
    description: "セントからドルへの変換ロジックを検証"
    model: fct_orders
    given:
      - input: ref('int_orders_joined')
        format: sql
        rows: |
          select 1 as order_id, 10 as customer_id, '2024-01-01'::date as order_date, 'completed' as status, 'credit_card' as payment_method, 1500 as amount_cents
          union all
          select 2 as order_id, 20 as customer_id, '2024-01-02'::date as order_date, 'placed' as status, 'coupon' as payment_method, 0 as amount_cents
    expect:
      rows:
        - {order_id: 1, customer_id: 10, order_date: "2024-01-01", status: "completed", payment_method: "credit_card", amount: 15.0}
        - {order_id: 2, customer_id: 20, order_date: "2024-01-02", status: "placed", payment_method: "coupon", amount: 0.0}
```

### ユニットテストの構成要素

| 要素 | 説明 |
|---|---|
| `name` | テスト名 |
| `description` | テストの説明 |
| `model` | テスト対象のモデル |
| `given` | 入力データの定義（`ref()` や `source()` の代わりにモックデータを指定） |
| `expect` | 期待される出力 |

### 入力データの形式

| 形式 | `format` | 説明 |
|---|---|---|
| dict（辞書） | なし（デフォルト） | YAML の辞書形式で行を定義 |
| SQL | `sql` | SELECT 文で行を定義 |
| CSV | `csv` | CSV 形式で行を定義 |

### ユニットテストの実行

```bash
# ユニットテストのみ実行
dbt test --select test_type:unit

# 特定のユニットテスト
dbt test --select test_fct_orders_amount_conversion
```

### dbt build での実行順序

```
ユニットテスト → モデル実行 → データテスト
```

ユニットテストが失敗するとモデル実行がスキップされる。

### 制限事項

- SQL モデルのみ対応（Python モデルは非対応）
- 同プロジェクト内のモデルのみ
- `materialized_view` は非対応

---

## 5-6. パッケージ提供テスト（参考）

`dbt-utils` や `dbt-expectations` が提供するテスト（Step 10 でパッケージをインストール後に使用可能）:

```yaml
columns:
  - name: order_id
    data_tests:
      - dbt_utils.not_constant
      - dbt_expectations.expect_column_values_to_be_increasing
```

---

## 確認チェックリスト

- [ ] 4種類の組み込みジェネリックテスト（unique, not_null, accepted_values, relationships）を定義した
- [ ] singular テスト（`assert_fct_orders_amount_is_positive.sql`）を作成した
- [ ] テストの設定オプション（severity, store_failures 等）を理解した
- [ ] `dbt test` で全テストが実行できた
- [ ] ユニットテスト（`test_fct_orders_amount_conversion`）を作成した
- [ ] `dbt test --select test_type:unit` でユニットテストが実行できた
- [ ] `dbt build` でのテスト実行順序（ユニット → モデル → データテスト）を理解した
