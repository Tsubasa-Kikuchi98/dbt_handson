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
