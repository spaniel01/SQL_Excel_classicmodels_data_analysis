################################## Preliminaries
### Information schema overview
SHOW DATABASES;
SHOW FULL TABLES;

#Details on classicmodels tables
SELECT *
       FROM information_schema.tables
       WHERE TABLE_SCHEMA = 'classicmodels';

#Names of columns in tables
SELECT * FROM information_schema.columns
WHERE TABLE_SCHEMA = 'classicmodels';

#Names of columns in particular table
SELECT * FROM information_schema.columns
WHERE TABLE_SCHEMA = 'classicmodels' AND TABLE_NAME = 'customers';

### Preliminary check of potential missing foreign key values for left joins
SELECT COUNT(*) FROM employees WHERE officeCode IS NULL; 
SELECT COUNT(*) FROM customers WHERE customerNumber IS NULL; 
SELECT COUNT(*) FROM orders WHERE customerNumber IS NULL;
# Not all customers in the customers table (csutomerNumber) have been assigned a sales rep (employeeNumber), which may lead to information loss when left joining customers to employees (via employeeNumber on salesRepEmployeeNumber):
SELECT * FROM employees RIGHT JOIN customers ON employeeNumber = salesRepEmployeeNumber WHERE employees.employeeNumber IS NULL;
 
################################## Data analysis
### Have order volumns increased or not across time? For graphical display
# Please note: Aggregation by year makes no sense, since start and end periods are:
SELECT MIN(orderDate), MAX(orderDate) FROM orders;
# Date variable is "standardized" in query by setting the day value to 01
SELECT offices.city, 
orderdetails.orderNumber, 
SUM(quantityOrdered*priceEach) AS order_amount,
CAST(concat_ws('-', YEAR(orderDate), MONTH(orderDate), '01') AS date) AS date_month_year
FROM offices 
LEFT JOIN employees ON offices.officeCode = employees.officeCode
LEFT JOIN customers ON employeeNumber = salesRepEmployeeNumber
LEFT JOIN orders ON customers.customerNumber = orders.customerNumber
LEFT JOIN orderdetails ON orders.orderNumber = orderdetails.orderNumber
WHERE orderDetails.orderNumber IS NOT NULL
GROUP BY offices.city, YEAR(orderDate), MONTH(orderDate)
ORDER BY city, date_month_year;

### Customer number and total sales by country (including customers with NULL total_sales)
SELECT country, COUNT(DISTINCT customerNumber) AS N_customers, SUM(priceEach*quantityOrdered) AS total_sales 
FROM (SELECT country, customerNumber, orderNumber FROM orders LEFT JOIN customers USING(customerNumber)
      UNION
      SELECT country, customerNumber, orderNumber FROM orders RIGHT JOIN customers USING(customerNumber)) as ocFull
LEFT JOIN orderdetails ON orderdetails.orderNumber = ocFull.orderNumber
GROUP BY country
ORDER BY total_sales DESC;

### Which are the biggest customers and which offices are they administered by?
SELECT offices.city AS office_branch, customerNumber, SUM(quantityOrdered*priceEach) AS order_amount
FROM orderDetails
LEFT JOIN orders USING(orderNumber)
LEFT JOIN customers USING(customerNumber)
LEFT JOIN employees ON employeeNumber = salesRepEmployeeNumber
LEFT JOIN offices USING(officeCode)
GROUP BY customerNumber 
ORDER BY order_amount DESC
LIMIT 10;

