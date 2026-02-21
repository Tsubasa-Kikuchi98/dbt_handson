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
