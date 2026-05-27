-- 04: growth funnel  (register → activate → retain → pay → renew)
-- Tables: users, activity, subscription
-- DuckDB SQL
--
-- definitions (kept consistent across this file):
--   eligible  = registered at least 30 days before max(activity_date)
--   activated = >= 3 activities in first 7 days  (the activation window)
--   retained  = any activity in days 8..30       (POST-activation retention)
--   paid      = current plan_type <> 'Free'
--   renewed   = >= 2 successful payments
--               (subscription table has no renewal_count column;
--                this is the standard equivalent)
--
-- Why "retained = days 8..30" and not "days 1..30":
--   If we used 1..30, any user activated (>=3 events in week 1) would trivially
--   satisfy "any activity in 1..30" → Activated → Retained = 100% by construction,
--   which is not a real conversion. Using 8..30 makes Retained measure
--   "did the user actually come back after the activation burst?".
--   Note: the standalone D30 retention metric in section 3 still uses 1..30
--   (the general rolling-D30 metric); only the funnel uses 8..30.
--
-- creates 4 Tableau views at the bottom


-- ---------- 1. signups ----------

SELECT COUNT(*) AS total_registered FROM users;

-- monthly with running total
SELECT DATE_TRUNC('month', register_date) AS month,
       COUNT(*) AS new_users,
       SUM(COUNT(*)) OVER (ORDER BY DATE_TRUNC('month', register_date)
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_users
FROM users
GROUP BY month
ORDER BY month;

-- channel mix
SELECT acquisition_channel, COUNT(*) AS users,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_pct
FROM users GROUP BY acquisition_channel ORDER BY users DESC;

-- plan mix
SELECT plan_type, COUNT(*) AS users,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_pct
FROM users GROUP BY plan_type ORDER BY users DESC;


-- ---------- 2. activation ----------

-- overall activation rate
WITH today AS (SELECT MAX(activity_date) AS d FROM activity),
eligible AS (
    SELECT u.user_id, u.register_date
    FROM users u, today
    WHERE u.register_date <= today.d - INTERVAL 30 DAY
),
activated AS (
    SELECT e.user_id
    FROM eligible e
    JOIN activity a
      ON a.user_id = e.user_id
     AND a.activity_date >= e.register_date
     AND a.activity_date <= e.register_date + INTERVAL 7 DAY
    GROUP BY e.user_id
    HAVING COUNT(*) >= 3
)
SELECT
    (SELECT COUNT(*) FROM eligible)  AS eligible_users,
    (SELECT COUNT(*) FROM activated) AS activated_users,
    ROUND(100.0 * (SELECT COUNT(*) FROM activated)
                / NULLIF((SELECT COUNT(*) FROM eligible), 0), 2) AS activation_pct;


-- by channel
WITH today AS (SELECT MAX(activity_date) AS d FROM activity),
eligible AS (
    SELECT u.user_id, u.register_date, u.acquisition_channel
    FROM users u, today
    WHERE u.register_date <= today.d - INTERVAL 30 DAY
),
acts AS (
    SELECT e.user_id, COUNT(a.activity_id) AS cnt
    FROM eligible e
    LEFT JOIN activity a
      ON a.user_id = e.user_id
     AND a.activity_date >= e.register_date
     AND a.activity_date <= e.register_date + INTERVAL 7 DAY
    GROUP BY e.user_id
)
SELECT e.acquisition_channel,
       COUNT(*) AS users,
       SUM(CASE WHEN acts.cnt >= 3 THEN 1 ELSE 0 END) AS activated,
       ROUND(100.0 * SUM(CASE WHEN acts.cnt >= 3 THEN 1 ELSE 0 END)
                   / COUNT(*), 2) AS activation_pct
FROM eligible e
JOIN acts USING (user_id)
GROUP BY e.acquisition_channel
ORDER BY activation_pct DESC;


-- by plan
WITH today AS (SELECT MAX(activity_date) AS d FROM activity),
eligible AS (
    SELECT u.user_id, u.register_date, u.plan_type
    FROM users u, today
    WHERE u.register_date <= today.d - INTERVAL 30 DAY
),
acts AS (
    SELECT e.user_id, COUNT(a.activity_id) AS cnt
    FROM eligible e
    LEFT JOIN activity a
      ON a.user_id = e.user_id
     AND a.activity_date >= e.register_date
     AND a.activity_date <= e.register_date + INTERVAL 7 DAY
    GROUP BY e.user_id
)
SELECT e.plan_type,
       COUNT(*) AS users,
       SUM(CASE WHEN acts.cnt >= 3 THEN 1 ELSE 0 END) AS activated,
       ROUND(100.0 * SUM(CASE WHEN acts.cnt >= 3 THEN 1 ELSE 0 END)
                   / COUNT(*), 2) AS activation_pct
FROM eligible e
JOIN acts USING (user_id)
GROUP BY e.plan_type
ORDER BY activation_pct DESC;


-- ---------- 3. retention (30-day) ----------

-- overall
WITH today AS (SELECT MAX(activity_date) AS d FROM activity),
eligible AS (
    SELECT u.user_id, u.register_date FROM users u, today
    WHERE u.register_date <= today.d - INTERVAL 30 DAY
),
retained AS (
    SELECT DISTINCT e.user_id
    FROM eligible e
    JOIN activity a
      ON a.user_id = e.user_id
     AND a.activity_date >  e.register_date
     AND a.activity_date <= e.register_date + INTERVAL 30 DAY
)
SELECT
    (SELECT COUNT(*) FROM eligible) AS eligible_users,
    (SELECT COUNT(*) FROM retained) AS retained_users,
    ROUND(100.0 * (SELECT COUNT(*) FROM retained)
                / NULLIF((SELECT COUNT(*) FROM eligible), 0), 2) AS retention_pct;


-- by channel
WITH today AS (SELECT MAX(activity_date) AS d FROM activity),
eligible AS (
    SELECT u.user_id, u.register_date, u.acquisition_channel FROM users u, today
    WHERE u.register_date <= today.d - INTERVAL 30 DAY
)
SELECT acquisition_channel,
       COUNT(*) AS users,
       SUM(CASE WHEN EXISTS (
           SELECT 1 FROM activity a WHERE a.user_id = e.user_id
            AND a.activity_date >  e.register_date
            AND a.activity_date <= e.register_date + INTERVAL 30 DAY
       ) THEN 1 ELSE 0 END) AS retained,
       ROUND(100.0 * SUM(CASE WHEN EXISTS (
           SELECT 1 FROM activity a WHERE a.user_id = e.user_id
            AND a.activity_date >  e.register_date
            AND a.activity_date <= e.register_date + INTERVAL 30 DAY
       ) THEN 1 ELSE 0 END) / COUNT(*), 2) AS retention_pct
FROM eligible e
GROUP BY acquisition_channel
ORDER BY retention_pct DESC;


-- activated vs not-activated: does activation predict 30-day retention?
WITH today AS (SELECT MAX(activity_date) AS d FROM activity),
eligible AS (
    SELECT u.user_id, u.register_date FROM users u, today
    WHERE u.register_date <= today.d - INTERVAL 30 DAY
),
labeled AS (
    SELECT e.user_id,
           (SELECT COUNT(*) FROM activity a WHERE a.user_id = e.user_id
             AND a.activity_date >= e.register_date
             AND a.activity_date <= e.register_date + INTERVAL 7 DAY) >= 3 AS is_activated,
           EXISTS (SELECT 1 FROM activity a WHERE a.user_id = e.user_id
                    AND a.activity_date >  e.register_date
                    AND a.activity_date <= e.register_date + INTERVAL 30 DAY) AS retained
    FROM eligible e
)
SELECT CASE WHEN is_activated THEN 'Activated' ELSE 'Not Activated' END AS segment,
       COUNT(*) AS users,
       SUM(CASE WHEN retained THEN 1 ELSE 0 END) AS retained,
       ROUND(100.0 * SUM(CASE WHEN retained THEN 1 ELSE 0 END) / COUNT(*), 2) AS retention_pct
FROM labeled
GROUP BY is_activated
ORDER BY is_activated DESC;


-- ---------- 4. paid conversion ----------

-- overall
SELECT COUNT(*) AS total_users,
       SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END) AS paid_users,
       ROUND(100.0 * SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END)
                   / COUNT(*), 2) AS paid_pct
