# Step 11: ドキュメントと運用

## 目的

dbt のドキュメント生成、Analyses、Exposures、dbt build、ノード選択構文など、プロジェクトの運用に関わる機能を学ぶ。

---

## 前提条件

- Step 10 が完了していること

---

## 11-1. ドキュメント記述

### YAML の description

schema.yml でモデル・カラムに説明を記述（すべての Step で既に実施済み）:

```yaml
models:
  - name: fct_orders
    description: "注文ファクトテーブル。1行 = 1注文。"
    columns:
      - name: order_id
        description: "注文の一意識別子"
```

### Docs ブロック（Markdown ドキュメント）

長い説明やフォーマットが必要な場合、Docs ブロックを使う。

**ファイル**: `models/docs.md`（任意のファイル名）

```
{% docs fct_orders_description %}

## 注文ファクトテーブル

このテーブルは Jaffle Shop の全注文データを含む。

### カラム説明

| カラム | 説明 |
|---|---|
| order_id | 注文の一意識別子 |
| customer_id | 注文した顧客のID |
| amount | 支払金額（ドル単位、セントから変換済み） |

### 注意事項

- `amount` はセント単位の `amount_cents` を 100 で割って計算
- `payment_method_name_ja` は seed テーブルから結合

{% enddocs %}
```

YAML から参照:

```yaml
models:
  - name: fct_orders
    description: "{{ doc('fct_orders_description') }}"
```

### __overview__ ブロック（トップページ）

```
{% docs __overview__ %}

# Jaffle Shop dbt プロジェクト

このプロジェクトは Jaffle Shop のデータウェアハウスを管理する dbt プロジェクトです。

## モデル構成

- **staging**: ソースデータの軽い変換
- **intermediate**: ビジネスロジックの中間処理
- **marts**: 分析用の最終テーブル

{% enddocs %}
```

---

## 11-2. ドキュメント生成・閲覧

### 生成

```bash
dbt docs generate
```

以下のファイルが `target/` に生成される:

| ファイル | 説明 |
|---|---|
| `manifest.json` | DAG、モデルプロパティ、リネージ |
| `catalog.json` | Snowflake のテーブル/カラム情報（実際の DB からメタデータ取得） |
| `index.html` | ドキュメントサイトのエントリーポイント |

### 閲覧

```bash
dbt docs serve
```

ブラウザが自動で開き、ドキュメントサイトが表示される（デフォルト: http://localhost:8080）。

### ドキュメントサイトの機能

- モデル一覧と検索
- DAG のインタラクティブな可視化
- カラム情報（型、説明、テスト）
- ソースとモデルのリネージ
- テスト一覧

---

## 11-3. Analyses

### Analyses とは

- `analyses/` ディレクトリに `.sql` ファイルを配置
- `dbt compile` でコンパイルされるが**実行はされない**
- `ref()` を使った環境非依存のアドホッククエリに利用

### 本プロジェクトの例

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

### コンパイルと確認

```bash
dbt compile
```

コンパイル結果: `target/compiled/dbt_handson_project/analyses/jinja_practice.sql`

このコンパイル済み SQL を Snowflake ワークシートにコピーして実行できる。

---

## 11-4. Exposures

### Exposures とは

ダッシュボードやアプリなど、dbt の**下流の利用先**を定義するもの。DAG 上でモデルの消費者を可視化する。

### 定義

**ファイル**: `models/marts/exposures.yml`

```yaml
exposures:
  - name: jaffle_shop_dashboard
    type: dashboard
    description: "Jaffle Shop の売上分析ダッシュボード"
    maturity: medium
    owner:
      name: Analytics Team
      email: analytics@example.com
    depends_on:
      - ref('fct_orders')
      - ref('dim_customers')
    url: https://bi.example.com/dashboards/jaffle-shop
```

### プロパティ

| 項目 | 説明 | 例 |
|---|---|---|
| `name` | Exposure 名 | `jaffle_shop_dashboard` |
| `type` | 種別 | `dashboard`, `notebook`, `analysis`, `ml`, `application` |
| `description` | 説明 | |
| `maturity` | 成熟度 | `high`, `medium`, `low` |
| `owner` | オーナー情報 | `name`, `email` |
| `depends_on` | 依存するモデル | `ref()` で指定 |
| `url` | アクセス URL | |

### 選択実行

