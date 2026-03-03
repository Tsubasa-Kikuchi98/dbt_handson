# Step 10: パッケージ管理

## 目的

dbt パッケージ（dbt-utils, dbt-expectations 等）のインストールと活用方法を学ぶ。

---

## 前提条件

- Step 9 が完了していること

---

## 10-1. packages.yml

### ファイルの作成

**ファイル**: `dbt_handson_project/packages.yml`

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: ">=1.3.0"
  - package: calogica/dbt_expectations
    version: ">=0.10.0"
```

### パッケージのインストール

```bash
cd /c/Users/tsuba/dbt_handson/dbt_handson_project
dbt deps
```

**期待される出力:**

```
Installing dbt-labs/dbt_utils
  Installed from version 1.3.0
Installing calogica/dbt_expectations
  Installed from version 0.10.4
Installing calogica/dbt_date
  Installed from version 0.10.1 (dependency of dbt_expectations)

Updates available:
  ...
```

### インストール先

パッケージは `dbt_packages/` に展開される（`.gitignore` に含めること）。

### パッケージの削除

```bash
dbt clean
```

`dbt_packages/` と `target/` が削除される。再度 `dbt deps` が必要。

---

## 10-2. パッケージの種類

| 種類 | 定義方法 | 説明 |
|---|---|---|
| **Hub パッケージ** | `package:` | dbt Hub から取得（推奨） |
| **Git パッケージ** | `git:` | Git リポジトリから取得 |
| **ローカルパッケージ** | `local:` | ローカルパスから参照 |

### Hub パッケージ

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: ">=1.3.0"
```

- セマンティックバージョニング
- dbt Hub（https://hub.getdbt.com）で検索可能

### Git パッケージ

```yaml
packages:
  - git: "https://github.com/dbt-labs/dbt-utils.git"
    revision: v1.3.0
```

- `revision` でバージョンを固定（タグ、ブランチ、コミットハッシュ）

### ローカルパッケージ

```yaml
packages:
  - local: ../my_other_project
```

- モノレポ構成で使用

---

## 10-3. 代表的なパッケージ

### dbt-utils

汎用ユーティリティマクロ集。

| マクロ | 説明 | 例 |
|---|---|---|
| `generate_surrogate_key` | サロゲートキー生成 | `{{ dbt_utils.generate_surrogate_key(['col1', 'col2']) }}` |
| `star` | テーブルの全カラムを列挙 | `{{ dbt_utils.star(from=ref('model')) }}` |
| `pivot` | ピボットテーブル生成 | `{{ dbt_utils.pivot('status', ...) }}` |
| `date_spine` | 日付の連続生成 | `{{ dbt_utils.date_spine(...) }}` |
| `union_relations` | 複数テーブルの UNION | `{{ dbt_utils.union_relations([...]) }}` |

テストマクロ:

| テスト | 説明 |
|---|---|
| `unique_combination_of_columns` | 複合キーの一意性 |
| `not_constant` | 定数でないこと |
| `at_least_one` | 最低1行存在 |
| `expression_is_true` | 式が TRUE |

使用例:

```yaml
models:
  - name: fct_orders
    data_tests:
      - dbt_utils.unique_combination_of_columns:
          combination_of_columns:
            - order_id
            - payment_method
```

### dbt-expectations

Great Expectations スタイルのデータ品質テスト。

| テスト | 説明 |
|---|---|
| `expect_column_values_to_not_be_null` | NULL でないこと |
| `expect_column_values_to_be_between` | 値の範囲チェック |
| `expect_column_values_to_match_regex` | 正規表現マッチ |
| `expect_table_row_count_to_be_between` | 行数の範囲チェック |
| `expect_column_values_to_be_increasing` | 値が増加すること |

使用例:

```yaml
models:
  - name: fct_orders
    columns:
      - name: amount
        data_tests:
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 0
              max_value: 10000
```

### dbt-date

日付ユーティリティ。`dbt-expectations` の依存パッケージとして自動インストールされる。

### codegen

コード自動生成パッケージ。staging モデルや YAML スキーマを自動生成できる。

```bash
# staging モデルの自動生成
dbt run-operation codegen.generate_base_model --args '{source_name: jaffle_shop, table_name: customers}'

# YAML スキーマの自動生成
dbt run-operation codegen.generate_model_yaml --args '{model_names: [fct_orders]}'
```

---

## 10-4. パッケージのバージョン管理

### package-lock.yml

`dbt deps` 実行後に生成される。インストールされた正確なバージョンが記録される。

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: 1.3.0
  - package: calogica/dbt_expectations
    version: 0.10.4
  - package: calogica/dbt_date
    version: 0.10.1
```

**推奨**: Git にコミットして、チーム全員が同じバージョンを使うようにする。

### バージョン固定 vs 範囲指定

| 指定方法 | 例 | 用途 |
|---|---|---|
| 固定 | `"1.3.0"` | 本番環境の安定性重視 |
| 範囲（以上） | `">=1.3.0"` | 最新バグ修正を自動取得 |
| 範囲（以上かつ未満） | `[">=1.3.0", "<2.0.0"]` | メジャーバージョンを固定 |

---

## 確認チェックリスト

- [ ] `packages.yml` を作成した
- [ ] `dbt deps` でパッケージがインストールされた
- [ ] `dbt_packages/` に展開されたパッケージを確認した
- [ ] dbt-utils のマクロ/テストを使ってみた
- [ ] dbt-expectations のテストを使ってみた
- [ ] `package-lock.yml` が生成されたことを確認した
- [ ] `dbt clean` でパッケージを削除し、再インストールできた
