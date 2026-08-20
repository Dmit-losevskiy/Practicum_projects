create or replace function cookie_cats.bootstrap_losevskiy_d_p(sample_size integer, num_iterations integer default 1000)
returns table(metric_name text, gate_30_mean numeric, gate_40_mean numeric, mean_difference numeric, ci_lower numeric, ci_upper numeric, p_value numeric, is_significant boolean)
language plpgsql
as $$
declare
    iteration_index integer;
begin
    
    drop table if exists bootstrap_results_store;

    create temporary table if not exists bootstrap_results_store (
        run_id integer,
        metric_key text,
        group_30_value numeric,
        group_40_value numeric,
        value_difference numeric
    );

    truncate bootstrap_results_store;

    -- Основной цикл бутстрапа
    for iteration_index in 1..num_iterations loop

        with
        sampled_data_30 as (
            select sum_gamerounds, retention_1, retention_7
            from cookie_cats.ab_results
            where version = 'gate_30'
            order by random()
            limit sample_size
        ),
        sampled_data_40 as (
            select sum_gamerounds, retention_1, retention_7
            from cookie_cats.ab_results
            where version = 'gate_40'
            order by random()
            limit sample_size
        ),
        metrics_30 as (
            select 'retention_1' as metric_key, avg(case when retention_1 then 1.0 else 0.0 end) as group_30_value from sampled_data_30
            union all
            select 'retention_7' as metric_key, avg(case when retention_7 then 1.0 else 0.0 end) as group_30_value from sampled_data_30
            union all
            select 'median_gamerounds' as metric_key, percentile_cont(0.5) within group (order by sum_gamerounds) as group_30_value from sampled_data_30
            union all
            select 'mean_gamerounds' as metric_key, avg(sum_gamerounds) as group_30_value from sampled_data_30
            union all
            select 'p75_gamerounds' as metric_key, percentile_cont(0.75) within group (order by sum_gamerounds) as group_30_value from sampled_data_30
            union all
            select 'p95_gamerounds' as metric_key, percentile_cont(0.95) within group (order by sum_gamerounds) as group_30_value from sampled_data_30
        ),
        metrics_40 as (
            select 'retention_1' as metric_key, avg(case when retention_1 then 1.0 else 0.0 end) as group_40_value from sampled_data_40
            union all
            select 'retention_7' as metric_key, avg(case when retention_7 then 1.0 else 0.0 end) as group_40_value from sampled_data_40
            union all
            select 'median_gamerounds' as metric_key, percentile_cont(0.5) within group (order by sum_gamerounds) as group_40_value from sampled_data_40
            union all
            select 'mean_gamerounds' as metric_key, avg(sum_gamerounds) as group_40_value from sampled_data_40
            union all
            select 'p75_gamerounds' as metric_key, percentile_cont(0.75) within group (order by sum_gamerounds) as group_40_value from sampled_data_40
            union all
            select 'p95_gamerounds' as metric_key, percentile_cont(0.95) within group (order by sum_gamerounds) as group_40_value from sampled_data_40
        )
        insert into bootstrap_results_store (run_id, metric_key, group_30_value, group_40_value)
        select
            iteration_index,
            m30.metric_key,
            m30.group_30_value,
            m40.group_40_value
        from metrics_30 m30
        join metrics_40 m40 on m30.metric_key = m40.metric_key;

    end loop;

    update bootstrap_results_store
    set value_difference = group_40_value - group_30_value;

    -- Агрегация результатов, расчет CI и P-value
    return query
        with aggregated_bootstrap_stats as (
            select
                t.metric_key,
                avg(t.group_30_value) as avg_gate_30,
                avg(t.group_40_value) as avg_gate_40,
                avg(t.value_difference) as avg_diff,
                percentile_cont(0.025) within group (order by t.value_difference) as lower_ci,
                percentile_cont(0.975) within group (order by t.value_difference) as upper_ci,
                (2.0 * least(
                    sum(case when t.value_difference <= 0 then 1 else 0 end)::float / count(*),
                    sum(case when t.value_difference >= 0 then 1 else 0 end)::float / count(*)
                )) as calculated_p_value
            from bootstrap_results_store t
            where t.group_30_value is not null and t.group_40_value is not null
            group by t.metric_key
        )
        select
            s.metric_key as metric_name,
            s.avg_gate_30::numeric as gate_30_mean,
            s.avg_gate_40::numeric as gate_40_mean,
            s.avg_diff::numeric as mean_difference,
            s.lower_ci::numeric as ci_lower,
            s.upper_ci::numeric as ci_upper,
            s.calculated_p_value::numeric as p_value,
            s.calculated_p_value::numeric < 0.05 as is_significant
        from aggregated_bootstrap_stats s;
end;
$$;

select * from cookie_cats.bootstrap_losevskiy_d_p(1000, 1000)