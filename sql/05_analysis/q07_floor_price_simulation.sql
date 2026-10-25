-- Q7 · What would raising the floor do, segment by segment?
-- View:    Seller (estimated from one buyer's won auctions; D41).
-- Method:  A floor F binds on auctions that cleared below it (pay < F). Each such auction either
--          still sells, at F (the winner's bid was at least F), or goes unsold. With retention r =
--          the share of affected auctions that still sell:
--              revenue(F, r)  = revenue from unaffected auctions + r x affected auctions x F
--              impressions(r) = 1 - (1 - r) x affected share
--              break-even r*  = affected auctions' current revenue / (affected auctions x F)
--          A floor pays off only if more than r* of the auctions it touches still clear.
--          iPinYou's recorded bids cannot set r: they are fixed test bids (D23), and using them
--          keeps 100% of impressions up to a 230-fen floor at +236% revenue (D41). They appear only
--          as a labelled reference. Retention scenarios are 50 / 70 / 90%, base 70%.
--          Won auctions are split into random halves by hash(bid_id): each segment's floor is chosen
--          on the fit half (highest base-case revenue with at least 90% of impressions kept, D09,
--          D15) and every figure below is from the holdout half. Segments are exchange x visibility
--          with at least 10,000 won auctions in the fit half (D16). Floors 0-200 fen CPM, step 5.
-- Output:  one row per segment x floor (the curves for the Excel model); is_chosen marks the floor.
-- Answer:  Floors near each segment's 30th-percentile clearing price (30-80 fen) lift revenue by
--          3.4% across all eight segments if 70% of the auctions they touch still clear, keeping 92%
--          of impressions; they break even at 44-56% retention, and at 50% the gain is only 0.2%.
--          The 90% impressions guardrail, not revenue, sets every floor. Lowest break-even: Tencent
--          (50 fen, 44%) and AdX unknown-visibility (55 fen, 44%); AdX below the fold, the thinnest
--          market in Q5, gains 3.3% at a 30-fen floor (break-even 46%). Holdout matches fit within
--          0.02 points. The result hinges on buyer response, which only an A/B test can measure.
-- Decision it informs: opportunity sizing (Excel model) and the A/B test's target segments.

WITH won AS (
    SELECT
        e.exchange_name || ' · ' || f.visibility_label                  AS segment,
        CASE WHEN hash(f.bid_id) % 2 = 0 THEN 'fit' ELSE 'holdout' END   AS half,
        f.pay_price, f.bid_price,
        count(*)                                                         AS n
    FROM fact_auction f
    JOIN dim_exchange e USING (exchange_id)
    WHERE f.won
    GROUP BY ALL
),
floors AS (SELECT range AS floor_fen FROM range(0, 201, 5)),
sim AS (
    SELECT
        w.half, w.segment, fl.floor_fen,
        sum(w.n)                                                         AS auctions,
        sum(w.n * w.pay_price)                                           AS base_pay,
        coalesce(sum(w.n) FILTER (WHERE w.pay_price < fl.floor_fen), 0)  AS affected,
        coalesce(sum(w.n * w.pay_price) FILTER (WHERE w.pay_price < fl.floor_fen), 0) AS affected_pay,
        coalesce(sum(w.n) FILTER (WHERE w.pay_price < fl.floor_fen AND w.bid_price >= fl.floor_fen), 0) AS affected_bid_clears
    FROM won w CROSS JOIN floors fl
    GROUP BY ALL
),
scored AS (
    SELECT *,
        affected / auctions                                              AS affected_share,
        safe_ratio(affected_pay, affected * floor_fen)                   AS breakeven_retention,
        (base_pay - affected_pay + 0.5 * affected * floor_fen) / base_pay - 1 AS revenue_change_r50,
        (base_pay - affected_pay + 0.7 * affected * floor_fen) / base_pay - 1 AS revenue_change_r70,
        (base_pay - affected_pay + 0.9 * affected * floor_fen) / base_pay - 1 AS revenue_change_r90,
        1 - 0.5 * affected / auctions                                    AS imps_kept_r50,
        1 - 0.3 * affected / auctions                                    AS imps_kept_r70,
        1 - 0.1 * affected / auctions                                    AS imps_kept_r90,
        safe_ratio(affected_bid_clears, affected)                        AS recorded_bid_retention
    FROM sim
),
chosen AS (
    SELECT segment, floor_fen, revenue_change_r70 AS fit_revenue_change_r70
    FROM scored
    WHERE half = 'fit' AND auctions >= 10000 AND imps_kept_r70 >= 0.90
    QUALIFY row_number() OVER (PARTITION BY segment ORDER BY revenue_change_r70 DESC, floor_fen) = 1
)
SELECT
    s.segment,
    s.floor_fen,
    c.floor_fen IS NOT NULL                                              AS is_chosen,
    s.auctions::BIGINT                                                   AS holdout_auctions,
    round(s.affected_share, 4)                                           AS affected_share,
    round(s.breakeven_retention, 3)                                      AS breakeven_retention,
    round(s.revenue_change_r50, 4)                                       AS revenue_change_r50,
    round(s.revenue_change_r70, 4)                                       AS revenue_change_r70,
    round(s.revenue_change_r90, 4)                                       AS revenue_change_r90,
    round(s.imps_kept_r50, 4)                                            AS imps_kept_r50,
    round(s.imps_kept_r70, 4)                                            AS imps_kept_r70,
    round(s.imps_kept_r90, 4)                                            AS imps_kept_r90,
    round(c.fit_revenue_change_r70, 4)                                   AS fit_revenue_change_r70,
    round(s.recorded_bid_retention, 3)                                   AS recorded_bid_retention_reference,
    round(s.base_pay / 1000.0 / 100, 2)                                  AS holdout_spend_rmb
FROM scored s
LEFT JOIN chosen c ON c.segment = s.segment AND c.floor_fen = s.floor_fen
WHERE s.half = 'holdout' AND s.segment IN (SELECT segment FROM chosen)
ORDER BY s.segment, s.floor_fen;
