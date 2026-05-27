-- 02: retention
-- Tables: users, activity
-- DuckDB SQL
--
-- definitions:
--   DN retention  = user had any activity in days 1..N after register (rolling)
--   cohort month  = month of registration
--   eligible_dN   = registered at least N days before max(activity_date),
--                   otherwise the user hasn't had the chance to qualify
--
-- creates 2 views at the bottom for Tableau:
--   retention_tableau         long-format, segment by channel / paid-free
--   cohort_retention_tableau  long-format cohort grid


-- ---------- 1. D1 / D7 / D30 (overall) ----------

WITH today AS (SELECT MAX(activity_date) AS d FROM activity),
base AS (
    SELECT u.user_id, u.register_date, today.d AS today FROM users u, today
),
flags AS (
    SELECT
        (register_date <= today - INTERVAL 1  DAY) AS e1,
        (register_date <= today - INTERVAL 7  DAY) AS e7,
        (register_date <= today - INTERVAL 30 DAY) AS e30,
        EXISTS (SELECT 1 FROM activity a WHERE a.user_id = b.user_id
                 AND a.activity_date >  b.register_date
                 AND a.activity_date <= b.register_date + INTERVAL 1  DAY) AS r1,
        EXISTS (SELECT 1 FROM activity a WHERE a.user_id = b.user_id
                 AND a.activity_date >  b.register_date
                 AND a.activity_date <= b.register_date + INTERVAL 7  DAY) AS r7,
        EXISTS (SELECT 1 FROM activity a WHERE a.user_id = b.user_id
                 AND a.activity_date >  b.register_date
                 AND a.activity_date <= b.register_date + INTERVAL 30 DAY) AS r30
    FROM base b
)
SELECT
    ROUND(100.0 * SUM(CASE WHEN e1  AND r1  THEN 1 ELSE 0 END)
                / NULLIF(SUM(CASE WHEN e1  THEN 1 ELSE 0 END), 0), 2) AS d1_pct,
    ROUND(100.0 * SUM(CASE WHEN e7  AND r7  THEN 1 ELSE 0 END)
                / NULLIF(SUM(CASE WHEN e7  THEN 1 ELSE 0 END), 0), 2) AS d7_pct,
    ROUND(100.0 * SUM(CASE WHEN e30 AND r30 THEN 1 ELSE 0 END)
                / NULLIF(SUM(CASE WHEN e30 THEN 1 ELSE 0 END), 0), 2) AS d30_pct
FROM flags;


-- ---------- 2. cohort retention grid ----------
--
-- CAVEAT — cohort maturity:
-- Recent cohorts have sparse / missing cells at high months_since_register
-- because they haven't existed long enough (e.g. the 2025-H2 cohorts have
-- no M12 data yet). Do NOT average retention_pct across cohorts without
-- controlling for cohort age — you'd be averaging fully-observed cells
-- with cells that don't exist yet, which mechanically pulls the number down.
-- Safe comparisons: same-K-month across different cohorts, or whole rows.

-- long format (used by the view at the bottom)
WITH user_cohort AS (
    SELECT user_id, DATE_TRUNC('month', register_date) AS cohort_month FROM users
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS cohort_users FROM user_cohort GROUP BY 1
),
user_active_month AS (
    SELECT DISTINCT user_id, DATE_TRUNC('month', activity_date) AS active_month FROM activity
),
cohort_activity AS (
    SELECT
        uc.cohort_month,
        DATE_DIFF('month', uc.cohort_month, uam.active_month) AS months_since_register,
        COUNT(DISTINCT uam.user_id)                            AS active_users
    FROM user_cohort       uc
    JOIN user_active_month uam USING (user_id)
    WHERE uam.active_month >= uc.cohort_month
    GROUP BY 1, 2
)
SELECT
    ca.cohort_month,
    ca.months_since_register,
    cs.cohort_users,
    ca.active_users,
    ROUND(100.0 * ca.active_users / cs.cohort_users, 2) AS retention_pct
FROM cohort_activity ca
JOIN cohort_size     cs USING (cohort_month)
ORDER BY ca.cohort_month, ca.months_since_register;


