-- Metric layer: every KPI is defined once, here, and documented in docs/metric_dictionary.md.
-- Ratios are macros that take sums, so every caller computes sum / sum at its own grain (D04, D35).
-- Views carry the additive base columns next to the ratios: to roll a view up, re-aggregate the
-- base columns and reapply the macro. Never average or sum a ratio column.

-- ---------------------------------------------------------------------------------------------
-- Rules and windows
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE MACRO safe_ratio(numerator, denominator) AS numerator / nullif(denominator, 0);

-- Minimum events before a rate is compared (D03): clicks for CTR, conversions for CVR.
CREATE OR REPLACE MACRO min_rate_events() AS 30;
-- Minimum attributed conversions before a campaign is scored rather than pooled (D17).
CREATE OR REPLACE MACRO min_campaign_conversions() AS 50;

-- Criteo middle weeks: days 7-27 (weeks 1-3). Conversion-dated revenue on day d holds about
-- P(lag <= d) of its steady-state value: 82% on day 7, rising to 95% by day 21, so weekly revenue
-- changes are shown raw and lag-adjusted (D36, D40). Days 28-30 form a short impression week and
-- days 31-60 carry conversions only (D06, D08).
CREATE OR REPLACE MACRO is_middle_day(d) AS d BETWEEN 7 AND 27;
CREATE OR REPLACE MACRO is_middle_week(w) AS w BETWEEN 1 AND 3;

-- ---------------------------------------------------------------------------------------------
-- Ratio definitions
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE MACRO win_rate(impressions, bids) AS safe_ratio(impressions, bids);
CREATE OR REPLACE MACRO ctr(clicks, impressions) AS safe_ratio(clicks, impressions);
CREATE OR REPLACE MACRO cvr(conversions, clicks) AS safe_ratio(conversions, clicks);
CREATE OR REPLACE MACRO cpm(spend, impressions) AS 1000 * safe_ratio(spend, impressions);
CREATE OR REPLACE MACRO ecpc(spend, clicks) AS safe_ratio(spend, clicks);
CREATE OR REPLACE MACRO rpm(spend, bids) AS 1000 * safe_ratio(spend, bids);
CREATE OR REPLACE MACRO bid_headroom(headroom_sum, won_bid_price_sum) AS safe_ratio(headroom_sum, won_bid_price_sum);
CREATE OR REPLACE MACRO margin_pct(revenue, media_cost) AS safe_ratio(revenue - media_cost, revenue);
CREATE OR REPLACE MACRO return_on_media_cost(revenue, media_cost) AS safe_ratio(revenue, media_cost);
CREATE OR REPLACE MACRO attribution_rate(attributed, conversions) AS safe_ratio(attributed, conversions);
CREATE OR REPLACE MACRO avg_cpo(revenue, attributed) AS safe_ratio(revenue, attributed);

-- Wilson 95% interval for k successes in n trials (D03).
CREATE OR REPLACE MACRO wilson_low(k, n) AS
    CASE WHEN n > 0 THEN
        (k / n + pow(1.96, 2) / (2 * n)
         - 1.96 * sqrt((k / n) * (1 - k / n) / n + pow(1.96, 2) / (4 * pow(n, 2))))
        / (1 + pow(1.96, 2) / n)
    END;
CREATE OR REPLACE MACRO wilson_high(k, n) AS
    CASE WHEN n > 0 THEN
        (k / n + pow(1.96, 2) / (2 * n)
         + 1.96 * sqrt((k / n) * (1 - k / n) / n + pow(1.96, 2) / (4 * pow(n, 2))))
        / (1 + pow(1.96, 2) / n)
    END;

