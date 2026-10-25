-- Gate 2 · Second-price auction rule
-- A winner should never pay more than it bid. In the released data 1.55% of won auctions do,
-- all for advertisers 3358, 3427 and 3476 at a few fixed bid prices (D33): an artefact of how
-- bids were recorded, not of the auction. The test fails if any advertiser exceeds 5% of its
-- won auctions, if 1458 or 3386 show any, or if the excess exceeds 50 fen CPM.
-- Passes when it returns 0 rows.
SELECT advertiser_id,
       count(*) FILTER (WHERE pay_price > bid_price)                                      AS pay_above_bid,
       round(100.0 * count(*) FILTER (WHERE pay_price > bid_price) / count(*), 2)        AS pct_of_won,
       max(pay_price - bid_price)                                                         AS max_excess
FROM fact_auction
WHERE won
GROUP BY advertiser_id
HAVING count(*) FILTER (WHERE pay_price > bid_price) > 0.05 * count(*)
    OR (advertiser_id IN (1458, 3386) AND count(*) FILTER (WHERE pay_price > bid_price) > 0)
    OR max(pay_price - bid_price) > 50;
