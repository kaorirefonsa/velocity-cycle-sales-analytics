/*
 * Q: What is the overall scale and timeframe of this business?
 * Total sales: 18.097
 * Sales duration: January 2012 to December 2013
 * Total revenue: $86,641,588.2752 or  $86M
 * 
 */

-- Q: What is the overall scope and scale of this business during 2012-2013?
SELECT 
    COUNT(*) AS total_orders,
    MIN(orderdate) AS start_date,
    MAX(orderdate) AS end_date,
    SUM(totaldue) AS total_revenue,
    round(sum(totaldue)/count(*),2) as AOV
FROM sales.salesorderheader
where extract (year from orderdate) between 2012 and 2013;

-- Q: How do monthly and quarterly sales trend during this period?
/* June-July are a reliable peak across both years, consistently 
 * above the $3.61M monthly average — a window worth aligning marketing 
 * spend and inventory buildup around.
 * February and April are consistently below average both years —
 * a structural low, not a one-off dip.
 */
SELECT
    EXTRACT(YEAR FROM orderdate) AS year,
    EXTRACT(MONTH FROM orderdate) AS month,
    SUM(totaldue) AS revenue,
    ROUND(AVG(SUM(totaldue)) OVER (), 2) AS avg_monthly_revenue,
    ROUND((SUM(totaldue) - AVG(SUM(totaldue)) OVER ()) / AVG(SUM(totaldue)) OVER () * 100, 2) AS variance_pct
FROM sales.salesorderheader
WHERE EXTRACT(YEAR FROM orderdate) BETWEEN 2012 AND 2013
GROUP BY year, month
ORDER BY year, month, revenue desc;

-- Q: Which quarters are structurally strong or weak, relative to each year's own average?
/* 
 * Based on quarterly trends, Q3 is strong in both years (+7.91% in 2012, +17.14% in 2013).
 * The oprations team could benefit from this data by increasing inventory in Q3 as
 * understocking during a known peak could result in a lost-revenue risk.
 */
SELECT  
EXTRACT(YEAR FROM orderdate) AS YEAR,    
EXTRACT(QUARTER FROM orderdate) AS quarter,
    SUM(totaldue) AS revenue,
    ROUND(AVG(SUM(totaldue)) OVER (PARTITION BY EXTRACT(YEAR FROM orderdate)), 2) AS avg_quarterly_revenue,
    ROUND((SUM(totaldue) - AVG(SUM(totaldue)) OVER (PARTITION BY EXTRACT(YEAR FROM orderdate))) / AVG(SUM(totaldue)) OVER (PARTITION BY EXTRACT(YEAR FROM orderdate)) * 100, 2) AS variance_pct
FROM sales.salesorderheader
WHERE EXTRACT(YEAR FROM orderdate) BETWEEN 2012 AND 2013
GROUP BY year, quarter
ORDER BY year, quarter;

-- Q: How does revenue and AOV differ between online and offline channels each quarter?
/* 
 */
select 
	extract(year from orderdate) as YEAR,
	extract(quarter from orderdate) as quarter,
	sum(totaldue) as total_revenue,
	count(*) as total_transaction,
	sum(totaldue)/count(*) as avg_order_value,
	onlineorderflag
from sales.salesorderheader s
where extract (year from orderdate) between 2012 and 2013
group by onlineorderflag, quarter, year
order by year, quarter asc, onlineorderflag desc;

-- Q: What is the average number of offline quarterly transactions?
with tc as(
select
	extract (year from orderdate) as year,
	extract (quarter from orderdate) as quarter,
	count(*) as transaction_count
	from sales.salesorderheader s
	where extract(year from orderdate) between 2012 and 2013 and onlineorderflag = false
	group by year, quarter
	order by year, quarter)
select avg(transaction_count) as avg_quarterly_transaction
from tc;

-- Q: How does average order value compare between offline and online channels?
select 
	onlineorderflag as online,
	round(sum(totaldue)/count(*),2) as aov
from sales.salesorderheader s 
where extract (year from orderdate) between 2012 and 2013
group by onlineorderflag ;

-- Q: Which products generate the most revenue?
WITH total AS (
    SELECT
        REGEXP_REPLACE(SPLIT_PART(p.name, ',', 1), '\s+\S+$', '') AS base_model,
        AVG(unitprice) AS avg_price,
        pc.name as category_name,
        SUM(orderqty) AS total_quantity,
        ROUND(SUM(unitprice * orderqty * (1 - unitpricediscount)), 2) AS linetotal,
        ROUND(SUM(unitprice * orderqty * (1 - unitpricediscount)) / SUM(SUM(unitprice * orderqty * (1 - unitpricediscount))) OVER () * 100, 2) AS revenue_pct
    FROM sales.salesorderdetail s
    join sales.salesorderheader s2 on s.salesorderid = s2.salesorderid
    JOIN production.product p ON s.productid = p.productid
    JOIN production.productsubcategory p2 ON p.productsubcategoryid = p2.productsubcategoryid
    JOIN production.productcategory pc ON p2.productcategoryid = pc.productcategoryid
   where extract (year from orderdate) between 2012 and 2013
    GROUP BY REGEXP_REPLACE(SPLIT_PART(p.name, ',', 1), '\s+\S+$', ''), category_name
    ORDER BY linetotal desc
    LIMIT 10
)
SELECT base_model, avg_price, category_name, total_quantity, linetotal, revenue_pct, sum(revenue_pct) over()
FROM total;

