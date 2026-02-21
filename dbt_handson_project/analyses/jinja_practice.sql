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
