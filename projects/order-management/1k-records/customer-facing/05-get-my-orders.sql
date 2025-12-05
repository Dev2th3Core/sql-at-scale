/****************************************************************************************
    FILE: 05-usp-get-my-orders.sql

    PURPOSE:
        Stored procedure to fetch a paginated "My Orders" list for a logged-in customer.

    CONTENTS:
        1. Procedure: dbo.usp_GetMyOrders
        2. Manual test block
****************************************************************************************/


/****************************************************************************************
    1️  STORED PROCEDURE: dbo.usp_GetMyOrders
    -----------------------------------------
    SCENARIO:
      Customer is logged in and opens the "My Orders" page.
      Backend needs to return a paginated list of their orders with basic info and
      a flag indicating whether each order has a payment.

    INPUTS:
      @CustomerId INT
        - The ID of the logged-in customer.

      @PageNumber INT = 1
        - 1-based page number (1 = first page).

      @PageSize   INT = 10
        - Number of orders per page (e.g. 10, 20, 50).

      @TotalCount INT OUTPUT
        - Total number of orders for this customer (matching current filter set,
          which currently is just CustomerId), used for UI pagination.

    BEHAVIOR:
      - Ensures @PageNumber and @PageSize have sensible minimums.
      - Optionally validates that the customer exists and is active.
      - Selects from Orders (for the given CustomerId).
      - Determines if each order has at least one payment in Payments.
      - Returns:
          * OrderId
          * OrderDate
          * Status
          * TotalAmount
          * HasPayment ('Y' or 'N')
      - Orders results by OrderDate DESC, then OrderId DESC.
      - Applies pagination via OFFSET / FETCH.
      - Sets @TotalCount to the total number of orders for that customer.
****************************************************************************************/
USE OrderManagement;
GO

IF OBJECT_ID('dbo.usp_GetMyOrders', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetMyOrders;
GO

CREATE PROCEDURE dbo.usp_GetMyOrders
(
    @CustomerId INT,
    @PageNumber INT = 1,
    @PageSize   INT = 10,
    @TotalCount INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    ------------------------------------------------------------
    -- 1. Guardrails for pagination inputs
    ------------------------------------------------------------
    IF @PageNumber < 1 SET @PageNumber = 1;
    IF @PageSize   < 1 SET @PageSize   = 10;

    ------------------------------------------------------------
    -- 2. (Optional) Validate customer exists and is active
    ------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Customers
        WHERE CustomerId = @CustomerId
          AND IsActive = 1
    )
    BEGIN
        RAISERROR('Invalid or inactive CustomerId.', 16, 1);
        RETURN;
    END;

    ------------------------------------------------------------
    -- 3. Temp table for My Orders
    --    Avoids duplicating filter logic for data + count.
    ------------------------------------------------------------
    IF OBJECT_ID('tempdb..#MyOrders') IS NOT NULL
        DROP TABLE #MyOrders;

    CREATE TABLE #MyOrders
    (
        OrderId     INT,
        OrderDate   DATETIME2(0),
        Status      NVARCHAR(20),
        TotalAmount DECIMAL(18,2),
        HasPayment  CHAR(1)
    );

    INSERT INTO #MyOrders (OrderId, OrderDate, Status, TotalAmount, HasPayment)
    SELECT
        o.OrderId,
        o.OrderDate,
        o.Status,
        o.TotalAmount,
        HasPayment = CASE
                        WHEN EXISTS (
                            SELECT 1
                            FROM dbo.Payments AS p
                            WHERE p.OrderId = o.OrderId
                        )
                        THEN 'Y'
                        ELSE 'N'
                     END
    FROM dbo.Orders AS o
    WHERE o.CustomerId = @CustomerId;

    ------------------------------------------------------------
    -- 4. Paged result set
    ------------------------------------------------------------
    SELECT
        mo.OrderId,
        mo.OrderDate,
        mo.Status,
        mo.TotalAmount,
        mo.HasPayment
    FROM #MyOrders AS mo
    ORDER BY
        mo.OrderDate DESC,
        mo.OrderId   DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;

    ------------------------------------------------------------
    -- 5. TotalCount for pagination
    ------------------------------------------------------------
    SELECT @TotalCount = COUNT(*)
    FROM #MyOrders;
END;
GO



/****************************************************************************************
    2️  MANUAL TEST (run in SSMS)
****************************************************************************************/

DECLARE @SomeCustomerId INT;
DECLARE @TotalOrders INT;

-- Pick any active customer that has at least one order (if exists)
SELECT TOP 1 @SomeCustomerId = c.CustomerId
FROM dbo.Customers c
JOIN dbo.Orders   o ON o.CustomerId = c.CustomerId
WHERE c.IsActive = 1
ORDER BY c.CustomerId;

PRINT 'Testing usp_GetMyOrders for CustomerId = ' + CAST(ISNULL(@SomeCustomerId, 0) AS NVARCHAR(20));

IF @SomeCustomerId IS NOT NULL
BEGIN
    EXEC dbo.usp_GetMyOrders
        @CustomerId = @SomeCustomerId,
        @PageNumber = 1,
        @PageSize   = 10,
        @TotalCount = @TotalOrders OUTPUT;

    SELECT @TotalOrders AS TotalOrdersForCustomer;
END
ELSE
BEGIN
    PRINT 'No suitable customer with orders found for test.';
END;
GO
