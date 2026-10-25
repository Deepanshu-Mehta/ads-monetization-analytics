-- Marts: iPinYou star schema (auction health, inventory, pricing simulation).
-- Built only after gate 1 (sql/02_test_staging) passes.
-- Price unit: bid_price, pay_price and floor_price are CPM in Chinese fen (Zhang et al., 2014,
-- section 2.2), so one impression costs pay_price / 1000 fen (D29).

-- dim_advertiser
-- Grain: one row per advertiser (Season 2 has 5, one campaign each).   Primary key: advertiser_id
-- Source: dataset specification, Table 1 (Liao et al., 2014)
CREATE OR REPLACE TABLE dim_advertiser AS
SELECT * FROM (VALUES
    (1458, 'Chinese vertical e-commerce', 2),
    (3358, 'Software',                    2),
    (3386, 'International e-commerce',    2),
    (3427, 'Oil',                         2),
    (3476, 'Tyre',                        2)
) AS t(advertiser_id, industry, season);

-- dim_exchange
-- Grain: one row per ad exchange.   Primary key: exchange_id
-- Source: dataset specification, section 2.1
CREATE OR REPLACE TABLE dim_exchange AS
SELECT * FROM (VALUES
    (1, 'Tanx',    'Alibaba'),
    (2, 'AdX',     'Google DoubleClick'),
    (3, 'Tencent', 'Tencent'),
    (4, 'Baidu',   'Baidu'),
    (5, 'Youku',   'Youku'),
    (6, 'Amx',     'Google Mobile')
) AS t(exchange_id, exchange_name, owner);

-- dim_slot
-- Grain: one row per ad slot.   Primary key: slot_id
-- Source: stg_ipy_bids. Visibility changes from one impression to the next on 28.5K slots, and
-- size or format on a few dozen, so these attributes live on fact_auction (D30). This table
-- keeps slot-level context only: the most common size and how many attribute combinations
-- the slot was seen with.
CREATE OR REPLACE TABLE dim_slot AS
SELECT
    slot_id,
    mode(slot_width || 'x' || slot_height)                                   AS modal_size_label,
    count(DISTINCT concat_ws('|', slot_width, slot_height, slot_visibility, slot_format))
                                                                             AS attribute_variants,
    count(*)                                                                 AS bids
FROM stg_ipy_bids
GROUP BY slot_id;

-- dim_geo
-- Grain: one row per (region, city) pair observed in the bid log.   Primary key: (region_id, city_id)
-- Source: stg_ipy_bids + region.en.txt / city.en.txt lookups. The lookups do not cover every
-- id (10.8% of bids have an unnamed city), so *_label falls back to the id (D34).
CREATE OR REPLACE TABLE dim_geo AS
WITH pairs AS (
    SELECT region_id, city_id, count(*) AS bids
    FROM stg_ipy_bids
    GROUP BY ALL
)
SELECT
    p.region_id,
    r.name                                                       AS region_name,
    coalesce(r.name, 'Unknown region ' || p.region_id)           AS region_label,
    p.city_id,
    c.name                                                       AS city_name,
    coalesce(c.name, 'Unknown city ' || p.city_id)               AS city_label,
    p.bids
FROM pairs p
LEFT JOIN raw_ipy_region r ON CAST(r.id AS INTEGER) = p.region_id
LEFT JOIN raw_ipy_city   c ON CAST(c.id AS INTEGER) = p.city_id;

-- fact_auction
-- Grain: one row per bid request iPinYou bid on.   Primary key: bid_id
-- Source: stg_ipy_bids LEFT JOIN impressions, clicks and conversions on bid_id.
-- Slot attributes are recorded per auction because visibility varies within a slot (D30).
-- Visibility codes follow the dataset specification (1 above the fold, 2 below, 0 unknown);
-- 255 and the format codes are undocumented and kept as codes.
-- clicked / converted require a won auction: 87 clicks and 13 conversions have no impression
-- row (logging gap, D31) and are flagged separately instead of counting toward CTR or CVR.
-- impression_events / pay_price_events_sum keep the raw-row counts (duplicate impression
-- logs, D27) used only to reproduce the paper's Table 3.
CREATE OR REPLACE TABLE fact_auction AS
SELECT
    b.bid_id,
    b.ts,
    b.date,
    b.hour,
    b.advertiser_id,
    b.exchange_id,
    b.region_id,
    b.city_id,
    b.slot_id,
    b.slot_width,
    b.slot_height,
    b.slot_width || 'x' || b.slot_height   AS size_label,
    b.slot_visibility,
    CASE b.slot_visibility
        WHEN '1'   THEN 'Above the fold'
        WHEN '2'   THEN 'Below the fold'
        WHEN '0'   THEN 'Unknown'
        ELSE 'Undocumented (' || b.slot_visibility || ')'
    END                                    AS visibility_label,
    b.slot_format,
    b.os,
    b.browser,
    b.floor_price,
    b.bid_price,
    i.bid_id IS NOT NULL                   AS won,
    i.pay_price,
    coalesce(i.impression_events, 0)       AS impression_events,
    i.pay_price_events_sum,
    i.bid_id IS NOT NULL AND c.bid_id IS NOT NULL AS clicked,
    i.bid_id IS NOT NULL AND v.bid_id IS NOT NULL AS converted,
    i.bid_id IS NULL AND c.bid_id IS NOT NULL     AS click_without_impression,
    i.bid_id IS NULL AND v.bid_id IS NOT NULL     AS conversion_without_impression
FROM stg_ipy_bids b
LEFT JOIN stg_ipy_imps   i ON i.bid_id = b.bid_id
LEFT JOIN stg_ipy_clicks c ON c.bid_id = b.bid_id
LEFT JOIN stg_ipy_convs  v ON v.bid_id = b.bid_id;

-- mart_ipy_hourly
-- Grain: one row per advertiser x hour x exchange.   Primary key: (advertiser_id, hour_ts, exchange_id)
-- Source: fact_auction. Sums only, so any ratio can be rebuilt as sum / sum (D04).
CREATE OR REPLACE TABLE mart_ipy_hourly AS
SELECT
    advertiser_id,
    date_trunc('hour', ts)                         AS hour_ts,
    exchange_id,
    count(*)                                       AS bids,
    count(*) FILTER (WHERE won)                    AS impressions,
    count(*) FILTER (WHERE clicked)                AS clicks,
    count(*) FILTER (WHERE converted)              AS conversions,
    coalesce(sum(pay_price), 0)                    AS pay_price_sum,
    coalesce(sum(pay_price), 0) / 1000.0           AS spend_fen
FROM fact_auction
GROUP BY ALL;
