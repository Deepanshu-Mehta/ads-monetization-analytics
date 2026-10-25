-- Q5 · Where is competition thin enough for a floor price to matter?
-- View:    Seller (estimated from one buyer's won auctions). The clearing price is the
--          second-highest bid, so its distribution in a segment shows how much competing demand
--          there is. Where many auctions clear low, a reserve price would bind often.
-- Metrics: won auctions, clearing-price percentiles (fen CPM), share clearing below 20/30/50 fen,
--          competition tier (NTILE(4) on median clearing price; 1 = thinnest), and bid headroom.
--          Segments are exchange x visibility with at least 10,000 won auctions (D16).
-- Caveat:  Bid headroom is shown for reference only. iPinYou bid fixed, deliberately high test
--          prices (D23), so (bid - pay) / bid measures its test premium, not the value a real
--          buyer leaves on the table. Negative headroom is floored at zero (D33).
-- Answer:  Competition is thinnest on AdX below the fold: half of its 2.1M won auctions clear
--          under 47 fen and 30.5% under 30 fen, on 15% of spend, which makes it the first segment
--          to test a reserve price on. Tanx above the fold is the deepest market (median 109 fen,
--          13% under 30 fen), where a floor would rarely bind.
-- Decision it informs: which segments a reserve price could target (feeds Q7).

WITH seg AS (
    SELECT
        e.exchange_name || ' · ' || f.visibility_label                 AS segment,
        count(*)                                                        AS won_auctions,
        sum(f.pay_price) / 1000.0                                       AS spend_fen,
        quantile_cont(f.pay_price, [0.10, 0.25, 0.50, 0.75, 0.90])      AS q,
        avg((f.pay_price < 20)::INT)                                    AS share_below_20,
        avg((f.pay_price < 30)::INT)                                    AS share_below_30,
        avg((f.pay_price < 50)::INT)                                    AS share_below_50,
        sum(greatest(f.bid_price - f.pay_price, 0))                     AS bid_headroom_sum,
        sum(f.bid_price)                                                AS won_bid_price_sum
    FROM fact_auction f
    JOIN dim_exchange e USING (exchange_id)
    WHERE f.won
    GROUP BY 1
    HAVING count(*) >= 10000
)
SELECT
    segment,
    won_auctions,
    round(spend_fen / sum(spend_fen) OVER (), 4)                        AS spend_share,
    q[1] AS p10_fen, q[2] AS p25_fen, q[3] AS median_fen, q[4] AS p75_fen, q[5] AS p90_fen,
    round(share_below_20, 3)                                            AS share_below_20,
    round(share_below_30, 3)                                            AS share_below_30,
    round(share_below_50, 3)                                            AS share_below_50,
    ntile(4) OVER (ORDER BY q[3], share_below_30 DESC)                  AS competition_tier,
    round(bid_headroom(bid_headroom_sum, won_bid_price_sum), 3)         AS bid_headroom_reference
FROM seg
ORDER BY competition_tier, median_fen;