-- ---------------------------------------------------------------------------------------------
-- iPinYou (buyer's view). Money in Chinese fen; one auction counted once (D27, D29).
-- ---------------------------------------------------------------------------------------------

-- metrics_ipy_hourly
-- Grain: one row per advertiser x hour x exchange.   Primary key: (advertiser_id, hour_ts, exchange_id)
-- Source: mart_ipy_hourly. Ratios hold at this grain only; roll up the base columns.
CREATE OR REPLACE VIEW metrics_ipy_hourly AS
SELECT
    h.advertiser_id,
    h.hour_ts,
    h.hour_ts::DATE                                         AS date,
    hour(h.hour_ts)                                         AS hour,
    h.exchange_id,
    e.exchange_name,
    h.bids, h.impressions, h.clicks, h.conversions,
    h.spend_fen, h.won_bid_price_sum, h.bid_headroom_sum,
    win_rate(h.impressions, h.bids)                         AS win_rate,
    cpm(h.spend_fen, h.impressions)                         AS cpm_fen,
    ctr(h.clicks, h.impressions)                            AS ctr,
    ecpc(h.spend_fen, h.clicks)                             AS ecpc_fen,
    rpm(h.spend_fen, h.bids)                                AS rpm_fen,
    bid_headroom(h.bid_headroom_sum, h.won_bid_price_sum)   AS bid_headroom
FROM mart_ipy_hourly h
JOIN dim_exchange e USING (exchange_id);

-- metrics_ipy_advertiser
-- Grain: one row per advertiser (5).   Primary key: advertiser_id
-- Source: mart_ipy_hourly. Counts each auction once, so impressions, clicks and spend sit just
-- below the paper's Table 3, which counts duplicate log rows (D27, D29).
CREATE OR REPLACE VIEW metrics_ipy_advertiser AS
WITH base AS (
    SELECT
        advertiser_id,
        sum(bids)                AS bids,
        sum(impressions)         AS impressions,
        sum(clicks)              AS clicks,
        sum(conversions)         AS conversions,
        sum(spend_fen)           AS spend_fen,
        sum(won_bid_price_sum)   AS won_bid_price_sum,
        sum(bid_headroom_sum)    AS bid_headroom_sum
    FROM mart_ipy_hourly
    GROUP BY advertiser_id
)
SELECT
    b.advertiser_id,
    a.industry,
    b.bids, b.impressions, b.clicks, b.conversions,
    b.spend_fen, b.won_bid_price_sum, b.bid_headroom_sum,
    win_rate(b.impressions, b.bids)                         AS win_rate,
    cpm(b.spend_fen, b.impressions)                         AS cpm_fen,
    ctr(b.clicks, b.impressions)                            AS ctr,
    wilson_low(b.clicks, b.impressions)                     AS ctr_low,
    wilson_high(b.clicks, b.impressions)                    AS ctr_high,
    ecpc(b.spend_fen, b.clicks)                             AS ecpc_fen,
    cvr(b.conversions, b.clicks)                            AS cvr,
    rpm(b.spend_fen, b.bids)                                AS rpm_fen,
    bid_headroom(b.bid_headroom_sum, b.won_bid_price_sum)   AS bid_headroom,
    b.clicks >= min_rate_events()                           AS ctr_reportable,
    b.conversions >= min_rate_events()                      AS cvr_reportable
FROM base b
JOIN dim_advertiser a USING (advertiser_id);

-- ---------------------------------------------------------------------------------------------
-- Criteo (intermediary's view). Money in transformed units (_idx): report ratios and changes,
-- not absolute amounts. Media cost by impression day, revenue by conversion day (D13).
-- ---------------------------------------------------------------------------------------------

-- metrics_criteo_day
-- Grain: one row per day (0-60).   Primary key: day
-- Source: mart_campaign_day. Days 31-60 carry conversions only. No margin or CVR here: they
-- would divide conversion-dated revenue by same-day, impression-dated cost or clicks (D14).
CREATE OR REPLACE VIEW metrics_criteo_day AS
WITH base AS (
    SELECT
        day,
        bool_and(in_impression_window)                      AS in_impression_window,
        sum(impressions)                                    AS impressions,
        sum(clicks)                                         AS clicks,
        sum(media_cost_idx)                                 AS media_cost_idx,
        sum(conversions)                                    AS conversions,
        sum(attributed_conversions)                         AS attributed_conversions,
        sum(revenue_idx)                                    AS revenue_idx,
        count(*) FILTER (WHERE impressions > 0)             AS active_campaigns
    FROM mart_campaign_day
    GROUP BY day
)
SELECT
    day,
    day // 7                                                AS week,
    CASE WHEN in_impression_window THEN 'impression window' ELSE 'conversion tail' END AS period,
    is_middle_day(day)                                      AS is_middle_day,
    impressions, clicks, media_cost_idx, conversions, attributed_conversions, revenue_idx,
    CASE WHEN in_impression_window THEN active_campaigns END AS active_campaigns,
    ctr(clicks, impressions)                                AS ctr,
    ecpc(media_cost_idx, clicks)                            AS ecpc_idx,
    attribution_rate(attributed_conversions, conversions)   AS attribution_rate
FROM base;

-- metrics_criteo_week
-- Grain: one row per week (day // 7, weeks 0-8).   Primary key: week
-- Source: mart_campaign_day, dim_campaign. Week 4 has 3 impression days and weeks 5-8 none,
-- so weekly comparisons use the middle weeks (D06, D08). Margin and return on media cost are
-- shown for middle weeks only (D14). New campaigns are blank for week 0, which mixes existing
-- and new campaigns (D05); churn needs a complete current and prior week, so it is shown for
-- weeks 1-3 only.
CREATE OR REPLACE VIEW metrics_criteo_week AS
WITH weeks AS (
    SELECT DISTINCT day // 7 AS week FROM mart_campaign_day
),
campaign_week AS (
    SELECT campaign_id, day // 7 AS week, sum(impressions) AS impressions
    FROM mart_campaign_day
    GROUP BY ALL
),
activity AS (
    SELECT
        w.week,
        count(*) FILTER (WHERE cur.impressions > 0)                                      AS active_campaigns,
        count(*) FILTER (WHERE cur.impressions > 0 AND c.first_day // 7 = w.week)        AS new_campaigns,
        count(*) FILTER (WHERE prev.impressions > 0 AND coalesce(cur.impressions, 0) = 0) AS churned_campaigns
    FROM weeks w
    CROSS JOIN dim_campaign c
    LEFT JOIN campaign_week cur  ON cur.campaign_id = c.campaign_id  AND cur.week = w.week
    LEFT JOIN campaign_week prev ON prev.campaign_id = c.campaign_id AND prev.week = w.week - 1
    GROUP BY w.week
),
base AS (
    SELECT
        day // 7                                            AS week,
        count(DISTINCT day) FILTER (WHERE in_impression_window) AS impression_days,
        sum(impressions)                                    AS impressions,
        sum(clicks)                                         AS clicks,
        sum(media_cost_idx)                                 AS media_cost_idx,
        sum(conversions)                                    AS conversions,
        sum(attributed_conversions)                         AS attributed_conversions,
        sum(revenue_idx)                                    AS revenue_idx
    FROM mart_campaign_day
    GROUP BY ALL
)
SELECT
    b.week,
    7 * b.week                                              AS first_day,
    b.impression_days,
    b.impression_days = 7                                   AS is_complete_week,
    is_middle_week(b.week)                                  AS is_middle_week,
    b.impressions, b.clicks, b.media_cost_idx, b.conversions, b.attributed_conversions, b.revenue_idx,
    ctr(b.clicks, b.impressions)                            AS ctr,
    ecpc(b.media_cost_idx, b.clicks)                        AS ecpc_idx,
    attribution_rate(b.attributed_conversions, b.conversions) AS attribution_rate,
    avg_cpo(b.revenue_idx, b.attributed_conversions)       AS avg_cpo_idx,
    CASE WHEN is_middle_week(b.week) THEN margin_pct(b.revenue_idx, b.media_cost_idx) END           AS margin_pct,
    CASE WHEN is_middle_week(b.week) THEN return_on_media_cost(b.revenue_idx, b.media_cost_idx) END AS return_on_media_cost,
    CASE WHEN b.impression_days > 0 THEN a.active_campaigns END AS active_campaigns,
    CASE WHEN b.week > 0 AND b.impression_days > 0 THEN a.new_campaigns END AS new_campaigns,
    CASE WHEN is_middle_week(b.week) THEN a.churned_campaigns END AS churned_campaigns
FROM base b
JOIN activity a USING (week);

-- metrics_criteo_campaign
-- Grain: one row per campaign over the whole period.   Primary key: campaign_id
-- Source: mart_campaign_day. Revenue includes every conversion day (0-60), so it covers all
-- conversions of the period's impressions and margin is like for like (D36).
-- volume_tier applies the 50-conversion rule (D17); *_reportable apply the 30-event rule (D03).
CREATE OR REPLACE VIEW metrics_criteo_campaign AS
WITH base AS (
    SELECT
        campaign_id,
        sum(impressions)                                    AS impressions,
        sum(clicks)                                         AS clicks,
        sum(media_cost_idx)                                 AS media_cost_idx,
        sum(conversions)                                    AS conversions,
        sum(attributed_conversions)                         AS attributed_conversions,
        sum(revenue_idx)                                    AS revenue_idx
    FROM mart_campaign_day
    GROUP BY campaign_id
)
SELECT
    campaign_id,
    impressions, clicks, media_cost_idx, conversions, attributed_conversions, revenue_idx,
    revenue_idx - media_cost_idx                            AS margin_idx,
    margin_pct(revenue_idx, media_cost_idx)                 AS margin_pct,
    return_on_media_cost(revenue_idx, media_cost_idx)       AS return_on_media_cost,
    ctr(clicks, impressions)                                AS ctr,
    wilson_low(clicks, impressions)                         AS ctr_low,
    wilson_high(clicks, impressions)                        AS ctr_high,
    cvr(conversions, clicks)                                AS cvr,
    ecpc(media_cost_idx, clicks)                            AS ecpc_idx,
    attribution_rate(attributed_conversions, conversions)   AS attribution_rate,
    avg_cpo(revenue_idx, attributed_conversions)            AS avg_cpo_idx,
    clicks >= min_rate_events()                             AS ctr_reportable,
    conversions >= min_rate_events()                        AS cvr_reportable,
    CASE WHEN attributed_conversions >= min_campaign_conversions() THEN 'scored' ELSE 'long tail' END AS volume_tier,
    revenue_idx / sum(revenue_idx) OVER ()                  AS revenue_share,
    row_number() OVER (ORDER BY revenue_idx DESC, campaign_id) AS revenue_rank
FROM base;

-- metrics_criteo_platform
-- Grain: one row per reporting window.   Primary key: reporting_window
-- 'whole period': impression days 0-30 with every conversion they produced (days 0-60).
-- 'middle weeks': impression and conversion days 7-27, a booked-date view (D14).
-- Concentration is measured over the whole period: the top 10% of campaigns by revenue
-- (68 of 675) and the Herfindahl index of revenue shares, on a 0-1 scale.
CREATE OR REPLACE VIEW metrics_criteo_platform AS
WITH windowed AS (
    SELECT 'whole period' AS reporting_window, * FROM mart_campaign_day
    UNION ALL
    SELECT 'middle weeks', * FROM mart_campaign_day WHERE is_middle_day(day)
),
base AS (
    SELECT
        reporting_window,
        count(DISTINCT day) FILTER (WHERE in_impression_window)     AS impression_days,
        sum(impressions)                                            AS impressions,
        sum(clicks)                                                 AS clicks,
        sum(media_cost_idx)                                         AS media_cost_idx,
        sum(conversions)                                            AS conversions,
        sum(attributed_conversions)                                 AS attributed_conversions,
        sum(revenue_idx)                                            AS revenue_idx,
        count(DISTINCT campaign_id) FILTER (WHERE impressions > 0)  AS active_campaigns
    FROM windowed
    GROUP BY reporting_window
),
concentration AS (
    SELECT
        'whole period'                                              AS reporting_window,
        sum(revenue_share) FILTER (WHERE revenue_rank <= ceil(0.1 * campaigns)) AS top_decile_revenue_share,
        sum(pow(revenue_share, 2))                                  AS revenue_hhi
    FROM (SELECT revenue_share, revenue_rank, count(*) OVER () AS campaigns FROM metrics_criteo_campaign)
)
SELECT
    b.reporting_window,
    b.impression_days,
    b.impressions, b.clicks, b.media_cost_idx, b.conversions, b.attributed_conversions, b.revenue_idx,
    b.revenue_idx - b.media_cost_idx                                AS margin_idx,
    margin_pct(b.revenue_idx, b.media_cost_idx)                     AS margin_pct,
    return_on_media_cost(b.revenue_idx, b.media_cost_idx)           AS return_on_media_cost,
    ctr(b.clicks, b.impressions)                                    AS ctr,
    cvr(b.conversions, b.clicks)                                    AS cvr,
    ecpc(b.media_cost_idx, b.clicks)                                AS ecpc_idx,
    attribution_rate(b.attributed_conversions, b.conversions)       AS attribution_rate,
    avg_cpo(b.revenue_idx, b.attributed_conversions)                AS avg_cpo_idx,
    b.active_campaigns,
    c.top_decile_revenue_share,
    c.revenue_hhi
FROM base b
LEFT JOIN concentration c USING (reporting_window);
