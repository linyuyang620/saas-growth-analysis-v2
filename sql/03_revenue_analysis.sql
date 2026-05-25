-- 03: revenue
-- Tables: users, subscription
-- DuckDB SQL
--
-- MRR rules:
--   monthly sub  → counts amount in payment month
--   annual sub   → spreads amount/12 across 12 months from payment month
--   only payment_status = 'Success' is counted
--
-- creates 3 Tableau views: v_mrr_trend, v_revenue_by_channel, v_revenue_by_plan


-- ---------- 0. sanity ----------

SELECT
    COUNT(*)                                                          AS total_records,
    SUM(CASE WHEN payment_status = 'Success'  THEN 1 ELSE 0 END)       AS success,
    SUM(CASE WHEN payment_status = 'Failed'   THEN 1 ELSE 0 END)       AS failed,
    SUM(CASE WHEN payment_status = 'Refunded' THEN 1 ELSE 0 END)       AS refunded,
    MIN(payment_date)                                                  AS first_payment,
    MAX(payment_date)                                                  AS last_payment,
    ROUND(SUM(CASE WHEN payment_status = 'Success' THEN amount END), 2) AS total_revenue
FROM subscription;


-- ---------- 1. monthly cash revenue ----------
-- recorded by payment_date, no annual smoothing (for finance reconciliation)

SELECT
    DATE_TRUNC('month', payment_date) AS month,
    COUNT(*)                          AS payments,
    ROUND(SUM(CASE WHEN payment_status = 'Success'  THEN amount END), 2) AS revenue,
    ROUND(SUM(CASE WHEN payment_status = 'Refunded' THEN amount END), 2) AS refunded,
    ROUND(SUM(CASE WHEN payment_status = 'Success'  THEN amount ELSE 0 END)
        - SUM(CASE WHEN payment_status = 'Refunded' THEN amount ELSE 0 END), 2) AS net_revenue
FROM subscription
GROUP BY month
ORDER BY month;


-- ---------- 2. MRR + ARR ----------

WITH active AS (
    SELECT
        DATE_TRUNC('month', payment_date) AS start_month,
        CASE
            WHEN subscription_type = 'Monthly' THEN DATE_TRUNC('month', payment_date)
            WHEN subscription_type = 'Annual'  THEN DATE_TRUNC('month', payment_date) + INTERVAL 11 MONTH
        END AS end_month,
        CASE
            WHEN subscription_type = 'Monthly' THEN amount
            WHEN subscription_type = 'Annual'  THEN amount / 12.0
        END AS monthly_value,
        user_id
    FROM subscription WHERE payment_status = 'Success'
),
calendar AS (
    SELECT DATE_TRUNC('month', d)::DATE AS month
    FROM generate_series(
        (SELECT MIN(start_month) FROM active),
        (SELECT MAX(start_month) FROM active) + INTERVAL 12 MONTH,
        INTERVAL 1 MONTH
    ) AS t(d)
)
SELECT
    c.month,
    COUNT(DISTINCT a.user_id)            AS paying_users,
    ROUND(SUM(a.monthly_value), 2)       AS mrr,
    ROUND(SUM(a.monthly_value) * 12, 2)  AS arr
FROM calendar c
LEFT JOIN active a ON c.month BETWEEN a.start_month AND a.end_month
GROUP BY c.month
ORDER BY c.month;


-- MRR MoM growth
WITH active AS (
    SELECT DATE_TRUNC('month', payment_date) AS start_month,
           CASE
               WHEN subscription_type = 'Monthly' THEN DATE_TRUNC('month', payment_date)
               WHEN subscription_type = 'Annual'  THEN DATE_TRUNC('month', payment_date) + INTERVAL 11 MONTH
           END AS end_month,
           CASE
               WHEN subscription_type = 'Monthly' THEN amount
               WHEN subscription_type = 'Annual'  THEN amount / 12.0
           END AS monthly_value
    FROM subscription WHERE payment_status = 'Success'
),
calendar AS (
    SELECT DATE_TRUNC('month', d)::DATE AS month
    FROM generate_series(
        (SELECT MIN(start_month) FROM active),
        (SELECT MAX(start_month) FROM active) + INTERVAL 12 MONTH,
        INTERVAL 1 MONTH) AS t(d)
),
monthly_mrr AS (
    SELECT c.month, ROUND(SUM(a.monthly_value), 2) AS mrr
    FROM calendar c
    LEFT JOIN active a ON c.month BETWEEN a.start_month AND a.end_month
    GROUP BY c.month
)
SELECT month, mrr,
       LAG(mrr) OVER (ORDER BY month) AS prev_mrr,
       ROUND(100.0 * (mrr - LAG(mrr) OVER (ORDER BY month))
                   / NULLIF(LAG(mrr) OVER (ORDER BY month), 0), 2) AS mom_pct