FROM users;

-- by channel
SELECT acquisition_channel,
       COUNT(*) AS users,
       SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END) AS paid,
       ROUND(100.0 * SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END)
                   / COUNT(*), 2) AS paid_pct
FROM users
GROUP BY acquisition_channel
ORDER BY paid_pct DESC;

-- ARPU / ARPPU by plan
WITH ur AS (
    SELECT user_id, SUM(amount) AS rev FROM subscription
    WHERE payment_status = 'Success' GROUP BY user_id
)
SELECT u.plan_type,
       COUNT(*) AS users,
       COUNT(ur.user_id) AS paying_users,
       ROUND(SUM(COALESCE(ur.rev, 0)) / COUNT(*), 2)                       AS arpu,
       ROUND(SUM(COALESCE(ur.rev, 0)) / NULLIF(COUNT(ur.user_id), 0), 2)    AS arppu
FROM users u
LEFT JOIN ur ON ur.user_id = u.user_id
GROUP BY u.plan_type
ORDER BY arppu DESC NULLS LAST;

-- activated vs not: does activation predict payment?
WITH today AS (SELECT MAX(activity_date) AS d FROM activity),
eligible AS (
    SELECT u.user_id, u.register_date, u.plan_type FROM users u, today
    WHERE u.register_date <= today.d - INTERVAL 30 DAY
),
labeled AS (
    SELECT e.user_id, e.plan_type,
           (SELECT COUNT(*) FROM activity a WHERE a.user_id = e.user_id
             AND a.activity_date >= e.register_date
             AND a.activity_date <= e.register_date + INTERVAL 7 DAY) >= 3 AS is_activated
    FROM eligible e
)
SELECT CASE WHEN is_activated THEN 'Activated' ELSE 'Not Activated' END AS segment,
       COUNT(*) AS users,
       SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END) AS paid,
       ROUND(100.0 * SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END)
                   / COUNT(*), 2) AS paid_pct