```bash
# Exposure に関連するモデルとその上流を実行
dbt run --select +exposure:jaffle_shop_dashboard
```

---

## 11-5. dbt build

### 概要

モデル実行 + テスト + snapshot + seed + UDF を **DAG 順に一括実行**するコマンド。

```bash
dbt build
```

### 実行順序

```
1. seed のロード
2. ユニットテスト
3. モデル実行（DAG 順）
4. スナップショット
5. データテスト
```

### テスト失敗時の動作

データテストが失敗すると、**そのモデルの下流モデルが自動的にスキップ**される。

### --empty フラグ

```bash
dbt build --empty
```

スキーマのみの空実行。テーブル構造の確認に使用（データは読み込まない）。

---

## 11-6. ノード選択構文

`dbt run`, `dbt test`, `dbt build` 等で使える選択構文:

### 基本

| 構文 | 説明 | 例 |
|---|---|---|
| モデル名 | 単一モデル | `dbt run -s fct_orders` |
| `+model` | 上流を含む | `dbt run -s +fct_orders` |
| `model+` | 下流を含む | `dbt run -s fct_orders+` |
| `+model+` | 上流+下流 | `dbt run -s +fct_orders+` |
| `@model` | 上流+下流すべて | `dbt run -s @fct_orders` |

### 複数指定

| 構文 | 意味 | 例 |
|---|---|---|
| スペース区切り | 和集合（OR） | `-s model_a model_b` |
| カンマ区切り | 積集合（AND） | `-s path:marts,tag:nightly` |
| `--exclude` | 除外 | `--exclude fct_orders_daily` |

### セレクター

| セレクター | 説明 | 例 |
|---|---|---|
| `tag:` | タグで選択 | `-s tag:nightly` |
| `path:` | パスで選択 | `-s path:models/marts` |
| `config:` | 設定値で選択 | `-s config.materialized:table` |
| `test_type:` | テスト種別 | `-s test_type:unit` |
| `source:` | ソース | `-s source:jaffle_shop` |
| `state:` | 変更状態 | `-s state:modified` |
| `resource_type:` | リソース種別 | `-s resource_type:model` |

### プレビュー

```bash
# 選択結果を確認（実行なし）
dbt ls --select "+fct_orders"
dbt ls --select "path:models/marts"
dbt ls --select "tag:nightly"
```

### 実践例

```bash
# marts 配下の table モデルのみ実行
dbt run --select "path:models/marts,config.materialized:table"

# nightly タグのモデルとその上流を実行し、特定モデルを除外
dbt run --select "tag:nightly+" --exclude fct_orders_daily

# staging のテストのみ実行
dbt test --select "path:models/staging"

# ソースの下流すべてを実行
dbt build --select "source:jaffle_shop+"
```

---

## 11-7. config.meta_get() / config.meta_require() (v1.11)

### 概要

`meta` に格納したカスタム設定値をマクロやフック内から取得する v1.11 の新機能。

### 設定

```yaml
models:
  - name: fct_orders
    config:
      meta:
        owner: analytics_team
        sla_hours: 4
```

### マクロ内での使用

```sql
{% macro check_sla() %}
    {% set sla = config.meta_get('sla_hours', default=24) %}
    {{ log("SLA: " ~ sla ~ " hours", info=true) }}
{% endmacro %}
```

| 関数 | 説明 |
|---|---|
| `config.meta_get('key', default)` | 任意キー取得（キーがなければデフォルト値） |
| `config.meta_require('key')` | 必須キー取得（キーがなければエラー） |

---

## 確認チェックリスト

- [ ] YAML の `description` でモデル・カラムの説明を記述した
- [ ] Docs ブロック（`{% docs %}...{% enddocs %}`）の使い方を理解した
- [ ] `dbt docs generate` でドキュメントを生成した
- [ ] `dbt docs serve` でドキュメントサイトを閲覧した
- [ ] DAG がドキュメントサイト上で可視化されることを確認した
- [ ] Analyses の仕組み（コンパイルのみ、実行されない）を理解した
- [ ] Exposures を定義し、ドキュメントサイトに表示されることを確認した
- [ ] `dbt build` の実行順序と動作を理解した
- [ ] ノード選択構文（`+`, `@`, `tag:`, `path:`, `config:` 等）を理解した
- [ ] `dbt ls --select` で選択結果をプレビューできた