FROM monthly_mrr
ORDER BY month;


-- ---------- 3. ARPU & ARPPU ----------

-- lifetime values
WITH r AS (SELECT SUM(amount) AS rev FROM subscription WHERE payment_status = 'Success'),
     u AS (
         SELECT COUNT(*) AS total_users,
                SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END) AS paid_users
         FROM users
     )
SELECT u.total_users, u.paid_users,
       ROUND(r.rev, 2)                  AS total_revenue,
       ROUND(r.rev / u.total_users, 2)  AS arpu,
       ROUND(r.rev / u.paid_users,  2)  AS arppu
FROM r CROSS JOIN u;


-- monthly ARPU / ARPPU (running cumulative)
WITH revenue_by_month AS (
    SELECT DATE_TRUNC('month', payment_date) AS month, SUM(amount) AS revenue
    FROM subscription WHERE payment_status = 'Success'
    GROUP BY 1
),
users_by_month AS (
    SELECT DATE_TRUNC('month', register_date) AS month, COUNT(*) AS new_users,
           SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END) AS new_paid_users
    FROM users GROUP BY 1
),
calendar AS (
    SELECT DATE_TRUNC('month', d)::DATE AS month
    FROM generate_series(
        (SELECT MIN(month) FROM users_by_month),
        (SELECT MAX(month) FROM users_by_month),
        INTERVAL 1 MONTH) AS t(d)
)
SELECT c.month,
       SUM(COALESCE(u.new_users, 0))      OVER (ORDER BY c.month) AS cum_users,
       SUM(COALESCE(u.new_paid_users, 0)) OVER (ORDER BY c.month) AS cum_paid_users,
       ROUND(SUM(COALESCE(r.revenue, 0)) OVER (ORDER BY c.month), 2) AS cum_revenue,
       ROUND(SUM(COALESCE(r.revenue, 0)) OVER (ORDER BY c.month)
           / NULLIF(SUM(COALESCE(u.new_users, 0)) OVER (ORDER BY c.month), 0), 2) AS arpu,
       ROUND(SUM(COALESCE(r.revenue, 0)) OVER (ORDER BY c.month)
           / NULLIF(SUM(COALESCE(u.new_paid_users, 0)) OVER (ORDER BY c.month), 0), 2) AS arppu
FROM calendar c
LEFT JOIN revenue_by_month r USING (month)
LEFT JOIN users_by_month   u USING (month)
ORDER BY c.month;


-- ---------- 4. paid conversion ----------

-- overall
SELECT COUNT(*) AS total_users,
       SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END) AS paid_users,
       ROUND(100.0 * SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END)
                   / COUNT(*), 2) AS conversion_pct
FROM users;

-- by register cohort
SELECT DATE_TRUNC('month', register_date) AS register_month,
       COUNT(*) AS users,
       SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END) AS paid,
       ROUND(100.0 * SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END)
                   / COUNT(*), 2) AS conversion_pct
FROM users
GROUP BY register_month
ORDER BY register_month;


-- ---------- 5. revenue by plan ----------