-- wide format M0..M6 (easier to eyeball in Excel)
PIVOT (
    WITH uc AS (
        SELECT user_id, DATE_TRUNC('month', register_date) AS cohort_month FROM users
    ),
    cs AS (SELECT cohort_month, COUNT(*) AS cohort_users FROM uc GROUP BY 1),
    uam AS (
        SELECT DISTINCT user_id, DATE_TRUNC('month', activity_date) AS active_month FROM activity
    ),
    ca AS (
        SELECT uc.cohort_month,
               DATE_DIFF('month', uc.cohort_month, uam.active_month) AS months_since_register,
               COUNT(DISTINCT uam.user_id) AS active_users
        FROM uc JOIN uam USING (user_id)
        WHERE uam.active_month >= uc.cohort_month
        GROUP BY 1, 2
    )
    SELECT ca.cohort_month, cs.cohort_users, ca.months_since_register,
           ROUND(100.0 * ca.active_users / cs.cohort_users, 1) AS retention_pct
    FROM ca JOIN cs USING (cohort_month)
    WHERE ca.months_since_register BETWEEN 0 AND 6
)
ON months_since_register IN (0, 1, 2, 3, 4, 5, 6)
USING SUM(retention_pct)
ORDER BY cohort_month;


-- ---------- 3. retention by channel ----------

WITH today AS (SELECT MAX(activity_date) AS d FROM activity),
base AS (
    SELECT u.user_id, u.register_date, u.acquisition_channel, today.d AS today
    FROM users u, today
),
flags AS (
    SELECT
        acquisition_channel,
        (register_date <= today - INTERVAL 1  DAY) AS e1,
        (register_date <= today - INTERVAL 7  DAY) AS e7,
        (register_date <= today - INTERVAL 30 DAY) AS e30,
        EXISTS (SELECT 1 FROM activity a WHERE a.user_id = b.user_id
                 AND a.activity_date >  b.register_date
                 AND a.activity_date <= b.register_date + INTERVAL 1  DAY) AS r1,
        EXISTS (SELECT 1 FROM activity a WHERE a.user_id = b.user_id
                 AND a.activity_date >  b.register_date
                 AND a.activity_date <= b.register_date + INTERVAL 7  DAY) AS r7,
        EXISTS (SELECT 1 FROM activity a WHERE a.user_id = b.user_id
                 AND a.activity_date >  b.register_date
                 AND a.activity_date <= b.register_date + INTERVAL 30 DAY) AS r30
    FROM base b
)
SELECT
    acquisition_channel,
    ROUND(100.0 * SUM(CASE WHEN e1  AND r1  THEN 1 ELSE 0 END)
                / NULLIF(SUM(CASE WHEN e1  THEN 1 ELSE 0 END), 0), 2) AS d1_pct,
    ROUND(100.0 * SUM(CASE WHEN e7  AND r7  THEN 1 ELSE 0 END)
                / NULLIF(SUM(CASE WHEN e7  THEN 1 ELSE 0 END), 0), 2) AS d7_pct,
    ROUND(100.0 * SUM(CASE WHEN e30 AND r30 THEN 1 ELSE 0 END)
                / NULLIF(SUM(CASE WHEN e30 THEN 1 ELSE 0 END), 0), 2) AS d30_pct,
    SUM(CASE WHEN e30 THEN 1 ELSE 0 END) AS n
FROM flags
GROUP BY acquisition_channel
ORDER BY d30_pct DESC;


-- ---------- 4. paid vs free retention ----------

WITH today AS (SELECT MAX(activity_date) AS d FROM activity),
base AS (
    SELECT u.user_id, u.register_date,
           CASE WHEN u.plan_type = 'Free' THEN 'Free' ELSE 'Paid' END AS tier,
           today.d AS today
    FROM users u, today
),
flags AS (
    SELECT
        tier,
        (register_date <= today - INTERVAL 1  DAY) AS e1,
        (register_date <= today - INTERVAL 7  DAY) AS e7,
        (register_date <= today - INTERVAL 30 DAY) AS e30,
        EXISTS (SELECT 1 FROM activity a WHERE a.user_id = b.user_id
                 AND a.activity_date >  b.register_date
                 AND a.activity_date <= b.register_date + INTERVAL 1  DAY) AS r1,
        EXISTS (SELECT 1 FROM activity a WHERE a.user_id = b.user_id
                 AND a.activity_date >  b.register_date
                 AND a.activity_date <= b.register_date + INTERVAL 7  DAY) AS r7,
        EXISTS (SELECT 1 FROM activity a WHERE a.user_id = b.user_id
                 AND a.activity_date >  b.register_date
                 AND a.activity_date <= b.register_date + INTERVAL 30 DAY) AS r30
    FROM base b
)
SELECT
    tier,
    ROUND(100.0 * SUM(CASE WHEN e1  AND r1  THEN 1 ELSE 0 END)
                / NULLIF(SUM(CASE WHEN e1  THEN 1 ELSE 0 END), 0), 2) AS d1_pct,
    ROUND(100.0 * SUM(CASE WHEN e7  AND r7  THEN 1 ELSE 0 END)
                / NULLIF(SUM(CASE WHEN e7  THEN 1 ELSE 0 END), 0), 2) AS d7_pct,
    ROUND(100.0 * SUM(CASE WHEN e30 AND r30 THEN 1 ELSE 0 END)
                / NULLIF(SUM(CASE WHEN e30 THEN 1 ELSE 0 END), 0), 2) AS d30_pct,
    SUM(CASE WHEN e30 THEN 1 ELSE 0 END) AS n