FROM labeled
GROUP BY is_activated
ORDER BY is_activated DESC;


-- ---------- 5. renewal ----------

-- overall
WITH paid AS (
    SELECT user_id, COUNT(*) AS pay_cnt
    FROM subscription WHERE payment_status = 'Success'
    GROUP BY user_id
)
SELECT COUNT(*) AS paying_users,
       SUM(CASE WHEN pay_cnt >= 2 THEN 1 ELSE 0 END) AS renewed,
       ROUND(100.0 * SUM(CASE WHEN pay_cnt >= 2 THEN 1 ELSE 0 END)
                   / COUNT(*), 2) AS renewal_pct,
       ROUND(AVG(pay_cnt), 2) AS avg_payments
FROM paid;

-- by plan
WITH paid AS (
    SELECT user_id, COUNT(*) AS pay_cnt FROM subscription
    WHERE payment_status = 'Success' GROUP BY user_id
)
SELECT u.plan_type,
       COUNT(*) AS paying_users,
       SUM(CASE WHEN p.pay_cnt >= 2 THEN 1 ELSE 0 END) AS renewed,
       ROUND(100.0 * SUM(CASE WHEN p.pay_cnt >= 2 THEN 1 ELSE 0 END)
                   / COUNT(*), 2) AS renewal_pct,
       ROUND(AVG(p.pay_cnt), 2) AS avg_payments
FROM users u
JOIN paid p ON p.user_id = u.user_id
GROUP BY u.plan_type
ORDER BY renewal_pct DESC;

-- by channel
WITH paid AS (
    SELECT user_id, COUNT(*) AS pay_cnt FROM subscription
    WHERE payment_status = 'Success' GROUP BY user_id
)
SELECT u.acquisition_channel,
       COUNT(*) AS paying_users,
       SUM(CASE WHEN p.pay_cnt >= 2 THEN 1 ELSE 0 END) AS renewed,
       ROUND(100.0 * SUM(CASE WHEN p.pay_cnt >= 2 THEN 1 ELSE 0 END)
                   / COUNT(*), 2) AS renewal_pct
FROM users u
JOIN paid p ON p.user_id = u.user_id
GROUP BY u.acquisition_channel
ORDER BY renewal_pct DESC;

-- renewal by lifetime-value bucket (do whales renew more?)
WITH paid AS (
    SELECT user_id, COUNT(*) AS pay_cnt, SUM(amount) AS lifetime_rev
    FROM subscription WHERE payment_status = 'Success'
    GROUP BY user_id
),
b AS (
    SELECT *, NTILE(10) OVER (ORDER BY lifetime_rev DESC) AS decile FROM paid
)
SELECT CASE
           WHEN decile = 1  THEN 'Top 10% (whales)'
           WHEN decile <= 5 THEN 'Top 11-50% (mid)'
           ELSE                  'Bottom 50% (tail)'
       END AS value_segment,
       COUNT(*) AS users,
       ROUND(AVG(lifetime_rev), 2) AS avg_lifetime_rev,
       SUM(CASE WHEN pay_cnt >= 2 THEN 1 ELSE 0 END) AS renewed,
       ROUND(100.0 * SUM(CASE WHEN pay_cnt >= 2 THEN 1 ELSE 0 END)
                   / COUNT(*), 2) AS renewal_pct
FROM b
GROUP BY value_segment
ORDER BY MIN(decile);


