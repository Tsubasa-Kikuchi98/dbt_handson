{% macro update_customer() %}
    {% set sql %}
        update {{ source('jaffle_shop', 'customers') }}
        set last_name = 'Updated'
        where id = 1
    {% endset %}
    {{ run_query(sql) }}
    {{ log("Customer id=1 の last_name を 'Updated' に変更しました", info=true) }}
{% endmacro %}
