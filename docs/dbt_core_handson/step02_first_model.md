# Step 2: 最初のモデルを作る

## 目的

SQL モデルの基本を理解し、`dbt run` でモデルを Snowflake 上にビルドする。マテリアライゼーション、config ブロック、`ref()` 関数を学ぶ。

---

## 前提条件

- Step 1 が完了していること（プロジェクト作成・接続確認済み）
- Snowflake にソースデータ（`JAFFLE_SHOP_RAW.JAFFLE_SHOP`）が存在すること

---

## 2-1. SQL モデルの基本

### ルール

- `models/` ディレクトリに `.sql` ファイルを作成する
- **モデル名 = ファイル名**（拡張子を除く）
- **1ファイル = 1つの SELECT 文**
- `CREATE TABLE` や `CREATE VIEW` は書かない（dbt が自動で付与する）

### 最初のモデルを作成

**ファイル**: `models/my_first_model.sql`

```sql
select
    id as customer_id,
    first_name,
    last_name
from JAFFLE_SHOP_RAW.JAFFLE_SHOP.CUSTOMERS
```

> この時点ではまだ `source()` を使わず、テーブル名をハードコードしている。Step 3 で `source()` に置き換える。

---

## 2-2. dbt run によるモデル実行

```bash
cd /c/Users/tsuba/dbt_handson/dbt_handson_project
dbt run
```

### 何が起きるか

1. dbt がモデルファイルの SELECT 文を読み取る
2. `CREATE VIEW AS ...` でラップする（デフォルトのマテリアライゼーションが `view` のため）
3. Snowflake にビューを作成する
4. 既にビューが存在する場合は **アトミックに置換**（ダウンタイムなし）

### 期待される出力

```
Running with dbt=1.11.5
Found 1 model, ...

Concurrency: 1 threads (target='dev')

1 of 1 OK created sql view model PUBLIC.MY_FIRST_MODEL ............. [SUCCESS 1 in 1.23s]

Finished running 1 view model in 0 hours 0 minutes and X.XX seconds.
Completed successfully
Done. PASS=1 WARN=0 ERROR=0 SKIP=0 TOTAL=1
```

### 確認（Snowflake ワークシート）

```sql
SELECT * FROM DATALAKE_DB.PUBLIC.MY_FIRST_MODEL LIMIT 10;
```

---

## 2-3. マテリアライゼーション

dbt がモデルをどのような形式で Snowflake に作成するかを決める設定。

| 種類 | SQL | 用途 |
|---|---|---|
| **view** (デフォルト) | `CREATE VIEW AS` | シンプルな変換、常に最新データが必要な場合 |
| **table** | `CREATE TABLE AS` | BIツールからの高速クエリ、重い変換 |
| **ephemeral** | CTE に展開（DB に作成されない） | 軽量な中間処理、1-2 の下流モデルのみ |
| **incremental** | `INSERT` / `MERGE` | 大規模データ（Step 7 で詳述） |
| **materialized_view** | `CREATE MATERIALIZED VIEW` | 自動リフレッシュが必要な場合 |

> Snowflake では `materialized_view` の代わりに **Dynamic Table** が推奨される。

---

## 2-4. config ブロック

### モデル内で設定する方法

**ファイル**: `models/my_first_model.sql`

```sql
{{
    config(
        materialized='table'
    )
}}

select
    id as customer_id,
    first_name,
    last_name
from JAFFLE_SHOP_RAW.JAFFLE_SHOP.CUSTOMERS
```

### dbt_project.yml でディレクトリ単位設定

```yaml
models:
  dbt_handson_project:
    +materialized: view          # 全モデルのデフォルト
    staging:
      +materialized: view        # staging/ 以下は view
    marts:
      +materialized: table       # marts/ 以下は table
```

### 設定の優先順位

```
ファイル内 config() > schema.yml > dbt_project.yml
（ファイル内が最も優先される）
```

---

## 2-5. ref() 関数

モデル間の依存関係を宣言する関数。

### 基本構文

```sql
select * from {{ ref('model_name') }}
```

### 何が起きるか

1. **DAG（有向非巡回グラフ）** が自動構築される
2. 環境ごとに適切な **スキーマ解決** が行われる
   - dev: `DATALAKE_DB.DEV.model_name`
   - prod: `DATALAKE_DB.PROD.model_name`
3. dbt が **依存順** にモデルを実行する

### 使用例

```sql
-- dim_customers.sql
select * from {{ ref('stg_jaffle_shop__customers') }}
```

### 2引数構文（パッケージ間参照）

```sql
select * from {{ ref('package_name', 'model_name') }}
```

---

## 2-6. モデルの設定オプション

### 主要な設定一覧

| 設定 | 説明 | 例 |
|---|---|---|
| `materialized` | マテリアライゼーション種別 | `'table'`, `'view'` |
| `schema` | 出力先スキーマ | `'marts'` |
| `alias` | テーブル/ビュー名のオーバーライド | `'orders'` |
| `database` | 出力先データベース | `'ANALYTICS_DB'` |
| `tags` | タグ付け（選択実行に利用） | `['nightly', 'finance']` |
| `pre-hook` | ビルド前に実行する SQL | `"ALTER WAREHOUSE ..."` |
| `post-hook` | ビルド後に実行する SQL | `"GRANT SELECT ..."` |
| `grants` | オブジェクトレベルの権限設定 | `{select: ['ANALYST']}` |
| `persist_docs` | ドキュメントの永続化 | `{relation: true, columns: true}` |
| `meta` | カスタムメタデータ | `{owner: 'analytics'}` |

### 設定の例

```sql
{{
    config(
        materialized='table',
        schema='marts',
        tags=['nightly'],
        post_hook="GRANT SELECT ON {{ this }} TO ROLE ANALYST"
    )
}}

select ...
```

---

## 2-7. 特定モデルのみ実行

```bash
# 特定モデルのみ
dbt run --select my_first_model

# 特定モデルとその上流すべて
dbt run --select +my_first_model

# 特定モデルとその下流すべて
dbt run --select my_first_model+

# 特定モデルとその上流・下流すべて
dbt run --select +my_first_model+
```

---

## 2-8. 練習用モデルの削除

Step 3 以降で本格的なモデルを作るため、ここで作成した `my_first_model.sql` は削除する:

```bash
rm dbt_handson_project/models/my_first_model.sql
```

Snowflake 上のビュー/テーブルも削除:

```sql
DROP VIEW IF EXISTS DATALAKE_DB.PUBLIC.MY_FIRST_MODEL;
```

---

## 確認チェックリスト

- [ ] SQL モデルの基本ルール（1ファイル=1 SELECT）を理解した
- [ ] `dbt run` でモデルが Snowflake にビルドされることを確認した
- [ ] マテリアライゼーションの種類と使い分けを理解した
- [ ] `config()` ブロックの書き方を理解した
- [ ] `ref()` 関数の役割と使い方を理解した
- [ ] 設定の優先順位（ファイル内 > schema.yml > dbt_project.yml）を理解した
