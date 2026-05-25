-- 01: user growth
-- Tables: users, activity
-- DuckDB SQL


-- ---------- 1. data scope ----------

-- table sizes
SELECT 'users'         AS table_name, COUNT(*) AS row_count FROM users
UNION ALL
SELECT 'activity',     COUNT(*) FROM activity
UNION ALL
SELECT 'subscription', COUNT(*) FROM subscription;

-- date coverage
SELECT
    (SELECT MIN(register_date) FROM users)    AS first_register,
    (SELECT MAX(register_date) FROM users)    AS last_register,
    (SELECT MIN(activity_date) FROM activity) AS first_activity,
    (SELECT MAX(activity_date) FROM activity) AS last_activity;

-- plan + channel mix
SELECT plan_type, COUNT(*) AS users,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM users GROUP BY plan_type ORDER BY users DESC;

SELECT acquisition_channel, COUNT(*) AS users,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM users GROUP BY acquisition_channel ORDER BY users DESC;


-- ---------- 2. DAU ----------

-- daily active users
SELECT activity_date, COUNT(DISTINCT user_id) AS dau
FROM activity
GROUP BY activity_date
ORDER BY activity_date;

-- avg / peak / min DAU in last 30 days
WITH recent AS (
    SELECT activity_date, COUNT(DISTINCT user_id) AS dau
    FROM activity
    WHERE activity_date >= (SELECT MAX(activity_date) FROM activity) - INTERVAL 30 DAY
    GROUP BY activity_date
)
SELECT ROUND(AVG(dau), 0) AS avg_dau_30d,
       MAX(dau)            AS peak_dau,
       MIN(dau)            AS min_dau
FROM recent;

-- top 10 DAU days (spot promo / launch spikes)
SELECT activity_date, COUNT(DISTINCT user_id) AS dau
FROM activity
GROUP BY activity_date
ORDER BY dau DESC
LIMIT 10;


-- ---------- 3. WAU ----------

-- weekly active users
SELECT DATE_TRUNC('week', activity_date) AS week_start,
       COUNT(DISTINCT user_id)           AS wau
FROM activity
GROUP BY week_start
ORDER BY week_start;

-- last 8 weeks
SELECT DATE_TRUNC('week', activity_date) AS week_start,
       COUNT(DISTINCT user_id)           AS wau
FROM activity
WHERE activity_date >= (SELECT MAX(activity_date) FROM activity) - INTERVAL 56 DAY
GROUP BY week_start
ORDER BY week_start;


-- ---------- 4. MAU ----------

-- monthly active users
SELECT DATE_TRUNC('month', activity_date) AS month,
       COUNT(DISTINCT user_id)            AS mau
FROM activity
GROUP BY month
ORDER BY month;

-- MAU MoM growth
WITH monthly AS (
    SELECT DATE_TRUNC('month', activity_date) AS month,
           COUNT(DISTINCT user_id)            AS mau
    FROM activity GROUP BY month
)
SELECT month,
       mau,
       LAG(mau) OVER (ORDER BY month) AS prev_mau,
       ROUND(100.0 * (mau - LAG(mau) OVER (ORDER BY month))
                   / NULLIF(LAG(mau) OVER (ORDER BY month), 0), 2) AS mom_pct
FROM monthly
ORDER BY month;

-- stickiness = avg(daily DAU within month) / MAU
-- benchmark: social ~50%, tool ~20%, B2B SaaS ~10-30%
WITH daily AS (
    SELECT activity_date,
           DATE_TRUNC('month', activity_date) AS month,
           COUNT(DISTINCT user_id)            AS dau
    FROM activity GROUP BY activity_date, month
),
monthly AS (
    SELECT DATE_TRUNC('month', activity_date) AS month,
           COUNT(DISTINCT user_id)            AS mau
    FROM activity GROUP BY month
)
SELECT m.month,
       ROUND(AVG(d.dau), 0) AS avg_dau,
       m.mau,
       ROUND(100.0 * AVG(d.dau) / m.mau, 2) AS stickiness_pct
FROM daily d
JOIN monthly m USING (month)
GROUP BY m.month, m.mau
ORDER BY m.month;


-- ---------- 5. signups ----------

-- daily signups
SELECT register_date, COUNT(*) AS new_users
FROM users
GROUP BY register_date
ORDER BY register_date;

