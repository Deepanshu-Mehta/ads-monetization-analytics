-- Gate 2 · fact_auction contract
-- Flags and prices must be internally consistent: a won auction has a paying price and at least
-- one impression event; clicks and conversions only on won auctions (D31); slot attributes
-- recorded on every row (D30).
-- Passes when it returns 0 rows.
WITH c AS (
    SELECT
        count(*) FILTER (WHERE won AND pay_price IS NULL)                         AS won_without_pay_price,
        count(*) FILTER (WHERE NOT won AND pay_price IS NOT NULL)                 AS lost_with_pay_price,
        count(*) FILTER (WHERE won <> (impression_events > 0))                    AS won_vs_impression_events,
        count(*) FILTER (WHERE clicked AND NOT won)                               AS click_on_lost_auction,
        count(*) FILTER (WHERE converted AND NOT won)                             AS conversion_on_lost_auction,
        count(*) FILTER (WHERE size_label IS NULL OR slot_visibility IS NULL OR slot_format IS NULL) AS missing_slot_attributes,
        count(*) FILTER (WHERE bid_price IS NULL OR bid_price <= 0)               AS missing_or_zero_bid
    FROM fact_auction
)
SELECT check_name, value
FROM c
UNPIVOT (value FOR check_name IN (won_without_pay_price, lost_with_pay_price, won_vs_impression_events,
                                  click_on_lost_auction, conversion_on_lost_auction,
                                  missing_slot_attributes, missing_or_zero_bid))
WHERE value > 0;
