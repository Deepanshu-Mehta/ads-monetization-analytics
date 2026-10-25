-- Q6 · Do floor prices shape outcomes?
-- View:    Seller (estimated from one buyer's bids). The floor (reserve) price was linearly
--          rescaled before release, so it is compared only in buckets, never with bid or paying
--          price directly (63,894 won auctions even record a paying price below the floor value).
-- Method:  Floors are set per exchange: Tanx sends no floor at all, so a plain bucket view would
--          compare Tanx with the others rather than floors with each other. Buckets are therefore
--          read within each exchange.
-- Metrics: bids, win rate (with and without the six never-won slots), CPM (market price) and CTR
--          (Wilson 95%) per exchange x floor bucket.
-- Answer:  Where an exchange sets floors, they lift clearing prices: on Tencent the market price
--          rises from 29 fen (floor 1-10) to 50 (11-50) and 79 fen (51-100), and on AdX the 101+
--          bucket clears at 163 fen against 64-72 below it; Tanx sets no floors. Six Tencent 300x250
--          slots floored at 100 draw 12.4M bids (23% of all bids) and iPinYou never wins one: its
--          fixed bid never clears that floor, so for this buyer they are wasted bid requests.
-- Decision it informs: pricing policy, and for a buyer, which bid requests are not worth answering.

WITH never_won AS (
    SELECT slot_id FROM fact_auction GROUP BY slot_id
    HAVING count(*) >= 100000 AND count(*) FILTER (WHERE won) = 0
),
bucketed AS (
    SELECT
        f.exchange_id,
        CASE WHEN f.floor_price = 0   THEN 0
             WHEN f.floor_price <= 10  THEN 1
             WHEN f.floor_price <= 50  THEN 2
             WHEN f.floor_price <= 100 THEN 3
             ELSE 4 END                                     AS bucket_order,
        f.won, f.clicked, f.pay_price,
        n.slot_id IS NOT NULL                               AS never_won_slot
    FROM fact_auction f
    LEFT JOIN never_won n USING (slot_id)
),
agg AS (
    SELECT
        exchange_id, bucket_order,
        count(*)                                            AS bids,
        count(*) FILTER (WHERE won)                         AS impressions,
        count(*) FILTER (WHERE clicked)                     AS clicks,
        sum(pay_price) FILTER (WHERE won) / 1000.0          AS spend_fen,
        count(*) FILTER (WHERE never_won_slot)              AS never_won_slot_bids
    FROM bucketed
    GROUP BY ALL
)
SELECT
    e.exchange_name,
    ['0 (no floor)', '1-10', '11-50', '51-100', '101+'][a.bucket_order + 1]  AS floor_bucket,
    a.bids::BIGINT                                                         AS bids,
    round(a.bids / sum(a.bids) OVER (), 4)                                 AS share_of_all_bids,
    round(win_rate(a.impressions, a.bids), 4)                              AS win_rate,
    round(win_rate(a.impressions, a.bids - a.never_won_slot_bids), 4)      AS win_rate_excl_never_won_slots,
    round(cpm(a.spend_fen, a.impressions), 2)                              AS cpm_fen,
    CASE WHEN a.clicks >= min_rate_events() THEN round(ctr(a.clicks, a.impressions), 6) END       AS ctr,
    CASE WHEN a.clicks >= min_rate_events() THEN round(wilson_low(a.clicks, a.impressions), 6) END  AS ctr_low,
    CASE WHEN a.clicks >= min_rate_events() THEN round(wilson_high(a.clicks, a.impressions), 6) END AS ctr_high,
    a.never_won_slot_bids::BIGINT                                          AS never_won_slot_bids
FROM agg a
JOIN dim_exchange e USING (exchange_id)
ORDER BY e.exchange_name, a.bucket_order;
