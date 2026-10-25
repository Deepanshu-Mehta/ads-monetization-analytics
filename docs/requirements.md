# Requirements

Who needs what from this project, and how we know it is done. One row per stakeholder question.

> **Note:** The stakeholders are assumed personas for a portfolio project, modelled on an ads-monetization team. They are not real people or a real engagement.

| Stakeholder (assumed) | Question | Decision it drives | KPIs | Cadence | Acceptance criteria |
| :- | :- | :- | :- | :- | :- |
| Head of Ads Monetization | Why did ad revenue move this week? | Where to intervene | Revenue, Q15 bridge effects | Weekly | Bridge effects sum exactly to the revenue change; top 5 movers listed |
| Ads pricing / product manager | Which slots are underpriced? | Floor-price changes | RPM, bid headroom, impressions kept | Monthly | Per-segment simulation with an impressions-kept guardrail |
| Category / sales lead | Which advertisers should we grow or fix? | Account prioritisation | Margin %, volume, quadrant | Weekly | Every campaign above the threshold sits in exactly one quadrant |
| Account management | Who is about to churn? | Outreach list | Last-7-day vs prior-7-day spend | Weekly | List of campaigns with spend down more than 50% |
| Leadership | Is the ads P&L healthy? | Investment and targets | Revenue, margin %, active advertisers, win rate | Weekly | Dashboard page 1; every number from the metric dictionary |
| Analytics | Can we trust these numbers? | Whether to publish | Test results, Table 3 reconciliation | Every run | All tests return 0 rows |

## Scope

- **In scope:** the 16 business questions in `sql/05_analysis/`, the Ads P&L dashboard (4 pages plus definitions), the floor-price sizing model, the insights memo and the A/B test proposal.
- **Out of scope:** real-time pipelines, cloud warehouses, and production orchestration (dbt, Airflow). New ideas go into the README's *Next steps* list (scope frozen on 2026-10-25).

## Data limitations that shape the requirements

| Requirement | Limitation | How it is handled |
| :- | :- | :- |
| Fill rate | The iPinYou bid log only holds requests iPinYou bid on | Win rate, labelled as a fill-rate proxy |
| Advertiser ROAS | Criteo has no order value | Revenue ÷ media cost, labelled as a platform-side proxy |
| Absolute money | Criteo cost and cpo are transformed values | Only ratios and relative changes are reported |
| Category insight | Criteo cat1–cat9 are undisclosed | Behavioural segments, labelled as such |
