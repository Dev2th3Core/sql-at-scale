/****************************************************************************************
    FILE: 06-usp-get-my-order-details.sql

    PURPOSE:
        Stored procedure to fetch details for a single order belonging to a
        specific customer: order header + line items + payment info.

    CONTENTS:
        1. Procedure: dbo.usp_GetMyOrderDetails
        2. Manual test block
****************************************************************************************/


/****************************************************************************************
    1️  STORED PROCEDURE: dbo.usp_GetMyOrderDetails
    ------------------------------------------------
    SCENARIO:
      Customer is on the "My Orders" list and clicks on a specific order.
      Backend must fetch:
        - Order header (date, status, total)
        - Line items (products, quantity, price, line totals)
        - Payment info (if any)
      and **ensure the order belongs to that customer**.

    INPUTS:
      @CustomerId INT
        - Logged-in customer's ID (used for authorization check).

      @OrderId    INT
        - The order to show details for.

    OUTPUT:
      A result set with one row per line item, including:
        - OrderId, CustomerId
        - CustomerName (FirstName + LastName)
        - OrderDate, Status, TotalAmount
        - HasPayment ('Y' or 'N')
        - PaymentId, PaidAmount, PaidAt, Method, ReferenceNumber (may be NULL)
        - OrderItemId, ProductId, ProductName, Sku, CategoryName
        - Quantity, UnitPrice (at time of order), LineTotal

    BEHAVIOR:
      - Validates:
          * Customer exists and is active.
          * Order exists and belongs to that customer.
      - Joins:
          Orders        -> Customers
          Orders        -> OrderItems
          OrderItems    -> Products
          Products      -> ProductCategories
          Orders (LEFT) -> Payments
      - Returns data for that order only.
      - No transaction needed (read-only).
****************************************************************************************/
USE OrderManagement;
GO

IF OBJECT_ID('dbo.usp_GetMyOrderDetails', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetMyOrderDetails;
GO

CREATE PROCEDURE dbo.usp_GetMyOrderDetails
(
    @CustomerId INT,
    @OrderId    INT
)
AS
BEGIN
    SET NOCOUNT ON;

    ------------------------------------------------------------
    -- 1. Validate customer
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
    -- 2. Validate order belongs to this customer
    ------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Orders
        WHERE OrderId   = @OrderId
          AND CustomerId = @CustomerId
    )
    BEGIN
        RAISERROR('Order does not exist or does not belong to the specified customer.', 16, 1);
        RETURN;
    END;

    ------------------------------------------------------------
    -- 3. Return full order details (one row per line item)
    ------------------------------------------------------------
    SELECT
        o.OrderId,
        o.CustomerId,
        CustomerName = c.FirstName + N' ' + c.LastName,
        o.OrderDate,
        o.Status,
        o.TotalAmount,

        HasPayment = CASE WHEN p.PaymentId IS NULL THEN 'N' ELSE 'Y' END,

        p.PaymentId,
        p.PaidAmount,
        p.PaidAt,
        p.Method,
        p.ReferenceNumber,

        oi.OrderItemId,
        oi.ProductId,
        prod.ProductName,
        prod.Sku,
        cat.CategoryName,
        oi.Quantity,
        oi.UnitPrice,         -- unit price at the time of order
        oi.LineTotal
    FROM dbo.Orders AS o
    INNER JOIN dbo.Customers AS c
        ON o.CustomerId = c.CustomerId
    INNER JOIN dbo.OrderItems AS oi
        ON oi.OrderId = o.OrderId
    INNER JOIN dbo.Products AS prod
        ON oi.ProductId = prod.ProductId
    INNER JOIN dbo.ProductCategories AS cat
        ON prod.CategoryId = cat.CategoryId
    LEFT JOIN dbo.Payments AS p
        ON p.OrderId = o.OrderId   -- Stage-01: at most one payment per order
    WHERE
        o.OrderId    = @OrderId
        AND o.CustomerId = @CustomerId
    ORDER BY
        oi.OrderItemId;
END;
GO



/****************************************************************************************
    2️  MANUAL TEST (run in SSMS)
****************************************************************************************/

DECLARE @TestCustomerId INT;
DECLARE @TestOrderId    INT;

-- Pick any order + its customer
SELECT TOP 1
    @TestOrderId    = o.OrderId,
    @TestCustomerId = o.CustomerId
FROM dbo.Orders o
ORDER BY o.OrderId;

PRINT 'Testing usp_GetMyOrderDetails for CustomerId = '
      + CAST(ISNULL(@TestCustomerId, 0) AS NVARCHAR(20))
      + ', OrderId = '
      + CAST(ISNULL(@TestOrderId, 0) AS NVARCHAR(20));

IF @TestOrderId IS NOT NULL AND @TestCustomerId IS NOT NULL
BEGIN
    EXEC dbo.usp_GetMyOrderDetails
        @CustomerId = @TestCustomerId,
        @OrderId    = @TestOrderId;
END
ELSE
BEGIN
    PRINT 'No suitable order found for test.';
END;
GO