FROM flags
GROUP BY tier
ORDER BY tier;


-- breakdown by all 4 plans (D30 only)
WITH today AS (SELECT MAX(activity_date) AS d FROM activity),
base AS (
    SELECT u.user_id, u.register_date, u.plan_type, today.d AS today FROM users u, today
),
flags AS (
    SELECT plan_type,
           (register_date <= today - INTERVAL 30 DAY) AS e30,
           EXISTS (SELECT 1 FROM activity a WHERE a.user_id = b.user_id
                    AND a.activity_date >  b.register_date
                    AND a.activity_date <= b.register_date + INTERVAL 30 DAY) AS r30
    FROM base b
)
SELECT plan_type,
       SUM(CASE WHEN e30 THEN 1 ELSE 0 END) AS n,
       ROUND(100.0 * SUM(CASE WHEN e30 AND r30 THEN 1 ELSE 0 END)
                   / NULLIF(SUM(CASE WHEN e30 THEN 1 ELSE 0 END), 0), 2) AS d30_pct
FROM flags
GROUP BY plan_type
ORDER BY d30_pct DESC;


-- ---------- 5. views for Tableau ----------

CREATE OR REPLACE VIEW retention_tableau AS
WITH today AS (SELECT MAX(activity_date) AS d FROM activity),
base AS (
    SELECT
        u.user_id,
        u.register_date,
        DATE_TRUNC('month', u.register_date)                       AS cohort_month,
        u.acquisition_channel,
        CASE WHEN u.plan_type = 'Free' THEN 'Free' ELSE 'Paid' END AS user_tier,
        today.d AS today
    FROM users u, today
),
flags AS (
    SELECT b.*,
        (b.register_date <= b.today - INTERVAL 1  DAY) AS e1,
        (b.register_date <= b.today - INTERVAL 7  DAY) AS e7,
        (b.register_date <= b.today - INTERVAL 30 DAY) AS e30,
        EXISTS (SELECT 1 FROM activity a WHERE a.user_id = b.user_id
                 AND a.activity_date >  b.register_date
                 AND a.activity_date <= b.register_date + INTERVAL 1  DAY) AS r1,
        EXISTS (SELECT 1 FROM activity a WHERE a.user_id = b.user_id
                 AND a.activity_date >  b.register_date
                 AND a.activity_date <= b.register_date + INTERVAL 7  DAY) AS r7,
        EXISTS (SELECT 1 FROM activity a WHERE a.user_id = b.user_id
                 AND a.activity_date >  b.register_date
                 AND a.activity_date <= b.register_date + INTERVAL 30 DAY) AS r30
    FROM base b
),
unpivoted AS (
    SELECT cohort_month, acquisition_channel, user_tier,
           1  AS period, e1  AS eligible, r1  AS retained FROM flags
    UNION ALL
    SELECT cohort_month, acquisition_channel, user_tier, 7,  e7,  r7  FROM flags
    UNION ALL
    SELECT cohort_month, acquisition_channel, user_tier, 30, e30, r30 FROM flags
)
SELECT cohort_month, 'overall' AS segment_type, 'all' AS segment, period,
       SUM(CASE WHEN eligible THEN 1 ELSE 0 END) AS cohort_size,
       SUM(CASE WHEN eligible AND retained THEN 1 ELSE 0 END) AS retained_users,
       ROUND(100.0 * SUM(CASE WHEN eligible AND retained THEN 1 ELSE 0 END)
                   / NULLIF(SUM(CASE WHEN eligible THEN 1 ELSE 0 END), 0), 2) AS retention_pct
