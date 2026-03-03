# Step 7: インクリメンタルモデル

## 目的

大規模データに対して差分のみを処理するインクリメンタルモデルの仕組みと、microbatch 戦略を学ぶ。

---

## 前提条件

- Step 6 が完了していること

---

## 7-1. 基本概念

### なぜインクリメンタルが必要か

- **table** マテリアライゼーション: 毎回全データを再作成 → 大規模テーブルでは非効率
- **incremental**: 前回実行以降の新規・変更データのみを処理 → 高速・低コスト

### 適切な用途

| 適切 | 不適切 |
|---|---|
| 数百万〜数十億行のテーブル | 数千行の小さなテーブル |
| イベントデータ（ログ、トランザクション） | 頻繁に過去データが更新されるテーブル |
| コストの高い変換処理 | シンプルな変換 |

---

## 7-2. is_incremental() マクロ

増分実行かどうかを判定するマクロ。以下の**すべて**が TRUE のときに TRUE を返す:

1. マテリアライゼーションが `incremental`
2. 対象テーブルがすでに Snowflake に存在する
3. `--full-refresh` フラグが付いていない
4. dbt が非初回実行

### 基本パターン

```sql
{{ config(materialized='incremental') }}

select * from {{ source('app', 'events') }}

{% if is_incremental() %}
  -- 増分実行時のみ: 前回以降のデータだけを取得
  where event_time > (select max(event_time) from {{ this }})
{% endif %}
```

### `{{ this }}` について

- 現在のモデルが作成するテーブル/ビューを参照する
- 初回実行時は存在しないため、`is_incremental()` の中でのみ使う

---

## 7-3. incremental_strategy

| 戦略 | SQL | 説明 | Snowflake |
|---|---|---|---|
| **append** | `INSERT INTO` | 新規レコードを追加のみ | ○ |
| **merge** | `MERGE INTO` | 挿入・更新（upsert） | ○ |
| **delete+insert** | `DELETE` → `INSERT` | 削除後に挿入 | ○ |
| **microbatch** | 時間バッチ | 時間ベースのバッチ処理 (v1.9+) | ○ |

### append 戦略

```sql
{{ config(
    materialized='incremental'
) }}
-- unique_key を指定しない → append（デフォルト）
```

- 重複を許容する場合に使用
- 最もシンプルで高速

### merge 戦略

```sql
{{ config(
    materialized='incremental',
    unique_key='order_id'
) }}
```

- `unique_key` を指定すると自動的に merge 戦略になる
- 既存行は UPDATE、新規行は INSERT

### delete+insert 戦略

```sql
{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='order_id'
) }}
```

- merge より高速な場合がある（大規模な更新時）

---

## 7-4. スキーマ変更への対応

| 設定値 | 動作 |
|---|---|
| `ignore`（デフォルト） | 新カラムを無視 |
| `fail` | エラーで停止 |
| `append_new_columns` | 新カラムを追加（既存データは NULL） |
| `sync_all_columns` | カラム構成を完全同期 |

```sql
{{ config(
    materialized='incremental',
    on_schema_change='append_new_columns'
) }}
```

---

## 7-5. microbatch 戦略 (v1.9+)

大規模時系列データを**時間ベースのバッチ**に分割して処理する戦略。

### 特徴

- 各バッチが**独立・冪等**（失敗バッチのみリトライ可能）
- `is_incremental()` ブロック**不要**
- 遅延レコードにも `lookback` で対応

### 作成例

**ファイル**: `models/marts/fct_orders_daily.sql`

```sql
{{
    config(
        materialized='incremental',
        incremental_strategy='microbatch',
        event_time='order_date',
        batch_size='month',
        begin='2018-01-01',
        unique_key='order_id'
    )
}}

with orders_joined as (
    select * from {{ ref('int_orders_joined') }}
),

payment_mapping as (
    select * from {{ ref('payment_method_mapping') }}
),

final as (
    select
        orders_joined.order_id,
        orders_joined.customer_id,
        orders_joined.order_date,
        orders_joined.status,
        orders_joined.payment_method,
        payment_mapping.payment_method_name_ja,
        orders_joined.amount_cents / 100.0 as amount
    from orders_joined
    left join payment_mapping
        on orders_joined.payment_method = payment_mapping.payment_method
)

select * from final
```

### 設定パラメータ

| パラメータ | 必須 | 説明 |
|---|---|---|
| `event_time` | ○ | 時間カラム名（UTC と仮定される） |
| `batch_size` | ○ | バッチ粒度: `hour` / `day` / `month` / `year` |
| `begin` | ○ | 処理開始日（初回・フルリフレッシュ時の起点） |
| `unique_key` | × | マージキー |
| `lookback` | × | 遅延レコード対応のバッチ数（デフォルト: 1） |
| `concurrent_batches` | × | 並列バッチ実行（true / false） |

---

## 7-6. 実行と運用

### 通常の増分実行

```bash
dbt run --select fct_orders_daily
```

初回は全バッチ（`begin` から現在まで）を処理。2回目以降は前回の続きから。

### フルリフレッシュ

```bash
dbt run --select fct_orders_daily --full-refresh
```

テーブルを DROP して全データを再作成。

### バックフィル（microbatch 限定）

特定期間のみ再処理:

```bash
dbt run --select fct_orders_daily \
  --event-time-start "2024-01-01" \
  --event-time-end "2024-02-01"
```

### リトライ（microbatch 限定）

失敗バッチのみ再処理:

```bash
dbt retry
```

### full_refresh を無効化（推奨）

```sql
{{ config(
    materialized='incremental',
    incremental_strategy='microbatch',
    full_refresh=false
) }}
```

`--full-refresh` を誤って実行してもフルリビルドされない。バックフィルで代替する。

---

## 7-7. incremental_predicates（参考）

大規模テーブルで merge のパフォーマンスを改善する追加述語:

```sql
{{ config(
    materialized='incremental',
    unique_key='order_id',
    incremental_predicates=[
        "DBT_INTERNAL_DEST.order_date >= dateadd(day, -7, current_date)"
    ]
) }}
```

MERGE 文の ON 句に述語が追加され、スキャン範囲が限定される。

---

## 確認チェックリスト

- [ ] インクリメンタルモデルの基本概念（差分処理）を理解した
- [ ] `is_incremental()` マクロの動作を理解した
- [ ] 4つの incremental_strategy（append, merge, delete+insert, microbatch）を理解した
- [ ] microbatch モデル（`fct_orders_daily`）を作成した
- [ ] `dbt run` で初回実行が成功した
- [ ] `--full-refresh` によるフルリビルドを理解した
- [ ] バックフィル（`--event-time-start/end`）の使い方を理解した
