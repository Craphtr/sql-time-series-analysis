-- COHORT ANALYSIS
-- Load the dataset required for this work
select * from legislators_terms;


-- COMPUTING A BASIC RETENTION CURVE
-- 3 components are required :- 
   --> define the cohort group: the legislators, 
   --> time series of actions: terms in office for each legislator
   --> and an aggregate metric that measures something relevant to the process: count of those still in office each period from the starting date

-- BUSINESS QUESTION
-- =======================================================================================================
-- What percentage of US legislators, grouped by the year they first entered office (their cohort), 
-- remain in office (are retained) in each successive two-year period following their first term start date?"
-- =======================================================================================================


-- Step 1: find the first date each legislator took office (first_term) 
   --> take the min of the term_start and GROUP BY each id_bioguide, the unique identifier for a legislator
select id_bioguide,
    min(term_start) as first_term
from legislators_terms 
group by 1
order by first_term;

-- Step 2: The next step is to put this code above into a subquery and JOIN it to the time series of actions (tsa)
select date_part('year', age(tsa.term_start,a.first_term)) as period,
    count(distinct a.id_bioguide) as cohort_retained
    from (
        select id_bioguide,
        min(term_start) as first_term
        from legislators_terms 
        group by 1) a 
    join legislators_terms tsa on a.id_bioguide = tsa.id_bioguide
    group by 1;
    
-- Step 3: Now that we have the periods and the number of legislators retained in each, 
   --> the final step is to calculate the total cohort_size and populate it in each row 
   --> so that the cohort_retained can be divided by it to get the pctage_retained. 
create or replace view cohort_pctage_retained_view as
   with cohort_and_time_series as (
   select date_part('year', age(tsa.term_start,a.first_term)) as period_,
    count(distinct a.id_bioguide) as cohort_retained
    from (
        select id_bioguide,
        min(term_start) as first_term
        from legislators_terms 
        group by 1) a 
    join legislators_terms tsa on a.id_bioguide = tsa.id_bioguide
    group by 1 
)
select period_,
    first_value(cohort_retained) over (order by period_) as cohort_size,
    cohort_retained,
    round(cohort_retained::numeric/ first_value(cohort_retained) over (order by period_),2) as pct_retained
from cohort_and_time_series;

--PIVOT AND AGGREGATE WITH A CASE STATEMENT TO SEE THE RETENTION PER PERIOD
with cohort_and_time_series as (
   select date_part('year', age(tsa.term_start,a.first_term)) as period_,
    count(distinct a.id_bioguide) as cohort_retained
    from (
        select id_bioguide,
        min(term_start) as first_term
        from legislators_terms 
        group by 1) a 
    join legislators_terms tsa on a.id_bioguide = tsa.id_bioguide
    group by 1 
),
retained_pctage as (select period_,
    first_value(cohort_retained) over (order by period_) as cohort_size,
    cohort_retained,
    round(cohort_retained::numeric/ first_value(cohort_retained) over (order by period_),2) as pct_retained
from cohort_and_time_series)
select max(cohort_size) as cohort_size,
    max(case when period_ = 0 then pct_retained end) as yr_0,
    max(case when period_ = 2 then pct_retained end) as yr_2,
    max(case when period_ = 4 then pct_retained end) as yr_4,
    max(case when period_ = 6 then pct_retained end) as yr_6
from retained_pctage;
    

-- RETENTION CALCULATION USING START & END DATE DEFINED IN THE DATA
-- This is achieved by joining the first_term table (a) to the legislators_terms table (b)
-- containing start_term and term_end for each term before joining to the date_dimension table (dd)
select a.id_bioguide, a.first_term,
    b.term_start, b.term_end,
    dd.date,
    date_part('year', age(dd.date, a.first_term)) as period
from
(
    select id_bioguide, min(term_start) as first_term 
    from legislators_terms
    group by 1
) a
join legislators_terms b 
on a.id_bioguide = b.id_bioguide 
left join date_dim dd
on dd.date between term_start and term_end 
and dd.month_name = 'December' and dd.day_of_month = 31;

-- We now have a row for each date (year end) for which we would like to calculate retention. 
-- The next step is to calculate the cohort_retained for each period, which is done with a count of id_bioguide.
select coalesce(date_part('year', age(dd.date,a.first_term)),0) as period,
    count(distinct a.id_bioguide) as cohort_retained
from
(
    select id_bioguide, min(term_start) as first_term 
    from legislators_terms
    group by 1
) a 
join legislators_terms b on a.id_bioguide = b.id_bioguide
left join date_dim dd on dd.date between term_start and term_end
and dd.month_name = 'December' and dd.day_of_month = 31
group by 1;

