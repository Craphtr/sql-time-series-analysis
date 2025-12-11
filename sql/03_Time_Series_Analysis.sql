
-- The Retail Sales Dataset --
-----------------------------------------------------------
select * from retail_sales;

-- Displaying simple trends
select sales_month, sales from retail_sales
where kind_of_business = 'Retail and food services sales, total';

-- Since there's some pattern to the data, we can extract the year from the sales_month and replot
select extract(year from sales_month) as sales_year, sum(sales) as sales from retail_sales
where kind_of_business = 'Retail and food services sales, total'
group by sales_year
order by sales_year;

-- Comparing components of categorical time slices
select extract(year from sales_month) as sales_year, kind_of_business, sum(sales) as sales from retail_sales
where kind_of_business in ('Book stores', 'Sporting goods stores', 'Hobby, toy, and game stores')
group by 1,2;

-- Comparing sales at Mens clothing stores and Womens clothing stores --
select sales_month, kind_of_business, sales from retail_sales
where kind_of_business in ('Men''s clothing stores','Women''s clothing stores');

-- Pivot the monthly Men and Women clothing stores so as to be able to plot in looker
select sales_month,
    sum(case when kind_of_business = 'Men''s clothing stores' then sales end) as Men_monthly_sales,
    sum(case when kind_of_business = 'Women''s clothing stores' then sales end) as Women_monthly_sales
from retail_sales
where kind_of_business in ('Men''s clothing stores', 'Women''s clothing stores')
group by sales_month
order by sales_month;

-- Seasonality observed so we observe yearly sales in Men and Women's clothings
select extract(year from sales_month) as sales_year, kind_of_business, sum(sales) from retail_sales
where kind_of_business in ('Men''s clothing stores', 'Women''s clothing stores')
group by 1,2
order by 1;

-- To calculate the gap between the two categories, we pivot the data with aggregate functions
--  combined with CASE statements
select extract(year from sales_month) as sales_year,
    sum(case when kind_of_business = 'Men''s clothing stores' then sales end) as Men_sales,
    sum(case when kind_of_business = 'Women''s clothing stores' then sales end) as Women_sales
    from retail_sales
    where kind_of_business in ('Men''s clothing stores', 'Women''s clothing stores')
    group by 1;

-- Gap Calculations without using a subquery
select extract(year from sales_month) as sales_year,
    sum(case when kind_of_business = 'Men''s clothing stores' then sales end) as Men_sales,
    sum(case when kind_of_business = 'Women''s clothing stores' then sales end) as Women_sales
    sum(case when kind_of_business = 'Women''s clothing stores' then sales end) - 
    sum(case when kind_of_business = 'Men''s clothing stores' then sales end) as Women_Men_Sales_diff
    from retail_sales
    where kind_of_business in ('Men''s clothing stores', 'Women''s clothing stores')
    group by 1)
    
-- Gap Calculations using a CTE - sales_diff, ratio, pctage_diff, percentage_of_total for men and women sales
drop view if exists MenWomenSales_view;

create or replace view MenWomenSales_view  as ;
with Women_Men_sales as (
select sales_month, 
    extract(year from sales_month) as sales_year,
    sum(case when kind_of_business = 'Men''s clothing stores' then sales end) as Men_monthly_sales,
    sum(case when kind_of_business = 'Women''s clothing stores' then sales end) as Women_monthly_sales
    from retail_sales
    where kind_of_business in ('Men''s clothing stores', 'Women''s clothing stores')
    group by 1
    order by 1),
