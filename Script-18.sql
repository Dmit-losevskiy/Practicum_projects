-- 1. Daily Revenue (Выручка за день по продукту)
SELECT
    event_date,
    product_name,
    SUM(revenue) AS daily_revenue
FROM mobile_game.transactions
GROUP BY event_date, product_name
ORDER BY event_date;

-- Daily Revenue (Выручка за день по стране)
SELECT
    event_date,
    country,
    SUM(revenue) AS daily_revenue
FROM mobile_game.transactions t
join mobile_game.user_info ui using(user_id)
GROUP BY 1, 2
ORDER BY 1;

-- 2. Daily Active Users (DAU) по каналам
WITH first_sessions AS (
    SELECT
        user_id,
        MIN(session_start_time) AS first_session_time
    FROM mobile_game.sessions s 
    GROUP BY 1
),
last_click_channel AS (
    SELECT
        fs.user_id,
        ut.channel,
        MAX(ut.touch_date) AS last_touch_date
    FROM first_sessions fs
    LEFT JOIN mobile_game.users_touches ut 
        ON ut.user_id = fs.user_id
        AND ut.touch_date <= fs.first_session_time
    GROUP BY 1, 2
),
last_click_per_user AS (
    SELECT DISTINCT ON (user_id)
        user_id,
        channel,
        last_touch_date
    FROM last_click_channel
    ORDER BY user_id, last_touch_date DESC
)
SELECT
    lcu.last_touch_date,
    lcu.channel,
    COUNT(DISTINCT ui.user_id) AS dau
FROM last_click_per_user lcu
JOIN mobile_game.user_info ui ON ui.user_id = lcu.user_id
GROUP BY 1, 2

-- 3. Average Revenue Per Daily Active User (ARPDAU)
WITH DailyRevenue AS (
SELECT
    event_date,
    country,
    SUM(revenue) AS daily_revenue
FROM mobile_game.transactions t
join mobile_game.user_info ui using(user_id)
GROUP BY 1, 2
ORDER BY 1
),
DailyActiveUsers AS (
WITH first_sessions AS (
SELECT
    user_id,
    MIN(session_start_time) AS first_session_time
FROM mobile_game.sessions s 
GROUP BY 1
),
last_click_channel AS (
    SELECT
        fs.user_id,
        ut.channel,
        MAX(ut.touch_date) AS last_touch_date
    FROM first_sessions fs
    LEFT JOIN mobile_game.users_touches ut 
        ON ut.user_id = fs.user_id
        AND ut.touch_date <= fs.first_session_time
    GROUP BY 1, 2
),
last_click_per_user AS (
    SELECT DISTINCT ON (user_id)
        user_id,
        channel,
        last_touch_date
    FROM last_click_channel
    ORDER BY user_id, last_touch_date DESC
)
SELECT
    lcu.last_touch_date as event_date,
    lcu.channel,
    COUNT(DISTINCT ui.user_id) AS dau
FROM last_click_per_user lcu
JOIN mobile_game.user_info ui ON ui.user_id = lcu.user_id
GROUP BY 1, 2
) 
SELECT
    dr.event_date,
    dr.daily_revenue / dau.dau AS arpdau
FROM DailyRevenue dr
JOIN DailyActiveUsers dau ON dr.event_date = dau.event_date
ORDER BY dr.event_date;

-- 4. New Installs (Новые установки) по каналам
WITH new_installs AS (
SELECT
    MIN(user_start_date) AS install_date,
    user_id
FROM mobile_game.user_info
GROUP BY 2
),
last_click_channel AS (
    SELECT
        ni.user_id,
        ut.channel,
        MAX(ut.touch_date) AS last_touch_date
    FROM new_installs ni
    LEFT JOIN mobile_game.users_touches ut 
        ON ut.user_id = ni.user_id
        AND ut.touch_date <= ni.install_date
    GROUP BY 1, 2
),
last_click_per_user AS (
    SELECT DISTINCT ON (user_id)
        user_id,
        channel,
        last_touch_date
    FROM last_click_channel
    ORDER BY user_id, last_touch_date DESC
)
SELECT
    lcu.last_touch_date,
    lcu.channel,
    COUNT(DISTINCT ui.user_id) AS new_installs
FROM last_click_per_user lcu
JOIN mobile_game.user_info ui ON ui.user_id = lcu.user_id
GROUP BY 1, 2

-- 5. Returning Users (Вернувшиеся пользователи) по каналам
WITH new_installs AS (
SELECT
    MIN(user_start_date) AS install_date,
    user_id
FROM mobile_game.user_info
GROUP BY 2
),
last_click_channel AS (
    SELECT
        ni.user_id,
        ut.channel,
        MAX(ut.touch_date) AS last_touch_date
    FROM new_installs ni
    LEFT JOIN mobile_game.users_touches ut 
        ON ut.user_id = ni.user_id
        AND ut.touch_date <= ni.install_date
    GROUP BY 1, 2
),
last_click_per_user AS (
    SELECT DISTINCT ON (user_id)
        user_id,
        channel,
        last_touch_date
    FROM last_click_channel
    ORDER BY user_id, last_touch_date DESC
)
SELECT
    lcu.last_touch_date,
    lcu.channel,
    COUNT(s.user_id)::float / count(*) AS returning_1d
