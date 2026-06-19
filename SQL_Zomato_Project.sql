create database zomato_Project

use zomato_project

select * from zomato_cleaned_data


with cleaned as (select 
	Order_id, 
	Customer_name, 
	City, 
	Restaurant_name, 
	Cuisine , 
	round(order_amount,2) as Order_amount, 
	round(delivery_time_min,1) as Delivery_time_min , 
	Rating, 
	Payment_method, 
	Delivery_status, 
	Discount_percent, 
	Order_date, 
	round(Customer_age,0) as Customer_age, 
	round(distance_km,2) as Distance_km
from zomato_cleaned_Data
)
select * into zomato_temp from cleaned

select * from zomato_temp

delete from zomato_temp
where customer_name = 'unknown';

--	Highest Sales by which type of cuisine

with high_Sales_Cuisine as (
 select 
		cuisine,
		round(sum(Order_amount),2) Total_Sales,
		Dense_RANK() over (order by round(sum(Order_amount),2) desc) as rnk
 from zomato_temp
 group by cuisine
)
select cuisine,Total_Sales from high_Sales_Cuisine
where rnk=1


--Which cuisines have the highest average rating?

with high_rated_cuisine as (
 select cuisine, round(avg(Rating),2) Ratings, Dense_RANK() over (order by round(avg(rating),2) desc) as rnk
 from zomato_temp
 group by cuisine
)
select cuisine,Ratings from high_rated_cuisine
where rnk=1

--Revenue lost due to cancelled orders
select round(sum(Order_amount),2) as Revenue from zomato_temp
where Delivery_status='Cancelled'

--Cancellation Rate
select round(avg(case
when delivery_status='Cancelled' then 1.0
else 0.0
end
)*100.0,2) as Rate_of_cancellation
from zomato_temp

--Top Restaurant in Every City
select * from zomato_temp

with Top_Restaurant as (
Select 
    City,
    Restaurant_name,
    round(sum(order_amount),2) Revenue,
    DENSE_RANK() over(partition by City order by round(sum(order_amount),2) desc) as rnk
from zomato_temp
group by City,Restaurant_name
)
select * from Top_restaurant
where rnk=1
order by revenue desc

--Monthly Revenue Trend
SELECT
    Format(Order_Date,'yyyy-MM') AS Month,
    Round(SUM(Order_Amount),2) AS Revenue
FROM zomato_temp
Group BY Format(Order_Date,'yyyy-MM')
Order BY Month;


--Find Customers Who Spend More Than Average
select 
        Customer_name,
        round(sum(order_amount),2) Total_Spend
from zomato_temp
group by Customer_name
having round(sum(order_amount),2)>
(
select round(avg(Order_amount),2) from zomato_temp
)



--1. Customer Segmentation (RFM Analysis)
--Finds the most valuable customers and ranks them into 4 tiers based on their total spend.

WITH CustomerStats AS (
    SELECT 
        Customer_name,
        MAX(Order_date) AS Last_Order_Date,
        COUNT(Order_id) AS Total_Orders,
        SUM(Order_amount) AS Total_Spend
    FROM zomato_temp
    WHERE Delivery_status = 'Delivered'
    GROUP BY Customer_name
)
SELECT 
    Customer_name,
    Total_Orders,
    Total_Spend,
    -- Calculate days since their last order compared to the most recent date in the dataset
    DATEDIFF(day, Last_Order_Date, (SELECT MAX(Order_date) FROM zomato_temp)) AS Days_Since_Last_Order,
    -- Group customers into 4 tiers (1 is lowest spend, 4 is highest spend)
    NTILE(4) OVER (ORDER BY Total_Spend ASC) AS Spend_Tier
FROM CustomerStats
ORDER BY Spend_Tier DESC, Total_Spend DESC;


--2. Month-Over-Month (MoM) Revenue Growth
--Calculates how much revenue grew (or shrank) compared to the previous month.

