-- Gate 2 · Grain of every mart
-- Each table holds exactly one row per its stated primary key, and fact_auction holds exactly
-- one row per staged bid.
-- Passes when it returns 0 rows.
WITH dups(table_name, duplicate_keys) AS (
    SELECT 'fact_auction',      count(*) - count(DISTINCT bid_id)                          FROM fact_auction
    UNION ALL SELECT 'fact_conversion',   count(*) - count(DISTINCT (conversion_id, campaign_id)) FROM fact_conversion
    UNION ALL SELECT 'mart_campaign_day', count(*) - count(DISTINCT (campaign_id, day))       FROM mart_campaign_day
    UNION ALL SELECT 'mart_ipy_hourly',   count(*) - count(DISTINCT (advertiser_id, hour_ts, exchange_id)) FROM mart_ipy_hourly
    UNION ALL SELECT 'dim_campaign',      count(*) - count(DISTINCT campaign_id)             FROM dim_campaign
    UNION ALL SELECT 'dim_slot',          count(*) - count(DISTINCT slot_id)                 FROM dim_slot
    UNION ALL SELECT 'dim_geo',           count(*) - count(DISTINCT (region_id, city_id))    FROM dim_geo
    UNION ALL SELECT 'dim_advertiser',    count(*) - count(DISTINCT advertiser_id)           FROM dim_advertiser
    UNION ALL SELECT 'dim_exchange',      count(*) - count(DISTINCT exchange_id)             FROM dim_exchange
    UNION ALL SELECT 'ref_ipinyou_table3', count(*) - count(DISTINCT (advertiser_id, metric)) FROM ref_ipinyou_table3
    UNION ALL SELECT 'fact_auction vs stg_ipy_bids rows',
                     (SELECT count(*) FROM fact_auction) - (SELECT count(*) FROM stg_ipy_bids)
)
SELECT * FROM dups WHERE duplicate_keys <> 0;
