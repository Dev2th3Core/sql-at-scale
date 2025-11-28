-- Generates(approx):
--   ~1,000 Orders
--   ~2,500 OrderItems (avg 2–3 items per order)
--   ~900 Payments (most orders paid, some pending/cancelled)

USE OrderManagement;
GO

---------------------------------------
-- 0. Clear existing transactional data
---------------------------------------
-- Order of delete: children -> parents
DELETE FROM dbo.Payments;
DELETE FROM dbo.OrderItems;
DELETE FROM dbo.Orders;
GO

---------------------------------------
-- 1. Basic counts & sanity checks
---------------------------------------
DECLARE @CustomerCount INT = (SELECT COUNT(*) FROM dbo.Customers);
DECLARE @ProductCount  INT = (SELECT COUNT(*) FROM dbo.Products);

IF @CustomerCount = 0
BEGIN
    RAISERROR('No customers found. Please run seed_customers.sql first.', 16, 1);
    RETURN;
END;

IF @ProductCount = 0
BEGIN
    RAISERROR('No products found. Please run seed_products.sql first.', 16, 1);
    RETURN;
END;

---------------------------------------
-- 2. Config: how many orders to create
---------------------------------------
DECLARE @TargetOrders INT = 1000;
DECLARE @OrderIndex   INT = 1;

---------------------------------------
-- 3. Main loop: create Orders, Items, Payments
---------------------------------------
WHILE @OrderIndex <= @TargetOrders
BEGIN
    ------------------------
    -- 3.1 Pick a customer
    ------------------------
    DECLARE @CustomerId INT =
        1 + ABS(CHECKSUM(NEWID())) % @CustomerCount; -- assumes CustomerId ~ 1..@CustomerCount (OK for seed)

    ------------------------
    -- 3.2 Order date (last 365 days)
    ------------------------
    DECLARE @DaysAgo INT = ABS(CHECKSUM(NEWID())) % 365;
    DECLARE @OrderDate DATETIME2(0) = DATEADD(DAY, -@DaysAgo, SYSUTCDATETIME());

    ------------------------
    -- 3.3 Status distribution
    -- We want ~90% of orders to have payments.
    -- Let's define:
    --  50% Paid
    --  20% Shipped
    --  15% Delivered
    --  10% Pending
    --   5% Cancelled
    ------------------------
    DECLARE @StatusRoll INT = ABS(CHECKSUM(NEWID())) % 100 + 1;
    DECLARE @Status NVARCHAR(20);

    IF @StatusRoll BETWEEN 1 AND 50
        SET @Status = N'Paid';
    ELSE IF @StatusRoll BETWEEN 51 AND 70
        SET @Status = N'Shipped';
    ELSE IF @StatusRoll BETWEEN 71 AND 85
        SET @Status = N'Delivered';
    ELSE IF @StatusRoll BETWEEN 86 AND 95
        SET @Status = N'Pending';
    ELSE
        SET @Status = N'Cancelled';

    ------------------------
    -- 3.4 Create the Order (TotalAmount = 0 for now)
    ------------------------
    INSERT INTO dbo.Orders (CustomerId, OrderDate, Status, TotalAmount)
    VALUES (@CustomerId, @OrderDate, @Status, 0);

    DECLARE @OrderId INT = SCOPE_IDENTITY();

    ------------------------
    -- 3.5 Create OrderItems (2 to 4 items per order)
    ------------------------
    DECLARE @ItemCount INT = 2 + (ABS(CHECKSUM(NEWID())) % 3); -- 2, 3, or 4
    DECLARE @ItemIndex INT = 1;

    WHILE @ItemIndex <= @ItemCount
    BEGIN
        -- Pick a random product directly from table (no more 1..@ProductCount assumption)
        DECLARE @ProductId INT;
        DECLARE @UnitPrice DECIMAL(18,2);

        SELECT TOP 1
            @ProductId = p.ProductId,
            @UnitPrice = p.UnitPrice
        FROM dbo.Products AS p
        ORDER BY NEWID();  -- random row

        -- Safety check (unlikely to hit, but good practice)
        IF @ProductId IS NULL OR @UnitPrice IS NULL
        BEGIN
            SET @ItemIndex += 1;
            CONTINUE;
        END;

        -- Quantity between 1 and 5
        DECLARE @Quantity INT = 1 + (ABS(CHECKSUM(NEWID())) % 5);

        INSERT INTO dbo.OrderItems (OrderId, ProductId, Quantity, UnitPrice)
        VALUES (@OrderId, @ProductId, @Quantity, @UnitPrice);

        SET @ItemIndex += 1;
    END;

    ------------------------
    -- 3.6 Update Order.TotalAmount from OrderItems
    ------------------------
    DECLARE @TotalAmount DECIMAL(18,2);

    SELECT @TotalAmount = ISNULL(SUM(LineTotal), 0)
    FROM dbo.OrderItems
    WHERE OrderId = @OrderId;

    UPDATE dbo.Orders
    SET TotalAmount = @TotalAmount
    WHERE OrderId = @OrderId;

    ------------------------
    -- 3.7 Create Payment (for most orders)
    -- Rules:
    --   - No payments for Cancelled.
    --   - Payments always for Paid / Shipped / Delivered.
    --   - For Pending: 50% chance of having a payment.
    ------------------------
    DECLARE @CreatePayment BIT = 0;

    IF @Status IN (N'Paid', N'Shipped', N'Delivered')
    BEGIN
        SET @CreatePayment = 1;
    END
    ELSE IF @Status = N'Pending'
    BEGIN
        DECLARE @PendingRoll INT = ABS(CHECKSUM(NEWID())) % 100 + 1;
        IF @PendingRoll <= 50
            SET @CreatePayment = 1;  -- around half pending have payments
    END

    IF @CreatePayment = 1 AND @TotalAmount > 0
    BEGIN
        -- Single full payment for now (no partial payments in Stage 01)
        DECLARE @Method NVARCHAR(20);

        DECLARE @MethodRoll INT = ABS(CHECKSUM(NEWID())) % 4 + 1;
        SET @Method =
            CASE @MethodRoll
                WHEN 1 THEN N'Card'
                WHEN 2 THEN N'UPI'
                WHEN 3 THEN N'NetBanking'
                ELSE N'COD'
            END;

        DECLARE @PaidAt DATETIME2(0) =
            DATEADD(HOUR, (ABS(CHECKSUM(NEWID())) % 72), @OrderDate); -- within 3 days of order

        DECLARE @ReferenceNumber NVARCHAR(100) =
            N'PMT-' + CAST(@OrderId AS NVARCHAR(10)) + N'-' +
            RIGHT(CAST(ABS(CHECKSUM(NEWID())) AS NVARCHAR(20)), 6);

        INSERT INTO dbo.Payments (OrderId, PaidAmount, PaidAt, Method, ReferenceNumber)
        VALUES (@OrderId, @TotalAmount, @PaidAt, @Method, @ReferenceNumber);
    END;

    ------------------------
    -- Next order
    ------------------------
    SET @OrderIndex += 1;