WITH MonthlyRevenue AS (
    SELECT 
        YEAR(Order_date) AS Order_Year,
        MONTH(Order_date) AS Order_Month,
        SUM(Order_amount) AS Total_Revenue
    FROM zomato_temp
    WHERE Delivery_status = 'Delivered'
    GROUP BY YEAR(Order_date), MONTH(Order_date)
),
RevenueGrowth AS (
    SELECT 
        Order_Year,
        Order_Month,
        Total_Revenue,
        LAG(Total_Revenue) OVER (ORDER BY Order_Year, Order_Month) AS Prev_Month_Revenue
    FROM MonthlyRevenue
)
SELECT 
    Order_Year,
    Order_Month,
    Total_Revenue,
    Prev_Month_Revenue,
    -- Calculate MoM Growth Percentage
    ROUND(((Total_Revenue - Prev_Month_Revenue) / NULLIF(Prev_Month_Revenue, 0)) * 100, 2) AS MoM_Growth_Percent
FROM RevenueGrowth;



--3. Delivery Anomaly Detection
--Flags specific orders that took significantly longer than a restaurant's average delivery time in that city.

WITH CityAvgDelivery AS (
    SELECT 
        City,
        AVG(Delivery_time_min) AS Avg_City_Delivery
    FROM zomato_temp
    WHERE Delivery_status = 'Delivered'
    GROUP BY City
)
SELECT 
    z.Order_id,
    z.Restaurant_name,
    z.City,
    z.Distance_km,
    z.Delivery_time_min AS Actual_Delivery_Time,
    ROUND(c.Avg_City_Delivery, 2) AS Avg_City_Delivery,
    (z.Delivery_time_min - c.Avg_City_Delivery) AS Delay_Minutes
FROM zomato_temp z
JOIN CityAvgDelivery c 
    ON z.City = c.City
-- Flagging orders that took at least 15 minutes longer than the overall CITY average
WHERE z.Delivery_time_min > (c.Avg_City_Delivery + 15)
  AND z.Delivery_status = 'Delivered'
ORDER BY Delay_Minutes DESC;


--4. City-Level Restaurant Benchmarking
--Ranks the top-performing restaurants in each city based on revenue and compares it to their rating rank.

WITH RestaurantMetrics AS (
    SELECT 
        City,
        Restaurant_name,
        Cuisine,
        COUNT(Order_id) AS Total_Orders,
        SUM(Order_amount) AS Total_Revenue,
        AVG(Rating) AS Avg_Rating
    FROM zomato_temp
    WHERE Delivery_status = 'Delivered'
    GROUP BY City, Restaurant_name, Cuisine
)
SELECT 
    City,
    Restaurant_name,
    Cuisine,
    Total_Orders,
    Total_Revenue,
    ROUND(Avg_Rating, 2) AS Avg_Rating,
    DENSE_RANK() OVER (PARTITION BY City ORDER BY Total_Revenue DESC) AS City_Revenue_Rank,
    DENSE_RANK() OVER (PARTITION BY City ORDER BY Avg_Rating DESC) AS City_Rating_Rank
FROM RestaurantMetrics
-- The threshold filter has been removed to match your dataset size
ORDER BY City, City_Revenue_Rank;


--5. Analyzing Customer Retention (Purchase Frequency)
--Calculates the average number of days it takes for a repeat customer to place their next order.

WITH OrderDates AS (
    SELECT 
        Customer_name,
        Order_date,
        LAG(Order_date) OVER (PARTITION BY Customer_name ORDER BY Order_date) AS Previous_Order_Date
    FROM zomato_temp
    WHERE Delivery_status = 'Delivered'
)
SELECT 
    Customer_name,
    COUNT(*) + 1 AS Total_Lifetime_Orders,
    -- Average days between consecutive orders
    AVG(DATEDIFF(day, Previous_Order_Date, Order_date)) AS Avg_Days_Between_Orders
FROM OrderDates
WHERE Previous_Order_Date IS NOT NULL
GROUP BY Customer_name
ORDER BY Avg_Days_Between_Orders ASC;
