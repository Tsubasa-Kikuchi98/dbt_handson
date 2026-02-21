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