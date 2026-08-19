-- Создание первой временной таблицы события старта сессии
drop table if exists sessions

create temp table sessions as 
select 
ae.user_id,
ae.event_time,
cast(ae.user_properties->'segments'->>'gaming_skill' as integer) as gaming_skill,
cast(ae.user_properties->'segments'->>'payer_segment' as integer) as payer_segment,
ae.user_properties->>'timezone' AS timezone,
(ae.user_properties -> 'channels_touch') ->> (jsonb_array_length(ae.user_properties -> 'channels_touch') - 1) AS last_channel_touch,
(ae.user_properties->>'first_install_date')::date as first_install_date,
ae.app_version,
ae.platform,
ae.country
from 
puzzle.all_events as ae
where
ae.event_time::date >= (ae.user_properties->>'first_install_date')::date and ae.event_name = 'session_start'

select * from sessions

-- Создание второй временной таблицы платежи игроков
drop table if exists revenue

create temporary table revenue as
select
ae.user_id,
ae.event_time,
coalesce(
nullif(ae.event_properties->'transaction'->>'revenue', '')::numeric,0
) as revenue,
coalesce(
nullif(ae.event_properties->'transaction'->>'quantity', '')::integer,0
) as quantity,
coalesce(
nullif(ae.event_properties->'transaction'->>'product_id', '')::integer,0
) as product_id,
coalesce(
lower(event_properties->'transaction'->>'product_name'), 
case                                                      
when coalesce(nullif(event_properties->'transaction'->>'revenue','')::numeric, 0) = 3.99 then 'sale'
when coalesce(nullif(event_properties->'transaction'->>'revenue','')::numeric, 0) = 5.99 then 'hard_currency'
when coalesce(nullif(event_properties->'transaction'->>'revenue','')::numeric, 0) = 10.99 then 'season'
else null                                           
end
) as product_name,
coalesce(
nullif(ae.event_properties->'transaction'->>'transaction_id', '')::integer,0
) as transaction_id,
(ae.user_properties -> 'channels_touch') ->> (jsonb_array_length(ae.user_properties -> 'channels_touch') - 1) as last_channel_touch,
ae.app_version,
ae.platform,
ae.country
from 
puzzle.all_events as ae
where 
ae.event_name = 'transaction' and
ae.event_time::date >= (ae.user_properties->>'first_install_date')::date

select * from revenue

-- Создание третьей временной таблицы попытки игроков на уровнях (победы и поражения)
drop table if exists attempts

create temporary table attempts as
select
ae.user_id,
ae.event_time,
ae.event_name,
(ae.event_properties ->> 'errors')::integer as errors,
(ae.event_properties ->> 'attempt')::integer as attempt,
(ae.event_properties ->> 'level_number')::integer as level_number,
(ae.event_properties ->> 'level_hardness')::integer as level_hardness,
coalesce(
nullif(ae.event_properties ->> 'currency_spent_clues','')::integer,0
) as currency_spent_clues,
coalesce(
nullif(ae.event_properties ->> 'currency_spent_lives','')::integer,0
) as currency_spent_lives,
cast(ae.user_properties->'segments'->>'gaming_skill' as integer) as gaming_skill,
(ae.user_properties -> 'channels_touch') ->> (jsonb_array_length(ae.user_properties -> 'channels_touch') - 1) as last_channel_touch,
ae.app_version,
ae.platform,
ae.country
from
puzzle.all_events as ae
where
ae.event_name in ('level_completed', 'level_failed') and
ae.event_time::date >= (ae.user_properties->>'first_install_date')::date

select * from attempts

-- Создание четвёртой временной таблицы список читеров
drop table if exists cheaters

create temporary table cheaters as
with
level_completion_times as (
select
user_id,
level_number,
extract(epoch from (event_time - prev_event_time)) as sec_level
from (
select
user_id,
level_number,
event_time,
lag(event_time) over (partition by user_id order by event_time) as prev_event_time
from
attempts
 where
event_name = 'level_completed'
) as user_level_events
where extract(epoch from (event_time - prev_event_time)) is not null
and extract(epoch from (event_time - prev_event_time)) > 0 
),
speed_threshold as (
select
percentile_cont(0.005) within group (order by sec_level) as threshold_seconds
from
level_completion_times
where
sec_level > 0 
)
select
lct.user_id,
avg(lct.sec_level) as avg_level, 
count(lct.level_number) as count_levels         
from
level_completion_times as lct
cross join
speed_threshold as st
where
lct.sec_level < st.threshold_seconds 
group by
lct.user_id
having
count(lct.level_number) > 3 