yearly_calculations as (
select 
    sales_month,
    Men_monthly_sales,
    Women_monthly_sales,
    Women_monthly_sales - Men_monthly_sales as Women_Men_Sales_diff,
    round(Women_monthly_sales / Men_monthly_sales,2) as women_to_men_sales_ratio,
    round((Women_monthly_sales / Men_monthly_sales - 1) * 100,2) as women_to_men_pctage_diff,
    round((Men_monthly_sales * 100)/(Men_monthly_sales + Women_monthly_sales),2) as Men_pctage_of_total,
    round((Women_monthly_sales * 100)/(Men_monthly_sales + Women_monthly_sales),2) as Women_pctage_of_total,
    sum(Men_monthly_sales) over (partition by sales_year) as Men_yearly_sales,
    sum(Women_monthly_sales) over (partition by sales_year) as Women_yearly_sales
from Women_Men_sales
)
select 
    sales_month,
    Men_monthly_sales,
    Women_monthly_sales,
    Women_monthly_sales - Men_monthly_sales as Women_Men_Sales_diff,
    round(Women_monthly_sales / Men_monthly_sales,2) as women_to_men_sales_ratio,
    round((Women_monthly_sales / Men_monthly_sales - 1) * 100,2) as women_to_men_pctage_diff,
    round((Men_monthly_sales * 100)/(Men_monthly_sales + Women_monthly_sales),2) as Men_pctage_of_total,
    round((Women_monthly_sales * 100)/(Men_monthly_sales + Women_monthly_sales),2) as Women_pctage_of_total,
    round((Men_monthly_sales * 100)/Men_yearly_sales,2) as Men_pctage_of_yearly_sales,
    round((Women_monthly_sales * 100)/Women_yearly_sales,2) as Women_pctage_of_yearly_sales,
    sum(Men_monthly_sales) over (partition by date_part('year', sales_month) order by sales_month) as total_men_sales_ytd,
    sum(Women_monthly_sales) over (partition by date_part('year', sales_month) order by sales_month) as total_women_sales_ytd,
    round(avg(Men_monthly_sales) over (order by sales_month rows between 11 preceding and current row),2) as mens_12_month_moving_average,
    round(avg(Women_monthly_sales) over (order by sales_month rows between 11 preceding and current row),2) as womens_12_month_moving_average
    from yearly_calculations;

-- Indexing time series data can be done with a combination of aggregations and window functions or self joins.
-- We use window functions to calculate time series index for men and women clothing sales for the year
select extract(year from sales_month) as sales_year, 
    first_value(sum(men_monthly_sales)) over (order by extract(year from sales_month) ) as men_index_sales,
    first_value(sum(women_monthly_sales)) over (order by extract(year from sales_month) ) as women_index_sales
from MenWomenSales_view
group by sales_year;

-- Next find the percentage change from this base year of 1992 for each row and the yearly women to men sales ratio
drop view index_ratio_view;
create or replace view index_ratio_view as ;
with base_stats as (
select extract(year from sales_month) as sales_year,
    sum(Men_monthly_sales) as Men_yearly_sales,
    sum(Women_monthly_sales) as Women_yearly_sales
from MenWomenSales_view
group by sales_year)
select 
    sales_year,
    Men_yearly_sales,
    Women_yearly_sales,
    first_value(Men_yearly_sales) over (order by sales_year) as men_index_sales,
    first_value(Women_yearly_sales) over (order by sales_year) as women_index_sales,
    round((Men_yearly_sales/first_value(Men_yearly_sales) over (order by sales_year)-1) * 100,2) as pct_from_men_index,
    round((Women_yearly_sales/first_value(Women_yearly_sales) over (order by sales_year)-1)*100,2) as pct_from_women_index,
    round(Women_yearly_sales/Men_yearly_sales,2) as yearly_women_to_men_sales_ratio,
    round((Women_yearly_sales/Men_yearly_sales - 1) * 100,2) as women_to_men_yearly_pctage_diff
from base_stats;
select * from MenWomenSales_view;

-- ROLLING TIME WINDOW CALCULATIONS
-- 12 month moving average calculation
select sales_month,
    round(avg(Men_monthly_sales) over (order by sales_month rows between 11 preceding and current row),2) as mens_12_month_moving_average,
    count(Men_monthly_sales) over (order by sales_month rows between 11 preceding and current row) as mens_record_count,
    round(avg(Women_monthly_sales) over (order by sales_month rows between 11 preceding and current row),2) as womens_12_month_moving_average,
    count(Women_monthly_sales) over (order by sales_month rows between 11 preceding and current row) as womens_record_count
from menwomensales_view;
    

-- ROLLING TIME WINDOWS WITH SPARSE DATA
-- Firstly you create a date dimension which covers all the dates within your sparse dataset
-- Secondly, you left join that date dimension table to the sparse dataset. This ensures you have a row
-- for every single day/month as the case may be, with a NULL in the revenue column wherever data was missing
-- But first let's create a sparse dataset with january and july months data.
select dim.date, sales.sales_month, sales.Women_monthly_sales 
from date_dim dim
join (
    select sales_month, Women_monthly_sales
    from menwomensales_view
    where date_part('month', sales_month) in (1,7)
)sales
    on sales.sales_month between dim.date - interval '11 months' and dim.date