FROM unpivoted GROUP BY cohort_month, period
UNION ALL
SELECT cohort_month, 'channel', acquisition_channel, period,
       SUM(CASE WHEN eligible THEN 1 ELSE 0 END),
       SUM(CASE WHEN eligible AND retained THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN eligible AND retained THEN 1 ELSE 0 END)
                   / NULLIF(SUM(CASE WHEN eligible THEN 1 ELSE 0 END), 0), 2)
FROM unpivoted GROUP BY cohort_month, acquisition_channel, period
UNION ALL
SELECT cohort_month, 'tier', user_tier, period,
       SUM(CASE WHEN eligible THEN 1 ELSE 0 END),
       SUM(CASE WHEN eligible AND retained THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN eligible AND retained THEN 1 ELSE 0 END)
                   / NULLIF(SUM(CASE WHEN eligible THEN 1 ELSE 0 END), 0), 2)
FROM unpivoted GROUP BY cohort_month, user_tier, period;


CREATE OR REPLACE VIEW cohort_retention_tableau AS
WITH uc AS (
    SELECT user_id, DATE_TRUNC('month', register_date) AS cohort_month FROM users
),
cs AS (SELECT cohort_month, COUNT(*) AS cohort_users FROM uc GROUP BY 1),
uam AS (
    SELECT DISTINCT user_id, DATE_TRUNC('month', activity_date) AS active_month FROM activity
),
ca AS (
    SELECT uc.cohort_month,
           DATE_DIFF('month', uc.cohort_month, uam.active_month) AS months_since_register,
           COUNT(DISTINCT uam.user_id) AS active_users
    FROM uc JOIN uam USING (user_id)
    WHERE uam.active_month >= uc.cohort_month
    GROUP BY 1, 2
)
SELECT ca.cohort_month, ca.months_since_register, cs.cohort_users, ca.active_users,
       ROUND(100.0 * ca.active_users / cs.cohort_users, 2) AS retention_pct
FROM ca JOIN cs USING (cohort_month);


-- ---------- 6. quick insights for weekly note ----------

-- best / worst channel by D30
WITH today AS (SELECT MAX(activity_date) AS d FROM activity),
base AS (
    SELECT u.user_id, u.register_date, u.acquisition_channel, today.d AS today
    FROM users u, today
    WHERE u.register_date <= today.d - INTERVAL 30 DAY
),
ch AS (
    SELECT acquisition_channel, COUNT(*) AS n,
           ROUND(100.0 * SUM(CASE WHEN EXISTS (
               SELECT 1 FROM activity a WHERE a.user_id = b.user_id
                AND a.activity_date >  b.register_date
                AND a.activity_date <= b.register_date + INTERVAL 30 DAY
           ) THEN 1 ELSE 0 END) / COUNT(*), 2) AS d30_pct
    FROM base b GROUP BY acquisition_channel
)
SELECT 'best'  AS label, acquisition_channel, d30_pct, n FROM ch WHERE d30_pct = (SELECT MAX(d30_pct) FROM ch)
UNION ALL
SELECT 'worst', acquisition_channel, d30_pct, n FROM ch WHERE d30_pct = (SELECT MIN(d30_pct) FROM ch);


-- paid vs free D30 gap
WITH today AS (SELECT MAX(activity_date) AS d FROM activity),
base AS (
    SELECT u.user_id, u.register_date,
           CASE WHEN u.plan_type = 'Free' THEN 'Free' ELSE 'Paid' END AS tier, today.d AS today
    FROM users u, today
    WHERE u.register_date <= today.d - INTERVAL 30 DAY
),
t AS (
    SELECT tier,
           ROUND(100.0 * SUM(CASE WHEN EXISTS (
               SELECT 1 FROM activity a WHERE a.user_id = b.user_id
                AND a.activity_date >  b.register_date
                AND a.activity_date <= b.register_date + INTERVAL 30 DAY
           ) THEN 1 ELSE 0 END) / COUNT(*), 2) AS d30_pct
    FROM base b GROUP BY tier
)
SELECT
    MAX(CASE WHEN tier = 'Paid' THEN d30_pct END) AS paid_d30,
    MAX(CASE WHEN tier = 'Free' THEN d30_pct END) AS free_d30,
    MAX(CASE WHEN tier = 'Paid' THEN d30_pct END)
  - MAX(CASE WHEN tier = 'Free' THEN d30_pct END) AS gap_pp
FROM t;