-- ---------- 6. funnel summary ----------
-- 5 stages, nested: each stage is a subset of the previous

WITH today AS (SELECT MAX(activity_date) AS d FROM activity),
eligible AS (
    SELECT u.* FROM users u, today
    WHERE u.register_date <= today.d - INTERVAL 30 DAY
),
flags AS (
    SELECT e.user_id,
           (SELECT COUNT(*) FROM activity a WHERE a.user_id = e.user_id
             AND a.activity_date >= e.register_date
             AND a.activity_date <= e.register_date + INTERVAL 7 DAY) >= 3 AS is_activated,
           EXISTS (SELECT 1 FROM activity a WHERE a.user_id = e.user_id
                    AND a.activity_date >  e.register_date + INTERVAL 7  DAY
                    AND a.activity_date <= e.register_date + INTERVAL 30 DAY) AS is_retained,
           (e.plan_type <> 'Free') AS is_paid,
           (SELECT COUNT(*) FROM subscription s WHERE s.user_id = e.user_id
             AND s.payment_status = 'Success') >= 2 AS is_renewed
    FROM eligible e
),
sc AS (
    SELECT
        COUNT(*) AS registered,
        SUM(CASE WHEN is_activated                                                       THEN 1 ELSE 0 END) AS activated,
        SUM(CASE WHEN is_activated AND is_retained                                       THEN 1 ELSE 0 END) AS retained,
        SUM(CASE WHEN is_activated AND is_retained AND is_paid                           THEN 1 ELSE 0 END) AS paid,
        SUM(CASE WHEN is_activated AND is_retained AND is_paid AND is_renewed            THEN 1 ELSE 0 END) AS renewed
    FROM flags
)
SELECT stage, users, step_pct, overall_pct FROM (
    SELECT 1 AS ord, 'Registered' AS stage, registered AS users, 100.0 AS step_pct, 100.0 AS overall_pct FROM sc
    UNION ALL SELECT 2, 'Activated', activated,
        ROUND(100.0 * activated / registered, 2),
        ROUND(100.0 * activated / registered, 2) FROM sc
    UNION ALL SELECT 3, 'Retained', retained,
        ROUND(100.0 * retained / NULLIF(activated, 0), 2),
        ROUND(100.0 * retained / registered, 2) FROM sc
    UNION ALL SELECT 4, 'Paid', paid,
        ROUND(100.0 * paid / NULLIF(retained, 0), 2),
        ROUND(100.0 * paid / registered, 2) FROM sc
    UNION ALL SELECT 5, 'Renewed', renewed,
        ROUND(100.0 * renewed / NULLIF(paid, 0), 2),
        ROUND(100.0 * renewed / registered, 2) FROM sc
) ORDER BY ord;


-- ---------- 7. views for Tableau ----------

CREATE OR REPLACE VIEW v_funnel_summary AS
WITH today AS (SELECT MAX(activity_date) AS d FROM activity),
eligible AS (
    SELECT u.* FROM users u, today
    WHERE u.register_date <= today.d - INTERVAL 30 DAY
),
flags AS (
    SELECT e.user_id,
           (SELECT COUNT(*) FROM activity a WHERE a.user_id = e.user_id
             AND a.activity_date >= e.register_date
             AND a.activity_date <= e.register_date + INTERVAL 7 DAY) >= 3 AS is_activated,
           EXISTS (SELECT 1 FROM activity a WHERE a.user_id = e.user_id
                    AND a.activity_date >  e.register_date + INTERVAL 7  DAY
                    AND a.activity_date <= e.register_date + INTERVAL 30 DAY) AS is_retained,
           (e.plan_type <> 'Free') AS is_paid,
           (SELECT COUNT(*) FROM subscription s WHERE s.user_id = e.user_id
             AND s.payment_status = 'Success') >= 2 AS is_renewed
    FROM eligible e
),
sc AS (
    SELECT COUNT(*) AS registered,
           SUM(CASE WHEN is_activated                                                  THEN 1 ELSE 0 END) AS activated,
           SUM(CASE WHEN is_activated AND is_retained                                  THEN 1 ELSE 0 END) AS retained,
           SUM(CASE WHEN is_activated AND is_retained AND is_paid                      THEN 1 ELSE 0 END) AS paid,
           SUM(CASE WHEN is_activated AND is_retained AND is_paid AND is_renewed       THEN 1 ELSE 0 END) AS renewed
    FROM flags
)
SELECT 1 AS step_order, 'Registered' AS stage, registered AS users,
       100.0 AS step_conversion_pct, 100.0 AS overall_conversion_pct FROM sc
