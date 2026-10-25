-- Marts: iPinYou star schema (auction health, inventory, pricing simulation).
-- Built only after gate 1 (sql/02_test_staging) passes.
-- Price unit: pay_price and bid_price are CPM in the released, scaled units. Zhang et al.
-- (2014) report them in fen; the dataset specification says RMB. The Table 3 reconciliation
-- in gate 2 settles it; spend_fen assumes fen until then.

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
-- Source: stg_ipy_bids. Attributes are the most frequent value per slot; attribute_variants
-- counts distinct width/height/visibility/format combinations. Phase 2 tests that it is 1;
-- if not, those attributes move onto fact_auction.
CREATE OR REPLACE TABLE dim_slot AS
SELECT
    slot_id,
    mode(slot_width)                                                         AS slot_width,
    mode(slot_height)                                                        AS slot_height,
    mode(slot_width || 'x' || slot_height)                                   AS size_label,
    mode(slot_visibility)                                                    AS slot_visibility,
    mode(slot_format)                                                        AS slot_format,
    count(DISTINCT concat_ws('|', slot_width, slot_height, slot_visibility, slot_format))
                                                                             AS attribute_variants,
    count(*)                                                                 AS bids
FROM stg_ipy_bids
GROUP BY slot_id;

-- dim_geo
-- Grain: one row per (region, city) pair observed in the bid log.   Primary key: (region_id, city_id)
-- Source: stg_ipy_bids + region.en.txt / city.en.txt lookups
CREATE OR REPLACE TABLE dim_geo AS
WITH pairs AS (
    SELECT region_id, city_id, count(*) AS bids
    FROM stg_ipy_bids
    GROUP BY ALL
)
SELECT p.region_id, r.name AS region_name, p.city_id, c.name AS city_name, p.bids
FROM pairs p
LEFT JOIN raw_ipy_region r ON CAST(r.id AS INTEGER) = p.region_id
LEFT JOIN raw_ipy_city   c ON CAST(c.id AS INTEGER) = p.city_id;

-- fact_auction
-- Grain: one row per bid request iPinYou bid on.   Primary key: bid_id
-- Source: stg_ipy_bids LEFT JOIN impressions, clicks and conversions on bid_id.
-- won/clicked/converted are flags; impressions, clicks and conversions are already one row
-- per bid_id in staging. impression_events / pay_price_events_sum keep the raw-row counts
-- (duplicate impression logs, D27) used only to reproduce the paper's Table 3.
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
    b.os,
    b.browser,
    b.floor_price,
    b.bid_price,
    i.bid_id IS NOT NULL                   AS won,
    i.pay_price,
    coalesce(i.impression_events, 0)       AS impression_events,
    i.pay_price_events_sum,
    c.bid_id IS NOT NULL                   AS clicked,
    v.bid_id IS NOT NULL                   AS converted
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
