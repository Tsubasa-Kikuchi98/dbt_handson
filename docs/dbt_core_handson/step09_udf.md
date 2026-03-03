# Step 9: ユーザー定義関数（UDF）(v1.11 新機能)

## 目的

dbt v1.11 で追加された UDF（User Defined Function）のファーストクラスサポートを学ぶ。`functions/` ディレクトリに UDF を定義し、モデルから参照する。

---

## 前提条件

- Step 8 が完了していること
- dbt-core 1.11 以上がインストールされていること（本環境: 1.11.5）

---

## 9-1. UDF の基本

### 従来の方法

これまで dbt で UDF を管理するには、マクロ + `run-operation` や `on-run-start` フックで `CREATE FUNCTION` を実行する必要があった。

### v1.11 の新方式

- `functions/` ディレクトリに YAML + SQL で UDF を定義
- dbt がファーストクラスリソースとして管理
- `{{ function('function_name') }}` マクロでモデルから参照
- `dbt build` 時に自動的にウェアハウスに作成される

---

## 9-2. ディレクトリ構成

```
dbt_handson_project/
├── functions/                     ← UDF 定義ファイルを配置
│   ├── _functions.yml             ← UDF のプロパティ定義
│   └── cents_to_dollars.sql       ← SQL UDF の本体
├── models/
│   └── ...
└── dbt_project.yml
```

---

## 9-3. SQL UDF の作成

### UDF 本体の作成

**ファイル**: `functions/cents_to_dollars.sql`

```sql
cents / 100.0
```

> UDF 本体には `CREATE FUNCTION` は書かない。関数のボディ（式）だけを書く。

### UDF プロパティの定義

**ファイル**: `functions/_functions.yml`

```yaml
version: 2

functions:
  - name: cents_to_dollars
    description: "セント単位の金額をドル単位に変換する"
    args:
      - name: cents
        data_type: number
    returns: number(16, 2)
    language: sql
```

### プロパティの説明

| 項目 | 説明 |
|---|---|
| `name` | 関数名（ファイル名と一致させる） |
| `description` | 関数の説明 |
| `args` | 引数のリスト（`name` と `data_type`） |
| `returns` | 戻り値の型 |
| `language` | `sql` または `python` |

---

## 9-4. UDF のモデルからの参照

### function() マクロ

```sql
{{ function('cents_to_dollars') }}
```

これがコンパイルされると、Snowflake 上の完全修飾名に解決される:

```sql
DATALAKE_DB.PUBLIC.CENTS_TO_DOLLARS
```

### モデルでの使用例

```sql
select
    order_id,
    {{ function('cents_to_dollars') }}(amount_cents) as amount
from {{ ref('stg_jaffle_shop__payments') }}
```

---

## 9-5. Python UDF の作成（参考）

### UDF 本体

**ファイル**: `functions/add_tax.py`

```python
return price * (1 + tax_rate)
```

### プロパティ

```yaml
functions:
  - name: add_tax
    description: "税込金額を計算する"
    args:
      - name: price
        data_type: float
      - name: tax_rate
        data_type: float
    returns: float
    language: python
    runtime_version: '3.11'
```

---

## 9-6. UDF のビルドと確認

### ビルド

```bash
# UDF を含む全リソースをビルド
dbt build

# UDF のみビルド（モデルは実行しない）
dbt run --select resource_type:function
```

### 確認（Snowflake ワークシート）

```sql
-- 作成された UDF の確認
SHOW USER FUNCTIONS IN SCHEMA DATALAKE_DB.PUBLIC;

-- UDF のテスト実行
SELECT DATALAKE_DB.PUBLIC.CENTS_TO_DOLLARS(1500);
-- 結果: 15.00
```

---

## 9-7. デフォルト引数（参考）

```yaml
functions:
  - name: cents_to_dollars
    args:
      - name: cents
        data_type: number
      - name: scale
        data_type: number
        default: 2
    returns: number
    language: sql
```

---

## 9-8. 注意事項

| 項目 | 注意 |
|---|---|
| dbt バージョン | v1.11 以上が必要 |
| アダプター | dbt-snowflake 1.11 以上が必要 |
| Snowflake 上の dbt | v1.9 系のため **非対応**（dbt Projects on Snowflake では使えない） |
| 命名 | ファイル名 = 関数名 |
| 権限 | `CREATE FUNCTION` 権限が必要 |

---

## 確認チェックリスト

- [ ] `functions/` ディレクトリの役割を理解した
- [ ] SQL UDF の定義方法（本体 + YAML プロパティ）を理解した
- [ ] `{{ function('name') }}` マクロの使い方を理解した
- [ ] `dbt build` で UDF がウェアハウスに作成されることを確認した
- [ ] Snowflake 上で UDF が正しく動作することを確認した
- [ ] dbt Projects on Snowflake では v1.11 の UDF が非対応であることを認識した