### Employees, customers and sales by office
SELECT offices.city, 
COUNT(DISTINCT employeeNumber) AS N_employees,
COUNT(DISTINCT ecFull.customerNumber) AS N_customers,
ROUND(COUNT(DISTINCT ecFull.customerNumber)/COUNT(DISTINCT employeeNumber), 1) AS employee_to_customer_ratio,
SUM(quantityOrdered * priceEach) AS total_order_amount,  
ROUND(SUM(quantityOrdered * priceEach)/ COUNT(DISTINCT ecFull.customerNumber), 2) AS customer_to_total_order_ratio
FROM offices LEFT JOIN (
SELECT * FROM customers
LEFT JOIN employees ON employeeNumber = salesRepEmployeeNumber
UNION
SELECT * FROM customers 
RIGHT JOIN employees ON employeeNumber = salesRepEmployeeNumber) AS ecFull USING(officeCode) 
LEFT JOIN orders AS o ON ecFull.customerNumber = o.customerNumber
LEFT JOIN orderDetails AS od ON o.orderNumber = od.orderNumber 
WHERE quantityOrdered IS NOT NULL
GROUP BY offices.city ORDER BY total_order_amount DESC;

### Employee performance as sum of sales
SELECT oecFull.city, employeeNumber, 
COUNT(DISTINCT customerNumber) AS N_customers, 
SUM(quantityOrdered * priceEach) AS total_sales
FROM 
(SELECT oeFull.city, employeeNumber, customerNumber FROM (SELECT * FROM offices LEFT JOIN employees USING(officeCode)) AS oeFull
LEFT JOIN customers ON employeeNumber = salesRepEmployeeNumber
UNION
SELECT oeFull2.city, employeeNumber, customerNumber FROM (SELECT * FROM offices LEFT JOIN employees USING(officeCode)) AS oeFull2
RIGHT JOIN customers ON employeeNumber = salesRepEmployeeNumber) AS oecFull 
LEFT JOIN orders USING(customerNumber)
LEFT JOIN orderdetails USING(orderNumber)
GROUP BY employeeNumber
HAVING COUNT(DISTINCT customerNumber) <> 0
ORDER BY total_sales DESC;

### Which product lines are most successful? year and month variable as potential grouping variables for subsequent analysis in Excel
SELECT YEAR(orderDate) AS year,
MONTH(orderDate) AS month,
productLine, 
SUM(quantityOrdered*priceEach) AS sales_sum
FROM products 
LEFT JOIN orderdetails USING(productCode)
LEFT JOIN orders USING(orderNumber)
WHERE quantityOrdered IS NOT NULL
GROUP BY productLine, YEAR(orderDate), MONTH(orderDate)
ORDER BY productLine, year;

### Which products are the most popular? Which bring in most money?
SELECT productLine, 
productName, 
SUM(quantityOrdered) AS N_ordered,
quantityOrdered*priceEach AS order_amount
FROM products 
LEFT JOIN orderdetails USING (productCode)
LEFT JOIN productlines USING(productLine)
GROUP BY productName
ORDER BY order_amount DESC;

### Total number of orders, average order amount, sd, max and min sales
SELECT (SELECT COUNT(orderNumber) FROM (SELECT DISTINCT orderNumber FROM orderdetails) as N_orders) AS N_orders, 
SUM(total_by_order) AS orders_sum, 
ROUND(AVG(total_by_order),2) AS average, 
ROUND(STD(total_by_order),2) AS std, 
MIN(total_by_order) AS min,
MAX(total_by_order) AS max
FROM (SELECT
SUM(quantityOrdered*priceEach) AS total_by_order #Why did putting sum here fix the problem?
FROM orderdetails
GROUP BY orderNumber
HAVING ROUND(AVG(quantityOrdered*priceEach),2) IS NOT NULL) AS aggregateOrders;
# Sanity check
SELECT COUNT(DISTINCT orderNumber) FROM orderdetails;

### Current demand and stock, average and other order specs
SELECT productName, 
quantityInStock,
SUM(quantityOrdered) AS N_ordered_2005,
SUM(quantityOrdered)/ quantityInStock AS stock_to_order_ratio,
quantityOrdered*priceEach AS order_amount_2005,
MAX(quantityOrdered) AS max_quant_ordered, 
MIN(quantityOrdered) AS min_quant_ordered, 
AVG(quantityOrdered) AS mean_quant_ordered, 
ROUND(STD(quantityOrdered), 2) AS std_quant_ordered
FROM products 
LEFT JOIN orderdetails USING (productCode)
LEFT JOIN orders USING (orderNumber)
WHERE YEAR(orderDate) = 2005
GROUP BY productName 
ORDER BY stock_to_order_ratio DESC;

