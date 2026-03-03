# Step 6: Seeds と Snapshots

## 目的

CSV データを Seed として管理する方法と、SCD Type 2 によるスナップショットの作成方法を学ぶ。

---

## 前提条件

- Step 5 が完了していること

---

## 6-1. Seeds

### Seeds とは

- `seeds/` ディレクトリに CSV ファイルを配置する
- `dbt seed` コマンドでウェアハウスにテーブルとしてロードする
- `ref()` で他モデルから参照可能

### 適切な用途

| 適切 | 不適切 |
|---|---|
| マスタデータ（カテゴリ、区分） | 大規模データ（数万行以上） |
| マッピングテーブル | 本番データ |
| 除外リスト | 機密情報 |
| テスト用の固定データ | 頻繁に変わるデータ |

### Seed ファイルの作成

**ファイル**: `seeds/payment_method_mapping.csv`

```csv
payment_method,payment_method_name_ja
credit_card,クレジットカード
coupon,クーポン
bank_transfer,銀行振込
gift_card,ギフトカード
```

### Seed のロード

```bash
dbt seed
```

**期待される出力:**

```
1 of 1 OK loaded seed file PUBLIC.PAYMENT_METHOD_MAPPING ... [INSERT 4 in 1.23s]
```

### Seed をモデルから参照

```sql
-- fct_orders.sql 内で
select * from {{ ref('payment_method_mapping') }}
```

> 本プロジェクトでは `fct_orders.sql` で seed を LEFT JOIN して `payment_method_name_ja` を取得している。

### Seed の設定

`dbt_project.yml` で設定:

```yaml
seeds:
  dbt_handson_project:
    +schema: seeds                          # 出力先スキーマ
    payment_method_mapping:
      +column_types:
        payment_method: varchar(50)         # 型の明示指定
        payment_method_name_ja: varchar(50)
```

### Seed の再ロード

カラム構成が変わった場合（カラム追加・削除・型変更）:

```bash
dbt seed --full-refresh
```

> `--full-refresh` は既存テーブルを DROP CASCADE して再作成する。

個別の Seed のみ実行:

```bash
dbt seed --select payment_method_mapping
```

---

## 6-2. Snapshots（SCD Type 2）

### Snapshots とは

- ソーステーブルの**変更履歴**を追跡する仕組み
- Slowly Changing Dimension Type 2（SCD Type 2）を実現
- 「いつ」「何が」変わったかを記録する

### スナップショットメタカラム

dbt が自動で追加するカラム:

| カラム | 説明 |
|---|---|
| `dbt_valid_from` | この版の有効開始日時 |
| `dbt_valid_to` | この版の有効終了日時（現行レコードは NULL） |
| `dbt_scd_id` | スナップショット行の一意ID |
| `dbt_updated_at` | ソースの更新日時 |

### スナップショットの作成

**ファイル**: `snapshots/snp_jaffle_shop__customers.sql`

```sql
{% snapshot snp_jaffle_shop__customers %}

{{
    config(
        target_schema='snapshots',
        unique_key='id',
        strategy='check',
        check_cols=['first_name', 'last_name']
    )
}}

select * from {{ source('jaffle_shop', 'customers') }}

{% endsnapshot %}
```

### 構文のポイント

| 要素 | 説明 |
|---|---|
| `{% snapshot name %}...{% endsnapshot %}` | スナップショットブロック |
| `unique_key` | 行を一意に特定するキー（必須） |
| `strategy` | 変更検知の戦略 |
| `target_schema` | スナップショットテーブルの出力先スキーマ |

---

## 6-3. スナップショット戦略

### timestamp 戦略（推奨）

```sql
{{
    config(
        unique_key='id',
        strategy='timestamp',
        updated_at='updated_at'
    )
}}
```

- `updated_at` カラムの値で変更を検知
- スキーマ変更（カラム追加など）に強い
- ソースに `updated_at` カラムがある場合に推奨

### check 戦略

```sql
{{
    config(
        unique_key='id',
        strategy='check',
        check_cols=['first_name', 'last_name']
    )
}}
```

- 指定カラムの値を前回と比較して変更を検知
- `updated_at` カラムがない場合に使用
- `check_cols='all'` で全カラムを監視可能

### 本プロジェクトの採用

本プロジェクトでは `customers` テーブルに `updated_at` がないため **check 戦略**を使用。`first_name` と `last_name` の変更を監視する。

---

## 6-4. スナップショットの実行

```bash
dbt snapshot
```

### 初回実行

- スナップショットテーブルが作成される
- 全行が `dbt_valid_from = 現在時刻`, `dbt_valid_to = NULL`（現行レコード）として挿入される

### 2回目以降の実行

1. ソースデータを取得
2. 前回のスナップショットと比較
3. **変更があった行**: 旧レコードの `dbt_valid_to` を更新し、新レコードを挿入
4. **新規行**: 新レコードを挿入
5. **変更なしの行**: 何もしない

### 確認（Snowflake ワークシート）

```sql
-- スナップショットテーブルの確認
SELECT * FROM DATALAKE_DB.SNAPSHOTS.SNP_JAFFLE_SHOP__CUSTOMERS
ORDER BY id, dbt_valid_from;

-- 現行レコードのみ
SELECT * FROM DATALAKE_DB.SNAPSHOTS.SNP_JAFFLE_SHOP__CUSTOMERS
WHERE dbt_valid_to IS NULL;
```

---

## 6-5. スナップショットの設定オプション

| 設定 | 説明 |
|---|---|
| `unique_key` | 行の一意キー（必須） |
| `strategy` | `timestamp` または `check` |
| `updated_at` | タイムスタンプカラム（timestamp 戦略時） |
| `check_cols` | 監視カラムリスト or `'all'`（check 戦略時） |
| `target_schema` | 出力先スキーマ |
| `dbt_valid_to_current` | 現行レコードの `dbt_valid_to` 値（例: `'9999-12-31'`）(v1.9+) |
| `hard_deletes` | 削除の追跡方法（`'new_record'`） |
| `snapshot_meta_column_names` | メタカラム名のカスタマイズ |

### hard_deletes の例

```sql
{{
    config(
        unique_key='id',
        strategy='check',
        check_cols='all',
        hard_deletes='new_record'
    )
}}
```

ソースから削除された行に対して、`dbt_is_deleted = true` の新レコードが挿入される。

---

## 6-6. スキーマ進化

| 変更の種類 | 対応 |
|---|---|
| 新カラムの追加 | 自動対応 |
| varchar サイズの拡張 | 自動対応 |
| カラム削除 | 非対応（履歴データ保護のため） |
| カラムの型変更 | 非対応 |

---

## 確認チェックリスト

- [ ] Seed ファイル（`payment_method_mapping.csv`）を作成した
- [ ] `dbt seed` でテーブルがロードされた
- [ ] `ref()` で Seed をモデルから参照できた
- [ ] スナップショット（`snp_jaffle_shop__customers.sql`）を作成した
- [ ] `dbt snapshot` でスナップショットテーブルが作成された
- [ ] スナップショットのメタカラム（dbt_valid_from, dbt_valid_to 等）を理解した
- [ ] timestamp 戦略と check 戦略の違いを理解した