-- Q: Which customers are most valuable, based on recency, frequency, and monetary value?
WITH rfm AS (
    SELECT
        customerid,
        MAX(orderdate) AS last_order,
        ('2013-12-31'::date - MAX(orderdate)::date) AS recency_days,
        COUNT(*) AS frequency,
        SUM(totaldue) AS monetary
    FROM sales.salesorderheader
    WHERE EXTRACT(YEAR FROM orderdate) BETWEEN 2012 AND 2013
    GROUP BY customerid
),
segmented AS (
    SELECT *,
        CASE
            WHEN frequency > 2 AND monetary > 2699.90 AND recency_days < 365 THEN 'Champion'
            WHEN frequency > 2 AND monetary > 2699.90 AND recency_days >= 365 THEN 'Lapsed Champion'
            WHEN frequency > 2 AND monetary <= 2699.90 THEN 'Loyal'
            WHEN frequency <= 2 AND monetary > 2699.90 THEN 'Big Spender'
            ELSE 'At Risk'
        END AS segment
    FROM rfm
),
segment_summary AS (
    SELECT segment, COUNT(*) AS customer_count,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS customer_pct
    FROM segmented
    GROUP BY segment
),
segment_revenue AS (
    SELECT segmented.segment, ROUND(SUM(h.totaldue), 2) AS revenue
    FROM segmented
    JOIN sales.salesorderheader h ON h.customerid = segmented.customerid
    GROUP BY segmented.segment
)
SELECT ss.segment, ss.customer_count, ss.customer_pct, sr.revenue
FROM segment_summary ss
JOIN segment_revenue sr ON ss.segment = sr.segment
ORDER BY sr.revenue DESC;



-- Q: Which product categories does each customer segment spend on?
CREATE VIEW customer_rfm_segments AS
WITH rfm AS (
    SELECT
        customerid,
        MAX(orderdate) AS last_order,
        ('2013-12-31'::date - MAX(orderdate)::date) AS recency_days,
        COUNT(*) AS frequency,
        SUM(totaldue) AS monetary
    FROM sales.salesorderheader
    WHERE EXTRACT(YEAR FROM orderdate) BETWEEN 2012 AND 2013
    GROUP BY customerid
)
SELECT *,
    CASE
        WHEN frequency > 2 AND monetary > 2699.90 AND recency_days < 365 THEN 'Champion'
        WHEN frequency > 2 AND monetary > 2699.90 AND recency_days >= 365 THEN 'Lapsed Champion'
        WHEN frequency > 2 AND monetary <= 2699.90 THEN 'Loyal'
        WHEN frequency <= 2 AND monetary > 2699.90 THEN 'Big Spender'
        ELSE 'At Risk'
    END AS segment
FROM rfm;

with RFM_analysis as (
SELECT crs.customerid, crs.segment, p.name, SUM(h.totaldue) AS revenue, COUNT(*) AS items_bought
FROM customer_rfm_segments crs
JOIN sales.salesorderheader h ON h.customerid = crs.customerid
JOIN sales.salesorderdetail d ON d.salesorderid = h.salesorderid
JOIN production.product pr ON d.productid = pr.productid
JOIN production.productsubcategory sc ON pr.productsubcategoryid = sc.productsubcategoryid
JOIN production.productcategory p ON sc.productcategoryid = p.productcategoryid
GROUP BY crs.customerid, crs.segment, p.name
ORDER BY crs.customerid, revenue desc)
select segment, RFM_Analysis.name, SUM(RFM_Analysis.revenue) as rev
from RFM_analysis
group by segment, RFM_Analysis.name
order by segment, RFM_Analysis.name, rev desc;

-- Q: Which product category dominates revenue?
select
	p2.productcategoryid,
	pc.name,
	SUM(s.unitprice * s.orderqty * (1 - s.unitpricediscount)) as revenue,
	ROUND(SUM(s.unitprice * s.orderqty * (1 - s.unitpricediscount)) / SUM(SUM(s.unitprice * s.orderqty * (1 - s.unitpricediscount))) OVER () * 100, 2) AS revenue_pct
from sales.salesorderdetail s
join sales.salesorderheader soh on s.salesorderid = soh.salesorderid
join production.product p on s.productid = p.productid
join production.productsubcategory p2 on p.productsubcategoryid = p2.productsubcategoryid
JOIN production.productcategory pc ON p2.productcategoryid = pc.productcategoryid
WHERE EXTRACT(YEAR FROM soh.orderdate) BETWEEN 2012 AND 2013
GROUP BY p2.productcategoryid, pc.name
order by revenue desc;


-- Q: Which territory generates the most revenue?
SELECT
    s2.group,
    s2.name,
    COUNT(*) AS total_orders,
    SUM(totaldue) AS total_revenue,
    ROUND(AVG(totaldue), 2) AS aov,
    ROUND(SUM(totaldue) * 100.0 / SUM(SUM(totaldue)) OVER (), 2) AS pct_revenue
FROM sales.salesorderheader s
JOIN sales.salesterritory s2 ON s.territoryid = s2.territoryid
where extract (year from orderdate) between 2012 and 2013
GROUP BY s2.group, s2.name
ORDER BY total_revenue desc;

-- Q: Which countries generate the most revenue?
SELECT
    s2.countryregioncode,
    SUM(totaldue) AS total_revenue,
    COUNT(*) AS total_orders
FROM sales.salesorderheader s
JOIN sales.salesterritory s2 ON s.territoryid = s2.territoryid
WHERE EXTRACT(YEAR FROM orderdate) BETWEEN 2012 AND 2013
GROUP BY s2.countryregioncode
ORDER BY total_revenue DESC;
