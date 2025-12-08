/****************************************************************************************
    FILE: 03-usp-get-related-products.sql

    PURPOSE:
        Stored procedure to suggest "related" products for a given product, using a
        simple heuristic:
          - Same category
          - Active products only
          - Ordered by how often they've been ordered (popularity)

        This is a Stage-01, SQL-only approximation of "related items" without any
        ML/recommendation engine.

    CONTENTS:
        1. Procedure: dbo.usp_GetRelatedProducts
        2. Example call for manual testing
****************************************************************************************/
USE OrderManagement;
GO

IF OBJECT_ID('dbo.usp_GetRelatedProducts', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetRelatedProducts;
GO

/*
    Stored Procedure: dbo.usp_GetRelatedProducts

    Scenario:
      Customer is on a product details page.
      Backend needs to show a small list of "related products" (e.g. 4–8 items)
      that are similar and popular.

    Inputs:
      @ProductId  INT
          - The product currently being viewed.

      @MaxResults INT = 8
          - Maximum number of related products to return.

    Behavior:
      - Validates that the base product exists.
      - Looks up its CategoryId.
      - Finds other ACTIVE products in the same category.
      - Uses OrderItems to compute simple popularity metrics:
          * TotalOrders   = number of distinct orders containing that product
          * TotalQuantity = total quantity sold
      - Orders by:
          1) TotalOrders (DESC)
          2) TotalQuantity (DESC)
          3) CreatedAt (DESC)
      - Returns up to @MaxResults products with:
          * ProductId, ProductName, Sku, UnitPrice, CategoryName,
            TotalOrders, TotalQuantity
*/

CREATE PROCEDURE dbo.usp_GetRelatedProducts
(
    @ProductId  INT,
    @MaxResults INT = 8
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CategoryId INT;

    ------------------------------------------------------------
    -- 1. Validate base product and get its category
    ------------------------------------------------------------
    SELECT
        @CategoryId = p.CategoryId
    FROM dbo.Products AS p
    WHERE p.ProductId = @ProductId;

    IF @CategoryId IS NULL
    BEGIN
        RAISERROR('Base product not found for the given ProductId.', 16, 1);
        RETURN;
    END;

    IF @MaxResults IS NULL OR @MaxResults < 1
        SET @MaxResults = 8;

    ------------------------------------------------------------
    -- 2. Get related products in the same category
    --    with simple popularity metrics from OrderItems
    ------------------------------------------------------------
    ;WITH ProductStats AS
    (
        SELECT
            pr.ProductId,
            TotalOrders   = COUNT(DISTINCT oi.OrderId),
            TotalQuantity = ISNULL(SUM(oi.Quantity), 0)
        FROM dbo.Products AS pr
        LEFT JOIN dbo.OrderItems AS oi
            ON oi.ProductId = pr.ProductId
        WHERE
            pr.CategoryId = @CategoryId
            AND pr.ProductId <> @ProductId        -- exclude the base product
            AND pr.IsActive = 1                   -- only active products
        GROUP BY
            pr.ProductId
    )
    SELECT TOP (@MaxResults)
        pr.ProductId,
        pr.ProductName,
        pr.Sku,
        pr.UnitPrice,
        pr.IsActive,
        pr.CreatedAt,
        c.CategoryName,
        ps.TotalOrders,
        ps.TotalQuantity
    FROM dbo.Products AS pr
    INNER JOIN dbo.ProductCategories AS c
        ON pr.CategoryId = c.CategoryId
    INNER JOIN ProductStats AS ps
        ON pr.ProductId = ps.ProductId
    WHERE
        pr.IsActive = 1
    ORDER BY
        ps.TotalOrders   DESC,
        ps.TotalQuantity DESC,
        pr.CreatedAt     DESC;
END;
GO

/****************************************************************************************
    Example manual test
****************************************************************************************/

DECLARE @BaseProductId INT;

-- Pick a sample product
SELECT TOP 1 @BaseProductId = ProductId
FROM dbo.Products
ORDER BY ProductId;

PRINT 'Testing usp_GetRelatedProducts for ProductId = '
      + CAST(ISNULL(@BaseProductId, 0) AS NVARCHAR(20));

IF @BaseProductId IS NOT NULL
BEGIN
    EXEC dbo.usp_GetRelatedProducts
        @ProductId  = @BaseProductId,
        @MaxResults = 5;
END
ELSE
BEGIN
    PRINT 'No products found to test related products.';
END;
GO