SELECT u.plan_type,
       COUNT(DISTINCT u.user_id) AS users,
       COUNT(DISTINCT s.user_id) AS paying_users,
       ROUND(SUM(CASE WHEN s.payment_status = 'Success' THEN s.amount ELSE 0 END), 2) AS revenue,
       ROUND(100.0 * SUM(CASE WHEN s.payment_status = 'Success' THEN s.amount ELSE 0 END)
                   / NULLIF(SUM(SUM(CASE WHEN s.payment_status = 'Success' THEN s.amount ELSE 0 END)) OVER (), 0), 2)
                                AS revenue_share_pct,
       ROUND(SUM(CASE WHEN s.payment_status = 'Success' THEN s.amount ELSE 0 END)
           / NULLIF(COUNT(DISTINCT s.user_id), 0), 2) AS arppu
FROM users u
LEFT JOIN subscription s ON s.user_id = u.user_id
GROUP BY u.plan_type
ORDER BY revenue DESC;


-- ---------- 6. revenue by channel ----------

WITH user_rev AS (
    SELECT user_id, SUM(amount) AS rev
    FROM subscription WHERE payment_status = 'Success'
    GROUP BY user_id
)
SELECT u.acquisition_channel,
       COUNT(*)                                                            AS users,
       COUNT(ur.user_id)                                                   AS paying_users,
       ROUND(100.0 * COUNT(ur.user_id) / COUNT(*), 2)                       AS conversion_pct,
       ROUND(SUM(COALESCE(ur.rev, 0)), 2)                                  AS revenue,
       ROUND(SUM(COALESCE(ur.rev, 0)) / COUNT(*), 2)                        AS arpu,
       ROUND(SUM(COALESCE(ur.rev, 0)) / NULLIF(COUNT(ur.user_id), 0), 2)    AS arppu,
       ROUND(100.0 * SUM(COALESCE(ur.rev, 0))
                   / SUM(SUM(COALESCE(ur.rev, 0))) OVER (), 2)              AS revenue_share_pct
FROM users u
LEFT JOIN user_rev ur ON ur.user_id = u.user_id
GROUP BY u.acquisition_channel
ORDER BY revenue DESC;


-- ---------- 7. top customers & revenue concentration ----------

-- top 10 by lifetime revenue
SELECT u.user_id, u.country, u.acquisition_channel, u.plan_type, u.company_size,
       ROUND(SUM(s.amount), 2) AS lifetime_revenue,
       COUNT(s.subscription_id) AS payment_count,
       MIN(s.payment_date)      AS first_payment,
       MAX(s.payment_date)      AS last_payment
FROM users u
JOIN subscription s ON s.user_id = u.user_id
WHERE s.payment_status = 'Success'
GROUP BY u.user_id, u.country, u.acquisition_channel, u.plan_type, u.company_size
ORDER BY lifetime_revenue DESC
LIMIT 10;


-- pareto buckets (top 1% / 10% / 20% / 50% / bottom 50%)
WITH user_rev AS (
    SELECT user_id, SUM(amount) AS lifetime_revenue
    FROM subscription WHERE payment_status = 'Success'
    GROUP BY user_id
),
ranked AS (
    SELECT user_id, lifetime_revenue,
           NTILE(100) OVER (ORDER BY lifetime_revenue DESC) AS pct_rank,
           SUM(lifetime_revenue) OVER ()                    AS total_revenue
    FROM user_rev
)
SELECT
    CASE
        WHEN pct_rank = 1   THEN 'Top 1%'
        WHEN pct_rank <= 10 THEN 'Top 10%'
        WHEN pct_rank <= 20 THEN 'Top 20%'
        WHEN pct_rank <= 50 THEN 'Top 50%'
        ELSE                     'Bottom 50%'
    END AS segment,
    COUNT(*) AS users,
    ROUND(SUM(lifetime_revenue), 2) AS revenue,
    ROUND(100.0 * SUM(lifetime_revenue) / MAX(total_revenue), 2) AS share_pct
FROM ranked
GROUP BY segment
ORDER BY MIN(pct_rank);


-- ---------- 8. leaderboards ----------

-- top 3 channels
WITH ur AS (
    SELECT user_id, SUM(amount) AS rev FROM subscription
    WHERE payment_status = 'Success' GROUP BY user_id
)
SELECT u.acquisition_channel, ROUND(SUM(ur.rev), 2) AS revenue
FROM users u JOIN ur ON ur.user_id = u.user_id
GROUP BY u.acquisition_channel
ORDER BY revenue DESC
LIMIT 3;

