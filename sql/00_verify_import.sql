-- 00: post-import sanity checks
-- Tables: users, activity, subscription

-- row counts
SELECT 'users'         AS table_name, COUNT(*) AS rows FROM users
UNION ALL
SELECT 'activity'      AS table_name, COUNT(*) AS rows FROM activity
UNION ALL
SELECT 'subscription'  AS table_name, COUNT(*) AS rows FROM subscription;

-- preview
SELECT * FROM users        LIMIT 10;
SELECT * FROM activity     LIMIT 10;
SELECT * FROM subscription LIMIT 10;

DESCRIBE users;
DESCRIBE activity;
DESCRIBE subscription;

-- quick smell test: paid conversion by channel should rank organic/social high, email low
SELECT
    acquisition_channel,
    COUNT(*)                                                  AS total_users,
    SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END)      AS paid_users,
    ROUND(100.0 * SUM(CASE WHEN plan_type <> 'Free' THEN 1 ELSE 0 END) / COUNT(*), 2) AS conversion_pct
FROM users
GROUP BY acquisition_channel
ORDER BY conversion_pct DESC;
