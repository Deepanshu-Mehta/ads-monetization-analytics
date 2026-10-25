-- Marts: Criteo platform P&L, campaigns and conversions.
-- Built only after gate 1 (sql/02_test_staging) passes.
-- Money columns carry the _idx suffix: cost and cpo are transformed values, not real prices.
-- Revenue is booked by conversion day; media cost by impression day (D13, D14).
-- Revenue = cpo_idx summed over attributed conversion x campaign rows (D02, D28).

-- fact_conversion
-- Grain: one row per conversion x campaign.   Primary key: (conversion_id, campaign_id)
-- Source: stg_criteo_imps rows with conversion = 1. A conversion repeats on every impression
-- in its path, so revenue is counted here, once per conversion x campaign (D02, D28).
-- 0.66% of conversion_ids span 2-3 campaigns with different conversion timestamps, so the
-- campaign is part of the key. cpo varies across rows of the same conversion in 28% of cases;
-- revenue uses the cpo on the last impression before the conversion (D28). cpo_values and
-- conversion_ts_values keep that variation visible for the Phase 2 profile. last_impression_ts
-- and _day date the touch closest to the conversion, for conversion-lag measures (D36, D40).
CREATE OR REPLACE TABLE fact_conversion AS
WITH rows AS (     -- 51 pairs carry more than one conversion timestamp: anchor on the first
    SELECT *, min(conversion_ts) OVER (PARTITION BY conversion_id, campaign_id) AS first_conversion_ts
    FROM stg_criteo_imps
    WHERE conversion = 1
)
SELECT
    conversion_id,
    campaign_id,
    max(attribution)                                                   AS attributed,
    arg_max(cpo, (ts, imp_id)) FILTER (WHERE ts <= first_conversion_ts) AS cpo_idx,
    count(DISTINCT cpo)                                                AS cpo_values,
    min(conversion_ts)                                                 AS conversion_ts,
    min(conversion_ts) // 86400                                        AS conversion_day,
    max(ts) FILTER (WHERE ts <= first_conversion_ts)                   AS last_impression_ts,
    max(ts) FILTER (WHERE ts <= first_conversion_ts) // 86400          AS last_impression_day,
    count(DISTINCT conversion_ts)                                      AS conversion_ts_values,
    count(*)                                                           AS impression_rows
FROM rows
GROUP BY conversion_id, campaign_id;

-- dim_campaign
-- Grain: one row per campaign (treated as one advertiser).   Primary key: campaign_id
-- Source: stg_criteo_imps. segment is filled in Phase 5 (Q11).
CREATE OR REPLACE TABLE dim_campaign AS
SELECT
    campaign_id,
    min(day)                               AS first_day,
    max(day)                               AS last_day,
    count(DISTINCT day)                    AS active_days,
    count(*)                               AS impressions,
    sum(cost)                              AS media_cost_idx,
    CAST(NULL AS VARCHAR)                  AS segment
FROM stg_criteo_imps
GROUP BY campaign_id;

-- mart_campaign_day
-- Grain: one row per campaign x day.   Primary key: (campaign_id, day)
-- Source: stg_criteo_imps (impression-dated: impressions, clicks, media cost)
--         + fact_conversion (conversion-dated: conversions, revenue).
-- Conversions can land up to 30 days after the last impression, so some rows fall after
-- the impression window; in_impression_window flags them. margin_idx is a booked-date
-- view: use it over the whole period or middle weeks only, never as a daily line (D14).
CREATE OR REPLACE TABLE mart_campaign_day AS
WITH imp AS (
    SELECT campaign_id, day,
           count(*)                        AS impressions,
           sum(click)::BIGINT              AS clicks,
           sum(cost)                       AS media_cost_idx
    FROM stg_criteo_imps
    GROUP BY ALL
),
conv AS (
    SELECT campaign_id, conversion_day     AS day,
           count(*)                                        AS conversions,
           count(*) FILTER (WHERE attributed = 1)          AS attributed_conversions,
           coalesce(sum(cpo_idx) FILTER (WHERE attributed = 1), 0) AS revenue_idx
    FROM fact_conversion
    GROUP BY ALL
)
SELECT
    coalesce(i.campaign_id, c.campaign_id)                         AS campaign_id,
    coalesce(i.day, c.day)                                         AS day,
    coalesce(i.impressions, 0)                                     AS impressions,
    coalesce(i.clicks, 0)                                          AS clicks,
    coalesce(i.media_cost_idx, 0)                                  AS media_cost_idx,
    coalesce(c.conversions, 0)                                     AS conversions,
    coalesce(c.attributed_conversions, 0)                          AS attributed_conversions,
    coalesce(c.revenue_idx, 0)                                     AS revenue_idx,
    coalesce(c.revenue_idx, 0) - coalesce(i.media_cost_idx, 0)     AS margin_idx,
    coalesce(i.day, c.day) <= (SELECT max(day) FROM stg_criteo_imps) AS in_impression_window
FROM imp i
FULL OUTER JOIN conv c
  ON c.campaign_id = i.campaign_id AND c.day = i.day;