END;
GO

---------------------------------------
-- 4. Sanity checks
---------------------------------------
PRINT 'Row counts after seeding:';
SELECT
    (SELECT COUNT(*) FROM dbo.Customers)   AS CustomersCount,
    (SELECT COUNT(*) FROM dbo.ProductCategories) AS CategoriesCount,
    (SELECT COUNT(*) FROM dbo.Products)    AS ProductsCount,
    (SELECT COUNT(*) FROM dbo.Orders)      AS OrdersCount,
    (SELECT COUNT(*) FROM dbo.OrderItems)  AS OrderItemsCount,
    (SELECT COUNT(*) FROM dbo.Payments)    AS PaymentsCount;
GO

-- Optional: quick look at some data
SELECT TOP 10
    o.OrderId,
    o.OrderDate,
    o.Status,
    o.TotalAmount,
    c.FirstName,
    c.LastName
FROM dbo.Orders o
JOIN dbo.Customers c ON c.CustomerId = o.CustomerId
ORDER BY o.OrderId;

SELECT TOP 10
    oi.OrderItemId,
    oi.OrderId,
    oi.ProductId,
    oi.Quantity,
    oi.UnitPrice,
    oi.LineTotal
FROM dbo.OrderItems oi
ORDER BY oi.OrderItemId;

SELECT TOP 10
    p.PaymentId,
    p.OrderId,
    p.PaidAmount,
    p.PaidAt,
    p.Method,
    p.ReferenceNumber
FROM dbo.Payments p
ORDER BY p.PaymentId;
GO

-- Quick Count Check
SELECT COUNT(*) AS TotalOrders
FROM dbo.Orders;
GO

SELECT COUNT(*) AS TotalOrderItems
FROM dbo.OrderItems;
GO

SELECT COUNT(*) AS TotalPayments
FROM dbo.Payments;
GO
