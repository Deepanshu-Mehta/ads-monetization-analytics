-- Q2 · When is competition highest?
-- View:    Buyer (iPinYou). Competition shows up as a higher market price (the second-highest
--          bid, i.e. CPM paid) and, for a buyer with fixed bids, a lower win rate.
-- Metrics: bids, impressions, win rate, CPM (market price) per hour, plus a 3-hour rolling CPM
--          computed sum ÷ sum over a RANGE window, so busy hours weigh more and a missing hour
--          cannot stretch the window (D04). One row per advertiser (and all advertisers) x hour.
-- Caveat:  Seven days give one observation per weekday, so read patterns by hour of day and by
--          date only as a sanity check (D18). The 22:00 hour on 10 Jun is a bid-volume spike (D31).
-- Answer:  Competition peaks at midnight: across advertisers the 00:00 market price is 94.8 fen,
--          46% above the 02:00 trough of 65.0 fen, and even the cheapest date at 00:00 (76.4 fen)
--          costs more than the dearest date at 02:00 (71.6 fen). The pattern fits daily budgets
--          resetting at midnight (a hypothesis, not tested here); 02:00-05:00 is the cheapest window.
-- Decision it informs: dayparting and budget pacing.

WITH hourly AS (
    SELECT CAST(advertiser_id AS VARCHAR) AS advertiser, hour_ts,
           sum(bids) AS bids, sum(impressions) AS impressions, sum(spend_fen) AS spend_fen
    FROM metrics_ipy_hourly
    GROUP BY ALL
    UNION ALL
    SELECT 'All advertisers', hour_ts, sum(bids), sum(impressions), sum(spend_fen)
    FROM metrics_ipy_hourly
    GROUP BY ALL
)
SELECT
    advertiser,
    hour_ts,
    hour_ts::DATE                                                AS date,
    hour(hour_ts)                                                AS hour,
    bids::BIGINT                                                 AS bids,
    impressions::BIGINT                                          AS impressions,
    round(win_rate(impressions, bids), 4)                        AS win_rate,
    round(cpm(spend_fen, impressions), 2)                        AS cpm_fen,
    round(cpm(sum(spend_fen) OVER w, sum(impressions) OVER w), 2) AS cpm_fen_rolling_3h,
    round(win_rate(sum(impressions) OVER w, sum(bids) OVER w), 4) AS win_rate_rolling_3h
FROM hourly
WINDOW w AS (PARTITION BY advertiser ORDER BY hour_ts
             RANGE BETWEEN INTERVAL 2 HOUR PRECEDING AND CURRENT ROW)
ORDER BY advertiser, hour_ts;