FROM last_click_per_user lcu
left JOIN mobile_game.sessions s ON s.user_id = lcu.user_id
and lcu.last_touch_date + 1 = s.session_start_time::date
GROUP BY 1, 2
ORDER BY 1;

-- 6. Daily Conversion (Конверсия в покупку) 
-- Считаем количество новых пользователей и количество пользователей, совершивших первую покупку
WITH NewUsers AS (
    SELECT
        DATE(user_start_date) AS install_date,
        COUNT(DISTINCT user_id) AS new_users
    FROM mobile_game.user_info
    GROUP BY 1
),
FirstPurchase AS (
    SELECT
        DATE(ui.user_start_date) AS install_date,
        ui.country,
        COUNT(DISTINCT t.user_id) AS paying_users
    FROM mobile_game.transactions t
    JOIN mobile_game.user_info ui ON t.user_id = ui.user_id
    AND DATE(t.event_date) = DATE(ui.user_start_date)
    GROUP BY 1, 2
)
SELECT
    nu.install_date,
    fp.country,
    CAST(fp.paying_users AS REAL) / nu.new_users AS daily_conversion
FROM NewUsers nu
LEFT JOIN FirstPurchase fp ON nu.install_date = fp.install_date
ORDER BY nu.install_date;

-- 7. Average Revenue Per Paying User (ARPPU)
WITH PayingUsersRevenue AS (
    SELECT
        event_date,
        SUM(revenue) AS total_revenue,
        COUNT(DISTINCT user_id) AS paying_users
    FROM mobile_game.transactions
    GROUP BY event_date
)
SELECT
    event_date,
    total_revenue / paying_users AS arppu
FROM PayingUsersRevenue
WHERE paying_users > 0
ORDER BY event_date;

--3. ARPPU by Payer Segment and Date
SELECT
    t.event_date,
    ui.payer_segment,
    SUM(t.revenue) AS total_revenue,
    COUNT(DISTINCT t.user_id) AS paying_users,
    SUM(t.revenue) / COUNT(DISTINCT t.user_id) AS arppu
FROM mobile_game.transactions t
JOIN mobile_game.user_info ui ON t.user_id = ui.user_id
GROUP BY t.event_date, ui.payer_segment
ORDER BY t.event_date, ui.payer_segment;

-- предназначен для расчета конверсии новых пользователей по каналам с использованием атрибуции по последнему клику (Last Click).
WITH RankedTouches AS (
    SELECT
        user_id,
        touch_date,
        channel,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY touch_date DESC) AS rn
    FROM mobile_game.users_touches
),
LastTouch AS (
    SELECT
        user_id,
        touch_date,
        channel
    FROM RankedTouches
    WHERE rn = 1
),
NewUsers AS (
    SELECT
        DATE(ui.user_start_date) AS install_date,
        ui.user_id,
        lt.channel
    FROM mobile_game.user_info ui
    LEFT JOIN LastTouch lt ON ui.user_id = lt.user_id
),
FirstPurchase AS (
    SELECT
        DATE(ui.user_start_date) AS install_date,
        ui.user_id
    FROM mobile_game.transactions t
    JOIN mobile_game.user_info ui ON t.user_id = ui.user_id
    AND DATE(t.event_date) = DATE(ui.user_start_date)
)
SELECT
    nu.install_date,
    nu.channel,
    COUNT(DISTINCT fp.user_id) AS paying_users,
    COUNT(DISTINCT nu.user_id) AS new_users,
    CAST(COUNT(DISTINCT fp.user_id) AS REAL) / COUNT(DISTINCT nu.user_id) AS conversion_rate
FROM NewUsers nu
LEFT JOIN FirstPurchase fp ON nu.user_id = fp.user_id AND DATE(nu.install_date) = DATE(fp.install_date)
GROUP BY nu.install_date, nu.channel
ORDER BY nu.install_date, nu.channel;

-- Проверка недельных когорт на удержание индийских пользователей
WITH UserCohorts AS (
    SELECT
        user_id,
        DATE_TRUNC('week', DATE(user_start_date)) AS cohort_week
    FROM mobile_game.user_info
    WHERE country = 'India'
),
WeeklyActiveUsers AS (
    SELECT
        DATE_TRUNC('week', t.event_date) AS week,
        t.user_id
    FROM mobile_game.transactions t
    JOIN mobile_game.user_info ui ON t.user_id = ui.user_id
    WHERE ui.country = 'India'
    GROUP BY 1, 2
)
SELECT
    uc.cohort_week,
    wau.week,
    COUNT(DISTINCT wau.user_id) AS active_users,
    (COUNT(DISTINCT wau.user_id) * 1.0 / (SELECT COUNT(DISTINCT user_id) FROM UserCohorts WHERE cohort_week = uc.cohort_week)) AS retention_rate
FROM UserCohorts uc
LEFT JOIN WeeklyActiveUsers wau ON uc.user_id = wau.user_id
WHERE wau.week >= uc.cohort_week
GROUP BY 1, 2
ORDER BY 1, 2;