-- The final step is to calculate the cohort_size and pct_retained
-- as we did previously using first_value window functions:
create or replace view retention_with_startend_view_04 as
with cohort_and_time_series as (
    select coalesce(date_part('year', age(dd.date, a.first_term)),0) as period,
    count(distinct a.id_bioguide) as cohort_retained
    from 
    (
        select id_bioguide, min(term_start) as first_term
        from legislators_terms
        group by 1
    ) a
    join legislators_terms b on a.id_bioguide = b.id_bioguide 
    left join date_dim dd on dd.date between term_start and term_end
    and dd.month_name = 'December' and dd.day_of_month = 31
    group by 1
    )
    select period,
    first_value(cohort_retained) over (order by period) as cohort_size,
    cohort_retained,
    round(cohort_retained::numeric/first_value(cohort_retained) over (order by period),4) as pct_retained
    from cohort_and_time_series;

   
-- COHORTS DERIVED FROM THE TIME SERIES ITSELF
-- The key question we will consider is whether the era in which a legislator 
-- first took office has any correlation with their retention. 
-- Political trends and the pub‐ lic mood do change over time, but by how much?   
   
-- To calculate yearly cohorts, we first add the year of the first_term calculated 
-- previously to the query that finds the period and cohort_retained:  
   
SELECT date_part('year',a.first_term) AS first_year,
    COALESCE(date_part('year', age(dd.date, a.first_term)),0) AS period,
    count(DISTINCT a.id_bioguide) AS cohort_retained
FROM (
    SELECT id_bioguide, min(term_start) AS first_term 
    FROM legislators_terms
    GROUP BY 1
    ) a
JOIN legislators_terms b ON a.id_bioguide = b.id_bioguide
LEFT JOIN date_dim dd ON dd.date BETWEEN b.term_start AND b.term_end
AND dd.month_name = 'December' AND dd.day_of_month = 31
GROUP BY 1,2;
   
-- We now use the query above in a with statement and calculate the cohort_size and pct_retained
with time_series_derived_cohorts as (
   select date_part('year', a.first_term) as first_year,
   coalesce(date_part('year', age(dd.date, a.first_term)),0) as period,
   count(distinct a.id_bioguide) as cohort_retained
   from
   (
       select id_bioguide, min(term_start) as first_term
       from legislators_terms
       group by 1
   ) a 
   join legislators_terms b on a.id_bioguide = b.id_bioguide
   left join date_dim dd on dd.date between b.term_start and b.term_end 
   and dd.month_name = 'December' and dd.day_of_month = 31
   group by 1, 2
   )
select first_year, period,
    first_value(cohort_retained) over (partition by first_year order by period) as cohort_size,
    cohort_retained,
    cohort_retained::numeric/ first_value(cohort_retained) over (partition by first_year order by period) as pct_retained
from time_series_derived_cohorts;
--This yields a datset which includes over 200 starting years which is too much to easily graph
   
   
-- Next we’ll look at a less granular interval and cohort the legislators by the century of the first_term.   
create or replace view century_derived_cohorts_view as 
with time_series_derived_cohorts as (
   select date_part('century', a.first_term) as first_century,
   coalesce(date_part('year', age(dd.date, a.first_term)),0) as period,
   count(distinct a.id_bioguide) as cohort_retained
   from
   (
       select id_bioguide, min(term_start) as first_term
       from legislators_terms
       group by 1
   ) a 
   join legislators_terms b on a.id_bioguide = b.id_bioguide
   left join date_dim dd on dd.date between b.term_start and b.term_end 
   and dd.month_name = 'December' and dd.day_of_month = 31
   group by 1, 2
   )
select first_century, period,
    first_value(cohort_retained) over (partition by first_century order by period) as cohort_size,
    cohort_retained,
    round(cohort_retained::numeric/ first_value(cohort_retained) over (partition by first_century order by period),4) as pct_retained
from time_series_derived_cohorts;   
   

-- DEFINING COHORTS FROM OTHER ATTRIBUTES IN A TIME SERIES BESIDES FIRST DATE

-- The legislators_terms table has a state field, indicating which state the person is representing
-- for that term. We can use this to create cohorts, and we will base them on the first state 
-- in order to ensure that anyone who has represented multiple states appears in the data only once.
   
select distinct id_bioguide,
min(term_start) over (partition by id_bioguide) as first_term,
first_value(state) over (partition by id_bioguide order by term_start) as first_state
from legislators_terms;
--We can then plug this code into our retention code to find the retention by first_state

