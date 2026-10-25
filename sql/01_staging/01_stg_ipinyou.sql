-- Staging layer: iPinYou Season 2 training logs (6-12 Jun 2013).
-- Typed, parsed and, for clicks and conversions, deduplicated to one row per impression.
-- Casts are strict on purpose: a malformed value fails the build instead of becoming NULL (D21).
-- The literal string 'null' in the logs means missing and is converted to NULL.
-- Prices stay in the released units (scaled CPM); unit naming is confirmed in Phase 2.

-- stg_ipy_bids
-- Grain: one row per bid request iPinYou bid on.   Primary key: bid_id (tested in Phase 2)
-- Source: raw_ipy_bid
CREATE OR REPLACE TABLE stg_ipy_bids AS
SELECT
    bid_id,
    strptime(substr(ts_raw, 1, 14), '%Y%m%d%H%M%S')        AS ts,
    CAST(ts AS DATE)                                       AS date,
    hour(ts)                                               AS hour,
    CAST(advertiser_id AS INTEGER)                         AS advertiser_id,
    CAST(ad_exchange AS INTEGER)                           AS exchange_id,
    CAST(region_id AS INTEGER)                             AS region_id,
    CAST(city_id AS INTEGER)                               AS city_id,
    slot_id,
    CAST(slot_width AS INTEGER)                            AS slot_width,
    CAST(slot_height AS INTEGER)                           AS slot_height,
    slot_visibility,
    slot_format,
    CAST(floor_price AS INTEGER)                           AS floor_price,   -- linearly rescaled; bucket only
    CAST(bid_price AS INTEGER)                             AS bid_price,
    creative_id,
    nullif(domain, 'null')                                 AS domain,
    nullif(url, 'null')                                    AS url,
    nullif(anonymous_url, 'null')                          AS anonymous_url,
    user_agent,
    CASE
        WHEN user_agent ILIKE '%android%'                          THEN 'Android'
        WHEN user_agent ILIKE '%iphone%' OR user_agent ILIKE '%ipad%' THEN 'iOS'
        WHEN user_agent ILIKE '%windows%'                          THEN 'Windows'
        WHEN user_agent ILIKE '%mac os%'                           THEN 'macOS'
        WHEN user_agent ILIKE '%linux%'                            THEN 'Linux'
        ELSE 'Other'
    END                                                    AS os,
    CASE
        WHEN user_agent ILIKE '%metasr%'                           THEN 'Sogou'
        WHEN user_agent ILIKE '%360se%' OR user_agent ILIKE '%360ee%' THEN '360'
        WHEN user_agent ILIKE '%maxthon%'                          THEN 'Maxthon'
        WHEN user_agent ILIKE '%chrome%'                           THEN 'Chrome'
        WHEN user_agent ILIKE '%firefox%'                          THEN 'Firefox'
        WHEN user_agent ILIKE '%safari%'                           THEN 'Safari'
        WHEN user_agent ILIKE '%msie%' OR user_agent ILIKE '%trident%' THEN 'IE'
        ELSE 'Other'
    END                                                    AS browser,
    source_day
FROM raw_ipy_bid;

-- stg_ipy_imps
-- Grain: one row per won auction (duplicate impression events collapsed).   Primary key: bid_id
-- Source: raw_ipy_imp. Paying price exists only in this log, not in the bid log.
-- About 45K auctions (0.4%) are logged more than once, mostly seconds apart with the same
-- price (D27). The first event and its price are kept; ties break on the lower price so the
-- result is deterministic. impression_events and pay_price_events_sum keep the raw-row view,
-- which the iPinYou paper's Table 3 uses, for the Phase 2 reconciliation.
CREATE OR REPLACE TABLE stg_ipy_imps AS
WITH typed AS (
    SELECT
        bid_id,
        strptime(substr(ts_raw, 1, 14), '%Y%m%d%H%M%S')    AS ts,
        CAST(advertiser_id AS INTEGER)                     AS advertiser_id,
        CAST(bid_price AS INTEGER)                         AS bid_price,
        CAST(pay_price AS INTEGER)                         AS pay_price,
        CAST(log_type AS INTEGER)                          AS log_type
    FROM raw_ipy_imp
)
SELECT
    bid_id,
    min(ts)                                                AS ts,
    any_value(advertiser_id)                               AS advertiser_id,
    any_value(bid_price)                                   AS bid_price,
    arg_min(pay_price, (ts, pay_price))                    AS pay_price,
    count(*)                                               AS impression_events,
    sum(pay_price)                                         AS pay_price_events_sum,
    max(log_type)                                          AS log_type
FROM typed
GROUP BY bid_id;

-- stg_ipy_clicks
-- Grain: one row per clicked impression (duplicate clicks collapsed).   Primary key: bid_id
-- Source: raw_ipy_clk. click_events keeps the raw count so duplicates stay visible.
CREATE OR REPLACE TABLE stg_ipy_clicks AS
SELECT
    bid_id,
    min(strptime(substr(ts_raw, 1, 14), '%Y%m%d%H%M%S'))   AS first_click_ts,
    count(*)                                               AS click_events,
    any_value(CAST(advertiser_id AS INTEGER))              AS advertiser_id
FROM raw_ipy_clk
GROUP BY bid_id;

-- stg_ipy_convs
-- Grain: one row per converted impression (duplicates collapsed).   Primary key: bid_id
-- Source: raw_ipy_conv.
CREATE OR REPLACE TABLE stg_ipy_convs AS
SELECT
    bid_id,
    min(strptime(substr(ts_raw, 1, 14), '%Y%m%d%H%M%S'))   AS first_conversion_ts,
    count(*)                                               AS conversion_events,
    any_value(CAST(advertiser_id AS INTEGER))              AS advertiser_id
FROM raw_ipy_conv
GROUP BY bid_id;
