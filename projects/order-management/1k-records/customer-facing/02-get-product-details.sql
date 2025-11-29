/*
    Stored Procedure: dbo.usp_GetProductDetails

    Scenario:
      Customer opens a specific product page.
      Backend needs to show product details and some basic stats
      about how often it has been ordered.

    Inputs:
      @ProductId INT
        - The ID of the product to fetch.

    Behavior:
      - Returns a single row (or zero rows if not found) with:
          * ProductId
          * ProductName
          * Sku
          * UnitPrice
          * IsActive
          * CreatedAt
          * CategoryId
          * CategoryName
          * TotalOrders      (number of distinct orders containing this product)
          * TotalQuantity    (total quantity of this product sold)
          * TotalRevenue     (sum of LineTotal for this product across all orders)
      - Uses Products + ProductCategories for base info.
      - Uses OrderItems (Stage-01 bonus) for aggregate stats.
*/
USE OrderManagement;
GO

IF OBJECT_ID('dbo.usp_GetProductDetails', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetProductDetails;
GO

CREATE PROCEDURE dbo.usp_GetProductDetails
(
    @ProductId INT
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1
        p.ProductId,
        p.ProductName,
        p.Sku,
        p.UnitPrice,
        p.IsActive,
        p.CreatedAt,
        p.CategoryId,
        c.CategoryName,
        ISNULL(stats.TotalOrders,   0) AS TotalOrders,
        ISNULL(stats.TotalQuantity, 0) AS TotalQuantity,
        ISNULL(stats.TotalRevenue,  0) AS TotalRevenue
    FROM dbo.Products AS p
    INNER JOIN dbo.ProductCategories AS c
        ON p.CategoryId = c.CategoryId
    OUTER APPLY
    (
        SELECT
            COUNT(DISTINCT oi.OrderId)          AS TotalOrders,
            SUM(oi.Quantity)                    AS TotalQuantity,
            SUM(oi.LineTotal)                   AS TotalRevenue
        FROM dbo.OrderItems AS oi
        WHERE oi.ProductId = p.ProductId
    ) AS stats
    WHERE p.ProductId = @ProductId;
END;
GO

------------------------------------------------------------
-- Example test call (run in SSMS)
------------------------------------------------------------
DECLARE @SomeProductId INT;

-- Pick any product to test
SELECT TOP 1 @SomeProductId = ProductId
FROM dbo.Products
ORDER BY ProductId;

EXEC dbo.usp_GetProductDetails @ProductId = @SomeProductId;
GO