create or replace view attribute_derived_cohorts as
with attribute_derived_cohorts as (
    select a.first_state,
        coalesce(date_part('year', age(dd.date, a.first_term)),0) as period,
        count(distinct a.id_bioguide) as cohort_retained
    from
    (    
        select distinct id_bioguide, 
            min(term_start) over (partition by id_bioguide) as first_term,
            first_value(state) over (partition by id_bioguide order by term_start) as first_state
       from legislators_terms
   ) a 
   join legislators_terms b on a.id_bioguide = b.id_bioguide 
   left join date_dim dd on dd.date between term_start and term_end
   and dd.month_name = 'December' and dd.day_of_month = 31
   group by 1,2
   ) 
   select first_state,
   period,
   first_value(cohort_retained) over (partition by first_state order by period) as cohort_size_by_state,
   cohort_retained,
   cohort_retained::numeric / first_value(cohort_retained) over (partition by first_state order by period) as pct_retained_by_state
   from attribute_derived_cohorts;
   
 -- DEFINING COHORTS FROM A SEPARATE TABLE  
   -- We’ll consider whether the gender of the legislator has any impact on their retention. 
   -- The gender column is in another table called legislators and we shall use it to cohort the legislators
drop view gender_table_cohort04;
  create or replace view gender_table_cohort_view04 as  
  with separate_table_cohorts as (
  select c.gender,
      coalesce(date_part('year', age(dd.date, a.first_term)),0) as period,
      count(distinct a.id_bioguide) as cohort_retained
      from 
          (
              select id_bioguide, min(term_start) as first_term 
              from legislators_terms 
              group by 1
          ) a
      join legislators_terms b on a.id_bioguide = b.id_bioguide 
      left join date_dim dd on dd.date between b.term_start and b.term_end
      and dd.month_name = 'December' and dd.day_of_month = 31
      join legislators c on a.id_bioguide = c.id_bioguide 
      group by 1,2
      order by 1,2
)
select gender, period,
    first_value(cohort_retained) over (partition by gender order by period) as cohort_size_by_gender,
    cohort_retained,
    cohort_retained::numeric/first_value(cohort_retained) over (partition by gender order by period) as pct_retained_by_gender
from separate_table_cohorts;   
   
--RESTRICTING THE COMPARISON TO WHEN FEMALES STARTED TAKING OFFICE 
  with separate_table_cohorts as (
  select c.gender,
      coalesce(date_part('year', age(dd.date, a.first_term)),0) as period,
      count(distinct a.id_bioguide) as cohort_retained
      from 
          (
              select id_bioguide, min(term_start) as first_term 
              from legislators_terms 
              group by 1
          ) a
      join legislators_terms b on a.id_bioguide = b.id_bioguide 
      left join date_dim dd on dd.date between b.term_start and b.term_end
      and dd.month_name = 'December' and dd.day_of_month = 31
      join legislators c on a.id_bioguide = c.id_bioguide
      where a.first_term between '1917-01-01' and '1999-12-31'
      group by 1,2
      order by 1,2
)
select gender, period,
    first_value(cohort_retained) over (partition by gender order by period) as cohort_size_by_gender,
    cohort_retained,
    cohort_retained::numeric/first_value(cohort_retained) over (partition by gender order by period) as pct_retained_by_gender
from separate_table_cohorts;   
   
   
-- DEALING WITH SPARSE COHORTS
  
-- To demonstrate this, let’s attempt to cohort female legislators by the first state they represented
-- to see if there are any differences in retention. We have already seen that female legislators are few in number.
-- Cohorting them further by state would definitely lead to sparse cohorts in which there are very few members.
-- So lets add first_state into the previous retention by gender example and see the results.
   
SELECT first_state, 
gender, 
period ,
first_value(cohort_retained) over (partition by first_state, gender order by period) as cohort_size,
cohort_retained ,
cohort_retained::numeric/
first_value(cohort_retained) over (partition by first_state, gender order by period) as pct_retained
FROM 
(
    SELECT a.first_state, 
    d.gender ,
    coalesce(date_part('year',age(c.date,a.first_term)),0) as period ,
    count(distinct a.id_bioguide) as cohort_retained
    FROM
    (
        SELECT distinct id_bioguide,
        min(term_start) over (partition by id_bioguide) as first_term ,
        first_value(state) over (partition by id_bioguide order by term_start) as first_state
        FROM legislators_terms )a
    JOIN legislators_terms b on a.id_bioguide = b.id_bioguide
    LEFT JOIN date_dim c on c.date between b.term_start and b.term_end and c.month_name = 'December' and c.day_of_month = 31
    JOIN legislators d on a.id_bioguide = d.id_bioguide
    WHERE a.first_term between '1917-01-01' and '1999-12-31'
    GROUP BY 1,2,3
) aa ;