# Note 1985 Toyota Supra, no price, no sales
SELECT priceEach, quantityInStock, quantityOrdered FROM products LEFT JOIN orderdetails USING (productCode) WHERE productName = '1985 Toyota Supra';

### Elapsed time between order and shipping, btw ship and required
SELECT orderNumber, orderDate, shippedDate, requiredDate,
DATEDIFF(shippedDate, orderDate) AS order_to_ship,
DATEDIFF(requiredDate, shippedDate) - 5  AS delay
FROM orders
WHERE YEAR(orderDate) = 2005 AND shippedDate IS NOT NULL
ORDER BY delay ASC;

# Analysis I: order_to_ship count and perc of N of days required
SELECT 
DATEDIFF(shippedDate, orderDate) AS order_to_ship_days,
COUNT(DATEDIFF(shippedDate, orderDate)) AS N_order_to_ship_cat,
ROUND(COUNT(DATEDIFF(shippedDate, orderDate))/
(SELECT COUNT(*) FROM orders WHERE YEAR(orderDate) = 2005 AND shippedDate IS NOT NULL)*100, 2) AS perc_order_to_ship_cat
FROM orders
WHERE YEAR(orderDate) = 2005 AND shippedDate IS NOT NULL
GROUP BY DATEDIFF(shippedDate, orderDate)
ORDER BY order_to_ship_days;

# Analysis II: ship to required count and perc of N days delayed
SELECT 
DATEDIFF(requiredDate, shippedDate) - 5 AS ship_to_required_days,
COUNT(DATEDIFF(requiredDate, shippedDate)) AS N_ship_to_required,
ROUND(COUNT(DATEDIFF(requiredDate, shippedDate))/
(SELECT COUNT(*) FROM orders WHERE YEAR(orderDate) = 2005 AND shippedDate IS NOT NULL)*100, 2) AS perc_ship_to_required_cat
FROM orders
WHERE YEAR(orderDate) = 2005 AND shippedDate IS NOT NULL
GROUP BY DATEDIFF(requiredDate, shippedDate)
ORDER BY ship_to_required_days;

### Elapsed time btw shipping and payment and paid_before_ship boolean
SELECT shippedDate, paymentDate, DATEDIFF(paymentDate, shippedDate) AS time_elapsed_ship_to_pay, 
(CASE WHEN DATEDIFF(paymentDate, shippedDate) < 0 THEN 1 ELSE 0 END) AS paid_before_ship 
FROM payments 
LEFT JOIN customers USING(customerNumber)
LEFT JOIN orders USING(customerNumber)
ORDER BY time_elapsed_ship_to_pay DESC;

# Analysis: paid_before_ship boolean, N, perc, mean_time_elapsed
SELECT 
(CASE WHEN DATEDIFF(paymentDate, shippedDate) < 0 THEN 1 ELSE 0 END) AS paid_before_ship, 
COUNT(*) AS N, 
ROUND(COUNT(*)/ (SELECT COUNT(*) 
FROM payments 
LEFT JOIN orders USING(customerNumber))*100, 2) AS perc,
ROUND(AVG(DATEDIFF(paymentDate, shippedDate)),2) AS mean_time_elapsed_ship_to_pay 
FROM payments 
LEFT JOIN customers USING(customerNumber)
LEFT JOIN orders USING(customerNumber)
GROUP BY paid_before_ship;

### Orders status
SELECT status, 
COUNT(status) AS N_status,
ROUND(COUNT(status)/(select COUNT(*) from orders)*100, 2) AS status_perc
FROM orders
GROUP BY status
ORDER BY status_perc DESC;

### Orders cancelled and disrupted
SELECT customerNumber, orderNumber, orderDate, status, comments
FROM orders 
WHERE status IN ('Cancelled', 'On Hold', 'Disputed');


