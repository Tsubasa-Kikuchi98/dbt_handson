{{
    config(
        materialized='ephemeral'
    )
}}

with orders as (

    select * from {{ ref('stg_jaffle_shop__orders') }}

),

payments as (

    select * from {{ ref('stg_jaffle_shop__payments') }}

),

orders_with_payments as (

    select
        orders.order_id,
        orders.customer_id,
        orders.order_date,
        orders.status,
        payments.payment_method,
        payments.amount_cents

    from orders
    left join payments on orders.order_id = payments.order_id

)

select * from orders_with_payments