-- ARPPU by plan
WITH pr AS (
    SELECT u.plan_type, COUNT(DISTINCT s.user_id) AS paying_users, SUM(s.amount) AS revenue
    FROM users u
    JOIN subscription s ON s.user_id = u.user_id AND s.payment_status = 'Success'
    GROUP BY u.plan_type
)
SELECT plan_type, paying_users,
       ROUND(revenue, 2)              AS revenue,
       ROUND(revenue / paying_users, 2) AS arppu
FROM pr
ORDER BY arppu DESC;


-- ---------- 9. views for Tableau ----------

CREATE OR REPLACE VIEW v_mrr_trend AS
WITH active AS (
    SELECT user_id,
           DATE_TRUNC('month', payment_date) AS start_month,
           CASE
               WHEN subscription_type = 'Monthly' THEN DATE_TRUNC('month', payment_date)
               WHEN subscription_type = 'Annual'  THEN DATE_TRUNC('month', payment_date) + INTERVAL 11 MONTH
           END AS end_month,
           CASE
               WHEN subscription_type = 'Monthly' THEN amount
               WHEN subscription_type = 'Annual'  THEN amount / 12.0
           END AS monthly_value
    FROM subscription WHERE payment_status = 'Success'
),
calendar AS (
    SELECT DATE_TRUNC('month', d)::DATE AS month
    FROM generate_series(
        (SELECT MIN(start_month) FROM active),
        (SELECT MAX(start_month) FROM active) + INTERVAL 12 MONTH,
        INTERVAL 1 MONTH) AS t(d)
)
SELECT c.month                                  AS month_start,
       COUNT(DISTINCT a.user_id)                AS paying_users,
       ROUND(SUM(a.monthly_value), 2)           AS mrr,
       ROUND(SUM(a.monthly_value) * 12, 2)      AS arr
FROM calendar c
LEFT JOIN active a ON c.month BETWEEN a.start_month AND a.end_month
GROUP BY c.month;


CREATE OR REPLACE VIEW v_revenue_by_channel AS
WITH ur AS (
    SELECT user_id, SUM(amount) AS rev FROM subscription
    WHERE payment_status = 'Success' GROUP BY user_id
)
SELECT u.acquisition_channel,
       COUNT(*)                                                            AS users,
       COUNT(ur.user_id)                                                   AS paying_users,
       ROUND(100.0 * COUNT(ur.user_id) / COUNT(*), 2)                       AS conversion_pct,
       ROUND(SUM(COALESCE(ur.rev, 0)), 2)                                  AS revenue,
       ROUND(SUM(COALESCE(ur.rev, 0)) / COUNT(*), 2)                        AS arpu,
       ROUND(SUM(COALESCE(ur.rev, 0)) / NULLIF(COUNT(ur.user_id), 0), 2)    AS arppu,
       ROUND(100.0 * SUM(COALESCE(ur.rev, 0))
                   / SUM(SUM(COALESCE(ur.rev, 0))) OVER (), 2)              AS revenue_share_pct
FROM users u
LEFT JOIN ur ON ur.user_id = u.user_id
GROUP BY u.acquisition_channel;


CREATE OR REPLACE VIEW v_revenue_by_plan AS
WITH ur AS (
    SELECT user_id, SUM(amount) AS rev FROM subscription
    WHERE payment_status = 'Success' GROUP BY user_id
)
SELECT u.plan_type,
       COUNT(*)                                                             AS users,
       COUNT(ur.user_id)                                                    AS paying_users,
       ROUND(SUM(COALESCE(ur.rev, 0)), 2)                                   AS revenue,
       ROUND(100.0 * SUM(COALESCE(ur.rev, 0))
                   / SUM(SUM(COALESCE(ur.rev, 0))) OVER (), 2)              AS revenue_share_pct,
       ROUND(SUM(COALESCE(ur.rev, 0)) / NULLIF(COUNT(ur.user_id), 0), 2)    AS arppu
FROM users u
LEFT JOIN ur ON ur.user_id = u.user_id
GROUP BY u.plan_type;