UNION ALL SELECT 2, 'Activated', activated,
    ROUND(100.0 * activated / registered, 2),
    ROUND(100.0 * activated / registered, 2) FROM sc
UNION ALL SELECT 3, 'Retained', retained,
    ROUND(100.0 * retained / NULLIF(activated, 0), 2),
    ROUND(100.0 * retained / registered, 2) FROM sc
UNION ALL SELECT 4, 'Paid', paid,
    ROUND(100.0 * paid / NULLIF(retained, 0), 2),
    ROUND(100.0 * paid / registered, 2) FROM sc
UNION ALL SELECT 5, 'Renewed', renewed,
    ROUND(100.0 * renewed / NULLIF(paid, 0), 2),
    ROUND(100.0 * renewed / registered, 2) FROM sc;


CREATE OR REPLACE VIEW v_activation_analysis AS
WITH today AS (SELECT MAX(activity_date) AS d FROM activity),
eligible AS (
    SELECT u.user_id, u.register_date, u.acquisition_channel, u.plan_type
    FROM users u, today
    WHERE u.register_date <= today.d - INTERVAL 30 DAY
),
ac AS (
    SELECT e.user_id, COUNT(a.activity_id) AS cnt
    FROM eligible e
    LEFT JOIN activity a
      ON a.user_id = e.user_id
     AND a.activity_date >= e.register_date
     AND a.activity_date <= e.register_date + INTERVAL 7 DAY
    GROUP BY e.user_id
),
labeled AS (
    SELECT e.*, (ac.cnt >= 3) AS is_activated
    FROM eligible e JOIN ac USING (user_id)
)
SELECT 'overall' AS segment_type, 'all' AS segment,
       COUNT(*) AS users,
       SUM(CASE WHEN is_activated THEN 1 ELSE 0 END) AS activated,
       ROUND(100.0 * SUM(CASE WHEN is_activated THEN 1 ELSE 0 END) / COUNT(*), 2) AS activation_pct
FROM labeled
UNION ALL
SELECT 'channel', acquisition_channel, COUNT(*),
       SUM(CASE WHEN is_activated THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN is_activated THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM labeled GROUP BY acquisition_channel
UNION ALL
SELECT 'plan', plan_type, COUNT(*),
       SUM(CASE WHEN is_activated THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN is_activated THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM labeled GROUP BY plan_type;


CREATE OR REPLACE VIEW v_paid_conversion AS
SELECT 'overall' AS segment_type, 'all' AS segment, COUNT(*) AS users,
       SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END) AS paid,
       ROUND(100.0 * SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END) / COUNT(*), 2) AS paid_pct
FROM users
UNION ALL
SELECT 'channel', acquisition_channel, COUNT(*),
       SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM users GROUP BY acquisition_channel
UNION ALL
SELECT 'device', device_type, COUNT(*),
       SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM users GROUP BY device_type
UNION ALL
SELECT 'company_size', company_size, COUNT(*),
       SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM users GROUP BY company_size;


CREATE OR REPLACE VIEW v_renewal_analysis AS
WITH paid AS (
    SELECT user_id, COUNT(*) AS pay_cnt, SUM(amount) AS lifetime_rev
    FROM subscription WHERE payment_status = 'Success' GROUP BY user_id
),
j AS (
    SELECT u.user_id, u.acquisition_channel, u.plan_type,
           p.pay_cnt, p.lifetime_rev,
           (p.pay_cnt >= 2) AS renewed
    FROM users u JOIN paid p USING (user_id)
)
SELECT 'overall' AS segment_type, 'all' AS segment,
       COUNT(*) AS paying_users,
       SUM(CASE WHEN renewed THEN 1 ELSE 0 END) AS renewed_users,
       ROUND(100.0 * SUM(CASE WHEN renewed THEN 1 ELSE 0 END) / COUNT(*), 2) AS renewal_pct,
       ROUND(AVG(pay_cnt), 2) AS avg_payments
FROM j
UNION ALL
SELECT 'channel', acquisition_channel, COUNT(*),
       SUM(CASE WHEN renewed THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN renewed THEN 1 ELSE 0 END) / COUNT(*), 2),
       ROUND(AVG(pay_cnt), 2)
FROM j GROUP BY acquisition_channel
UNION ALL
SELECT 'plan', plan_type, COUNT(*),
       SUM(CASE WHEN renewed THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN renewed THEN 1 ELSE 0 END) / COUNT(*), 2),
       ROUND(AVG(pay_cnt), 2)
FROM j GROUP BY plan_type;
