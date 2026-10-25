-- Gate 2 · Referential integrity
-- Every foreign key in the facts and marts resolves to its dimension.
-- Passes when it returns 0 rows.
SELECT 'fact_auction.advertiser_id' AS foreign_key, count(*) AS orphan_rows
FROM fact_auction f ANTI JOIN dim_advertiser d USING (advertiser_id) HAVING count(*) > 0
UNION ALL
SELECT 'fact_auction.exchange_id', count(*) FROM fact_auction f ANTI JOIN dim_exchange d USING (exchange_id) HAVING count(*) > 0
UNION ALL
SELECT 'fact_auction.slot_id', count(*) FROM fact_auction f ANTI JOIN dim_slot d USING (slot_id) HAVING count(*) > 0
UNION ALL
SELECT 'fact_auction.(region_id, city_id)', count(*) FROM fact_auction f ANTI JOIN dim_geo d USING (region_id, city_id) HAVING count(*) > 0
UNION ALL
SELECT 'mart_campaign_day.campaign_id', count(*) FROM mart_campaign_day m ANTI JOIN dim_campaign d USING (campaign_id) HAVING count(*) > 0
UNION ALL
SELECT 'fact_conversion.campaign_id', count(*) FROM fact_conversion c ANTI JOIN dim_campaign d USING (campaign_id) HAVING count(*) > 0;