where dim.date = dim.first_day_of_month
    and dim.date between '1993-01-01' and '2020-12-01';

-- Now to calculate the moving average of the sparse dataset that has now been joined to the date dimension
select dim.date, avg(sales.Women_monthly_sales) as women_sales_moving_avg,
count(sales.women_monthly_sales) as records
from date_dim dim
left join (
    select sales_month, Women_monthly_sales
    from menwomensales_view
    where date_part('month', sales_month) in (1,7)
) sales
    on sales.sales_month between dim.date - interval '11 months' and dim.date
where dim.date = dim.first_day_of_month 
    and dim.date between '1993-01-01' and '2020-12-01'
    group by 1;

-- CALCULATING 12 MONTH AVERAGE FOR SPARSE DATA USING MODERN WINDOW FUNCTION
-- We first isolate the sparse data points of january and july
with sparse_sales as (
    select sales_month,
        women_monthly_sales,
        men_monthly_sales
    from menwomensales_view
    where 
        date_part('month',sales_month) in (1,7)
    ),
-- Create the dense timeline by joining the date dimension to the sparse dataset
dense_timeline as (
    select dim.date as full_date,
        ss.women_monthly_sales,
        ss.men_monthly_sales
    from date_dim dim
    left join sparse_sales ss
    on dim.date = ss.sales_month
    --use the authors filter and limit the analysis range to first day of the month 
    where dim.date = dim.first_day_of_month 
    and dim.date between '1993-01-01' and '2020-12-01'
)
-- apply the rolling window
select full_date,
    -- The moving average calculation uses a 12-month trailing window (11 preceding + current row)
    avg(Women_monthly_sales) over (order by full_date rows between 11 preceding and current row) as women_sales_moving_avg,
    -- Count the actual data points found within the 12-month window
    count(women_monthly_sales) over (order by full_date rows between 11 preceding and current row) as Women_records_in_window,
    -- The moving average calculation uses a 12-month trailing window (11 preceding + current row)
    avg(men_monthly_sales) over (order by full_date rows between 11 preceding and current row) as men_sales_moving_avg,
    -- Count the actual data points found within the 12-month window
    count(men_monthly_sales) over (order by full_date rows between 11 preceding and current row) as men_records_in_window
from dense_timeline
order by full_date;


-- CALCULATING CUMULATIVE VALUES
-- Calculating Total sales year-to-date YTD
select sales_month, men_monthly_sales,Women_monthly_sales,
    sum(Men_monthly_sales) over (partition by date_part('year', sales_month) order by sales_month) as total_men_sales_ytd,
    sum(Women_monthly_sales) over (partition by date_part('year', sales_month) order by sales_month) as total_women_sales_ytd
from menwomensales_view;
    
-- Calculating the monthly average ytd
select sales_month, men_monthly_sales,Women_monthly_sales,
    round(avg(Men_monthly_sales) over (partition by date_part('year', sales_month) order by sales_month),2) as avg_men_sales_ytd,
    round(avg(Women_monthly_sales) over (partition by date_part('year', sales_month) order by sales_month),2) as avg_women_sales_ytd
from menwomensales_view;

-- calculating the monthly maximum ytd
select sales_month, men_monthly_sales,Women_monthly_sales,
    max(Men_monthly_sales) over (partition by date_part('year', sales_month) order by sales_month) as max_men_sales_ytd,
    max(Women_monthly_sales) over (partition by date_part('year', sales_month) order by sales_month) as max_women_sales_ytd
from menwomensales_view;
  

-- PERIOD OVER PERIOD COMPARISONS: YoY and MoM
-- Calculating month over month (MoM) growth for the bookstore business
-- So we first need to pivot the book store category into column from the retail_sales dataset
select sales_month,
    sum(case when kind_of_business = 'Book stores' then sales end) as Bookstore_monthly_sales
from retail_sales
group by sales_month
order by sales_month;

