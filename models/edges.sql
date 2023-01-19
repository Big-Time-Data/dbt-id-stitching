{{ config(materialized='incremental', unique_key='original_rudder_id') }}

{% if not is_incremental() %}

    {% set sql_statements = dbt_utils.get_column_values(table=ref('queries'), column='sql_to_run') %}

    SELECT
        ROW_NUMBER() OVER (ORDER BY edge_rank_id ASC, edge_a, edge_b) AS rudder_id,
        ROW_NUMBER() OVER (ORDER BY edge_rank_id ASC, edge_a, edge_b) AS original_rudder_id,
        edge_a,
        edge_a_label,
        edge_b,
        edge_b_label,
        edge_timestamp,
        edge_rank_id
    FROM (
        {{ ' UNION '.join(sql_statements) }}
    ) AS s
    WHERE
        NOT LOWER(edge_a) in {{ var('ids-to-exclude') }}
        AND NOT LOWER(edge_b) in {{ var('ids-to-exclude') }}

{% else %}

    WITH
    cte_timestamp AS (
        SELECT
            rudder_id,
            MIN(edge_timestamp) AS edge_timestamp,
            MIN(edge_rank_id) AS edge_rank_id
        FROM {{ this }}
        GROUP BY rudder_id
    ),

    cte_min_edge_1 AS (
        select 
          t.*,
          cte_timestamp.edge_timestamp,
          cte_timestamp.edge_rank_id
        from (
          SELECT
              edge,
              MIN(rudder_id) AS first_row_id
          FROM (
              SELECT
                  rudder_id,
                  LOWER(edge_a) AS edge
              FROM {{ this }}
              UNION
              SELECT
                  rudder_id,
                  LOWER(edge_b) AS edge
              FROM {{ this }}
          ) AS c

          GROUP BY edge
        ) t
        join cte_timestamp on cte_timestamp.rudder_id = t.first_row_id
    ),

    cte_min_edge_2 AS (
        SELECT
            edge,
            MIN(rudder_id) AS first_row_id,
            MIN(edge_timestamp) as edge_timestamp,
            MIN(edge_rank_id) as edge_rank_id
        FROM (
            SELECT
                LEAST(a.first_row_id, b.first_row_id) AS rudder_id,
                LEAST(a.edge_timestamp, b.edge_timestamp) AS edge_timestamp,
                LEAST(a.edge_rank_id, b.edge_rank_id) AS edge_rank_id,
                LEAST(o.edge_a) AS edge
            FROM {{ this }} AS o
            LEFT OUTER JOIN cte_min_edge_1 AS a
                ON LOWER(o.edge_a) = a.edge
            LEFT OUTER JOIN cte_min_edge_1 AS b
                ON LOWER(o.edge_b) = b.edge
            UNION
            SELECT
                LEAST(a.first_row_id, b.first_row_id) AS rudder_id,
                LEAST(a.edge_timestamp, b.edge_timestamp) AS edge_timestamp,
                LEAST(a.edge_rank_id, b.edge_rank_id) AS edge_rank_id,
                LOWER(o.edge_b) AS edge
            FROM {{ this }} AS o
            LEFT OUTER JOIN cte_min_edge_1 AS a
                ON LOWER(o.edge_a) = a.edge
            LEFT OUTER JOIN cte_min_edge_1 AS b
                ON LOWER(o.edge_b) = b.edge

        ) AS g
        GROUP BY edge
    ),

    cte_min_edge_3 AS (
        SELECT
            edge,
            MIN(rudder_id) AS first_row_id,
            MIN(edge_timestamp) as edge_timestamp,
            MIN(edge_rank_id) as edge_rank_id
        FROM (
            SELECT
                LEAST(a.first_row_id, b.first_row_id) AS rudder_id,
                LEAST(a.edge_timestamp, b.edge_timestamp) AS edge_timestamp,
                LEAST(a.edge_rank_id, b.edge_rank_id) AS edge_rank_id,
                LOWER(o.edge_a) AS edge
            FROM {{ this }} AS o
            LEFT OUTER JOIN cte_min_edge_2 AS a
                ON LOWER(o.edge_a) = a.edge
            LEFT OUTER JOIN cte_min_edge_2 AS b
                ON LOWER(o.edge_b) = b.edge
            UNION
            SELECT
                LEAST(a.first_row_id, b.first_row_id) AS rudder_id,
                LEAST(a.edge_timestamp, b.edge_timestamp) AS edge_timestamp,
                LEAST(a.edge_rank_id, b.edge_rank_id) AS edge_rank_id,
                LOWER(o.edge_b) AS edge
            FROM {{ this }} AS o
            LEFT OUTER JOIN cte_min_edge_2 AS a
                ON LOWER(o.edge_a) = a.edge
            LEFT OUTER JOIN cte_min_edge_2 AS b
                ON LOWER(o.edge_b) = b.edge

        ) AS h
        GROUP BY edge
    ),

    cte_new_id AS (
        SELECT
            o.original_rudder_id,
            LEAST(a.first_row_id, b.first_row_id) AS new_rudder_id,
            LEAST(a.edge_timestamp, b.edge_timestamp) AS edge_timestamp,
            LEAST(a.edge_rank_id, b.edge_rank_id) AS edge_rank_id
        FROM {{ this }} AS o
        LEFT OUTER JOIN cte_min_edge_3 AS a
            ON LOWER(o.edge_a) = a.edge
        LEFT OUTER JOIN cte_min_edge_3 AS b
            ON LOWER(o.edge_b) = b.edge
    )

    SELECT
        cte_new_id.new_rudder_id AS rudder_id,
        e.original_rudder_id,
        e.edge_a,
        e.edge_a_label,
        e.edge_b,
        e.edge_b_label,
        cte_new_id.edge_timestamp AS edge_timestamp,
        cte_new_id.edge_rank_id AS edge_rank_id
    FROM {{ this }} AS e
    INNER JOIN cte_new_id
        ON e.original_rudder_id = cte_new_id.original_rudder_id
    WHERE e.rudder_id != cte_new_id.new_rudder_id

{% endif %}
