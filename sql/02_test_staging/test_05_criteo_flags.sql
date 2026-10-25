-- Gate 1 · Criteo flag logic
-- The binary flags and conversion fields must agree with each other.
-- (cpo is filled on every row by design, so no test expects it to be empty, D24.)
-- Passes when it returns 0 rows.
WITH c AS (
    SELECT
        count(*) FILTER (WHERE click NOT IN (0, 1) OR conversion NOT IN (0, 1) OR attribution NOT IN (0, 1)) AS non_binary_flags,
        count(*) FILTER (WHERE attribution = 1 AND conversion = 0)          AS attributed_without_conversion,
        count(*) FILTER (WHERE conversion = 1 AND conversion_id IS NULL)    AS conversion_without_id,
        count(*) FILTER (WHERE conversion = 0 AND conversion_id IS NOT NULL) AS id_without_conversion,
        count(*) FILTER (WHERE click_nb < click)                            AS click_count_below_click_flag,
        count(*) FILTER (WHERE cost < 0 OR cpo < 0)                         AS negative_money
    FROM stg_criteo_imps
)
SELECT check_name, value
FROM c
UNPIVOT (value FOR check_name IN (non_binary_flags, attributed_without_conversion, conversion_without_id,
                                  id_without_conversion, click_count_below_click_flag, negative_money))
WHERE value > 0;
