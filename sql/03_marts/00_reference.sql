-- Reference data: published benchmark figures used by the gate 2 reconciliation and Q1.

-- ref_ipinyou_table3
-- Grain: one row per advertiser x metric.   Primary key: (advertiser_id, metric)
-- Source: Zhang, Yuan, Wang & Shen (2014), "Real-Time Bidding Benchmarking with iPinYou
-- Dataset", Table 3 (training data, Season 2, 6-12 Jun 2013). decimals is the precision the
-- paper publishes, used to set the comparison tolerance. Counting conventions (D29):
-- impressions, clicks and conversions count impression log rows, duplicates included;
-- cost = sum(paying price) / 1000, in fen; CPM in fen; rates in percent.
CREATE OR REPLACE TABLE ref_ipinyou_table3 AS
WITH wide(advertiser_id, bids, imps, clicks, convs, cost, win_ratio, ctr, cvr, cpm, ecpc) AS (
    VALUES
    (1458, 14701496, 3083056, 2454,   1, 212400, 20.97, 0.080,  0.041, 68.89,  86.55),
    (3358,  3751016, 1742104, 1358, 369, 160943, 46.44, 0.078, 27.172, 92.38, 118.51),
    (3386, 14091931, 2847802, 2076,   0, 219066, 20.20, 0.073,  0.000, 76.92, 105.52),
    (3427, 14032619, 2593765, 1926,   0, 210239, 18.48, 0.074,  0.000, 81.06, 109.16),
    (3476,  6712268, 1970360, 1027,  26, 156088, 29.35, 0.052,  2.532, 79.22, 151.98)
)
SELECT advertiser_id, metric, CAST(value AS DOUBLE) AS paper_value, decimals
FROM (
    UNPIVOT wide ON bids, imps, clicks, convs, cost, win_ratio, ctr, cvr, cpm, ecpc
    INTO NAME metric VALUE value
)
JOIN (VALUES ('bids', 0), ('imps', 0), ('clicks', 0), ('convs', 0), ('cost', 0),
             ('win_ratio', 2), ('ctr', 3), ('cvr', 3), ('cpm', 2), ('ecpc', 2)) AS p(metric, decimals)
USING (metric);