-- monthly signups
SELECT DATE_TRUNC('month', register_date) AS month,
       COUNT(*) AS new_users
FROM users
GROUP BY month
ORDER BY month;

-- monthly signups by channel (pivoted)
SELECT DATE_TRUNC('month', register_date) AS month,
       SUM(CASE WHEN acquisition_channel = 'Organic'      THEN 1 ELSE 0 END) AS organic,
       SUM(CASE WHEN acquisition_channel = 'Social Media' THEN 1 ELSE 0 END) AS social_media,
       SUM(CASE WHEN acquisition_channel = 'Google Ads'   THEN 1 ELSE 0 END) AS google_ads,
       SUM(CASE WHEN acquisition_channel = 'Email'        THEN 1 ELSE 0 END) AS email,
       COUNT(*)                                                              AS total
FROM users
GROUP BY month
ORDER BY month;

-- monthly signups by plan
SELECT DATE_TRUNC('month', register_date) AS month,
       SUM(CASE WHEN plan_type = 'Free'       THEN 1 ELSE 0 END) AS free,
       SUM(CASE WHEN plan_type = 'Basic'      THEN 1 ELSE 0 END) AS basic,
       SUM(CASE WHEN plan_type = 'Pro'        THEN 1 ELSE 0 END) AS pro,
       SUM(CASE WHEN plan_type = 'Enterprise' THEN 1 ELSE 0 END) AS enterprise,
       COUNT(*)                                                  AS total
FROM users
GROUP BY month
ORDER BY month;


-- ---------- 6. cumulative growth ----------

-- daily cumulative users (running total)
WITH daily_new AS (
    SELECT register_date, COUNT(*) AS new_users
    FROM users GROUP BY register_date
)
SELECT register_date,
       new_users,
       SUM(new_users) OVER (ORDER BY register_date
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_users
FROM daily_new
ORDER BY register_date;

-- monthly cumulative + MoM + YoY
-- (YoY may be NULL where < 12 months of history exists — expected)
WITH monthly_new AS (
    SELECT DATE_TRUNC('month', register_date) AS month,
           COUNT(*) AS new_users
    FROM users GROUP BY month
),
with_cum AS (
    SELECT month, new_users,
           SUM(new_users) OVER (ORDER BY month
                                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_users
    FROM monthly_new
)
SELECT month, new_users, cum_users,
       ROUND(100.0 * (new_users - LAG(new_users, 1)  OVER (ORDER BY month))
                   / NULLIF(LAG(new_users, 1)  OVER (ORDER BY month), 0), 2) AS mom_pct,
       ROUND(100.0 * (new_users - LAG(new_users, 12) OVER (ORDER BY month))
                   / NULLIF(LAG(new_users, 12) OVER (ORDER BY month), 0), 2) AS yoy_pct
FROM with_cum
ORDER BY month;

-- cumulative signups by channel (separate curves)
WITH m AS (
    SELECT DATE_TRUNC('month', register_date) AS month,
           acquisition_channel,
           COUNT(*) AS new_users
    FROM users GROUP BY month, acquisition_channel
)
SELECT month, acquisition_channel, new_users,
       SUM(new_users) OVER (PARTITION BY acquisition_channel
                            ORDER BY month
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_users
FROM m
ORDER BY month, acquisition_channel;


-- ---------- 7. headline KPIs (one row, for dashboard cards) ----------

WITH params AS (SELECT MAX(activity_date) AS today FROM activity)
SELECT
    (SELECT COUNT(*) FROM users)                                                AS total_users,
    (SELECT COUNT(*) FROM users WHERE plan_type <> 'Free')                       AS paid_users,
    (SELECT COUNT(DISTINCT user_id) FROM activity
       WHERE activity_date = (SELECT today FROM params))                         AS dau_today,
    (SELECT COUNT(DISTINCT user_id) FROM activity
       WHERE activity_date >  (SELECT today FROM params) - INTERVAL 7 DAY)       AS wau,
    (SELECT COUNT(DISTINCT user_id) FROM activity
       WHERE activity_date >  (SELECT today FROM params) - INTERVAL 30 DAY)      AS mau,
    (SELECT COUNT(*) FROM users
       WHERE register_date > (SELECT today FROM params) - INTERVAL 30 DAY)       AS new_users_30d;