select * from cheaters

-- проверка за какое время в среднем проходится каждый уровень
select
level_number,
avg(sec_play_level) as average_level_time,
count(distinct user_id)
from (
select
user_id,
level_number,
(extract(epoch from (last_attempt_time - first_attempt_time)) / attempts_count::float) as sec_play_level
from (
select
user_id,
level_number,
count(*) as attempts_count,
min(event_time) as first_attempt_time,
max(event_time) as last_attempt_time
from attempts
group by user_id, level_number
) as q1
where attempts_count > 1
) as q2
group by level_number
order by 1


-- Анализ данных и ответы на вопросы Product Owner

-- 1. Сколько уровней в расчете на 1 игрока выигрывается с 1 попытки? Есть ли какая-то зависимость от скилла игроков? Если да, то какая?
with first_wins AS (
select 
user_id,
gaming_skill,
COUNT(level_number) as levels_first
from attempts
where event_name = 'level_completed' and attempt = 1
group by user_id, gaming_skill
)
select 
gaming_skill,
sum(levels_first)/ count(distinct user_id) as avg_first
from first_wins 
group by gaming_skill
order by gaming_skill
--0	33.4911375661375661
--1	36.6252844500632111
--2	39.0635582182860120
--3	41.5672241669907948
-- Чем выше скил тем больше уровней пройдено с первой попытки в среднем.

-- 2. Какой процент от игроков составляют читеры? Является ли это проблемой?
select
(count(distinct case when a.user_id in (select user_id from cheaters) then a.user_id end)::decimal / count(distinct a.user_id)) * 100 as cheater_percentage
from attempts a
-- 1.37305699481865285000%
-- Это относительно не много, терпимое количество.

-- 3. Сейчас в игре реализовано 1000 уровней. Достаточно ли у нас уровней сделано для игроков? Насколько этих уровней хватит?
with
level_progression as (
select
user_id,
max(level_number) as max_level_reached
from attempts
group by user_id
),
completion_rates as (
select
user_id,
cast(max_level_reached as float) / 1000 as completion_rate
from level_progression
)
select
(select max(level_number) from attempts) as max_level_reached,
avg(completion_rate) as avg_rate,
percentile_cont(0.25) within group (order by completion_rate) as p25_rate,
percentile_cont(0.50) within group (order by completion_rate) as p50_rate,
percentile_cont(0.75) within group (order by completion_rate) as p75_rate,
percentile_cont(0.95) within group (order by completion_rate) as p95_rate,
count(case when completion_rate >= 1.0 then 1 end) * 1.0 / count(*) as completed_all_levels,
(select max(event_time) - min(event_time) from attempts) as total_duration
from completion_rates;
-- никто не прошёл все 1000, в среднем прошли 49 уровней. Игра существует как минимум 290 дней, хватит этих уровней ещё на долго.

-- 4. Какая общая сложность всей последовательности уровней? Меняется ли она со временем? А какая чистая сложность?
with
level_difficulty as (
select
level_number,
level_hardness,
-- условная агрегация для расчета средней сложности для всех попыток
avg(attempt) as all_avg,
-- условная агрегация для расчета средней сложности без бонусов
avg(
case
when currency_spent_lives = 0 and currency_spent_clues = 0 then attempt
else null
end
) as clean_avg
from
attempts
where
event_name = 'level_completed' 
group by
level_number,
level_hardness
)
select
ld.level_hardness,
-- средняя сложность всех попыток для каждой категории сложности
avg(ld.all_avg) as category_all,
-- средняя "чистая" сложность для каждой категории сложности
avg(ld.clean_avg) as category_clean
from
level_difficulty as ld 
group by
ld.level_hardness
order by
ld.level_hardness
-- с ростом сложности уровня, для него в среднем требуется больше попыток, игрокам которые не пользуются бонусами требуется в среднем больше попыток для прохождения задания.

select
avg(attempt) as overall_all,
avg(
case
when currency_spent_lives = 0 and currency_spent_clues = 0 then attempt
else null 
end
) as overall_clean
from
attempts
where
event_name = 'level_completed'