-- MoM calculation
select sales_month, bookstore_monthly_sales,
    lag(sales_month) over (order by sales_month) as previous_month,
    lag(bookstore_monthly_sales) over (order by sales_month) as prev_month_sales
from Bookstore_sales_view;


-- Another approach is to use a with statement to pre-pivot the data before making subsequent calculations
with Bookstore_Monthly_data as (
    select sales_month,
    sum(case when kind_of_business = 'Book stores' then sales end) as Bookstore_monthly_sales
from retail_sales
group by sales_month
order by sales_month)
-- MoM calculation
select sales_month, bookstore_monthly_sales,
    lag(sales_month) over (order by sales_month) as previous_month,
    lag(bookstore_monthly_sales) over (order by sales_month) as prev_month_sales,
-- We can calculate percent growth from previous month sales
    (bookstore_monthly_sales/lag(bookstore_monthly_sales) over (order by sales_month)-1) * 100 as pct_growth_from_previous
from Bookstore_Monthly_data;


-- Calculating year over year (YoY) growth for the bookstore business
-- But first we first need to aggregate the sales yearly
with Bookstore_data as (
    select extract(year from sales_month) as sales_year,
    sum(case when kind_of_business = 'Book stores' then sales end) as Bookstore_yearly_sales
from retail_sales
group by 1
order by 1)
select 
    sales_year,
    Bookstore_yearly_sales,
    -- YoY calculation
    lag(sales_year) over (order by sales_year) as prev_year,
    lag(Bookstore_yearly_sales) over (order by sales_year) as prev_year_sales,
    -- We can calculate percent growth from previous month sales
    round((bookstore_yearly_sales/lag(bookstore_yearly_sales) over (order by sales_year)-1) * 100,2) as pct_growth_from_prev_year
from Bookstore_data;


-- PERIOD OVER PERIOD COMPARISONS: Same Month versus Same Month last Year
-- first lets confirm that the lag function returns the same month of last year in the partition by clause
create view Bookstore_sales_view as
with Bookstore_Monthly_data as (
    select sales_month,
    sum(case when kind_of_business = 'Book stores' then sales end) as Bookstore_monthly_sales
from retail_sales
group by sales_month
order by sales_month)
-- MoM calculation
select sales_month, bookstore_monthly_sales,
    lag(sales_month) over (partition by date_part('month', sales_month) order by sales_month) as prev_year_month,
    lag(bookstore_monthly_sales) over (partition by date_part('month', sales_month) order by sales_month) as prev_years_month_sales,
-- Now we can calculate the absolute difference and percentage change from previous value
    bookstore_monthly_sales - lag(bookstore_monthly_sales) over (partition by date_part('month', sales_month) order by sales_month) as absolute_diff,
    round((bookstore_monthly_sales / lag(bookstore_monthly_sales) over (partition by date_part('month', sales_month) order by sales_month) -1) * 100,2) as pct_diff
from Bookstore_Monthly_data;

select max(pct_diff), min(pct_diff) from bookstore_sales_view;
select * from bookstore_sales_view;


-- Creating a graph that lines up the same time period with a line for each time series
create view booksales_9294_timeline_view as
select date_part('month',sales_month) as month_number,
    to_char(sales_month, 'Month') as month_name,
    max(case when date_part('year',sales_month) = 1992 then bookstore_monthly_sales end) as sales_1992,
    max(case when date_part('year',sales_month) = 1993 then bookstore_monthly_sales end) as sales_1993,
    max(case when date_part('year',sales_month) = 1994 then bookstore_monthly_sales end) as sales_1994
from bookstore_sales_view
where sales_month between '1992-01-01' and '1994-12-01'
group by 1,2;


-- COMPARING TO MULTIPLE PRIOR PERIODS
-- lets compare current sales to what sales was in the last three years
select sales_month, bookstore_monthly_sales,
    lag(bookstore_monthly_sales, 3) over (partition by extract(month from sales_month) order by sales_month) as last_3yrs_sales
from bookstore_sales_view;

-- Compare the percent of the rolling average of three prior periods
select sales_month, bookstore_monthly_sales,
    bookstore_monthly_sales * 100 / avg(bookstore_monthly_sales) over 
    (partition by date_part('month', sales_month) order by sales_month
    rows between 3 preceding and 1 preceding) as pctage_of_prev_3
from bookstore_sales_view;
