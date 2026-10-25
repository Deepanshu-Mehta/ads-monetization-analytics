-- Staging layer: Criteo Attribution dataset.
-- Typed with strict casts (D21). The dataset uses -1 for "no value" in the conversion
-- and click-history columns; those become NULL here so they cannot leak into sums.
-- cost and cpo are transformed values: report ratios and relative changes only.

-- stg_criteo_imps
-- Grain: one row per impression.   Primary key: imp_id (file row number, released order)
-- Source: raw_criteo
CREATE OR REPLACE TABLE stg_criteo_imps AS
SELECT
    file_row_number                                        AS imp_id,
    CAST("timestamp" AS BIGINT)                            AS ts,          -- seconds from the first impression
    CAST("timestamp" AS BIGINT) // 86400                   AS day,         -- day 0 = first day
    CAST(uid AS BIGINT)                                    AS uid,
    CAST(campaign AS BIGINT)                               AS campaign_id,
    CAST(click AS INTEGER)                                 AS click,
    CAST(conversion AS INTEGER)                            AS conversion,
    nullif(CAST(conversion_timestamp AS BIGINT), -1)       AS conversion_ts,
    nullif(CAST(conversion_id AS BIGINT), -1)              AS conversion_id,
    CAST(attribution AS INTEGER)                           AS attribution,
    nullif(CAST(click_pos AS INTEGER), -1)                 AS click_pos,
    nullif(CAST(click_nb AS INTEGER), -1)                  AS click_nb,
    CAST(cost AS DOUBLE)                                   AS cost,
    CAST(cpo AS DOUBLE)                                    AS cpo,
    nullif(CAST(time_since_last_click AS BIGINT), -1)      AS time_since_last_click,
    CAST(cat1 AS BIGINT) AS cat1, CAST(cat2 AS BIGINT) AS cat2, CAST(cat3 AS BIGINT) AS cat3,
    CAST(cat4 AS BIGINT) AS cat4, CAST(cat5 AS BIGINT) AS cat5, CAST(cat6 AS BIGINT) AS cat6,
    CAST(cat7 AS BIGINT) AS cat7, CAST(cat8 AS BIGINT) AS cat8, CAST(cat9 AS BIGINT) AS cat9
FROM raw_criteo;
