/****************************************************************************************
    FILE: 01-usp-browse-products.sql

    PURPOSE:
        Stored procedure to power the product listing API.
        Supports browsing active products with optional search, category and
        price filters, plus pagination and total count for UI.

    CONTENTS:
        1. Procedure: dbo.usp_BrowseProducts
        2. Example calls for manual testing
****************************************************************************************/

/****************************************************************************************
    2️  STORED PROCEDURE: dbo.usp_BrowseProducts
    ------------------------------------------------
    Scenario:
      Customer opens the products page OR types in a search box.
      Frontend calls this API with debounced search input and optional filters.

    Inputs:
       @PageNumber INT                -- 1-based (1 = first page)
       @PageSize   INT                -- e.g. 10, 20, 50
       @SearchTerm NVARCHAR(100) = NULL
           - Optional text search on ProductName or Sku.
           - If NULL/empty: no search filter.

       @CategoryId INT = NULL
           - Optional filter.
           - If provided, only products from this category are returned.
           - If NULL: no category filter.

       @MinPrice DECIMAL(18,2) = NULL
           - Optional filter.
           - If provided, only products with UnitPrice >= MinPrice.

       @MaxPrice DECIMAL(18,2) = NULL
           - Optional filter.
           - If provided, only products with UnitPrice <= MaxPrice.

       @TotalCount INT OUTPUT
           - Total number of products matching filters (without pagination).
           - Used by backend to compute total pages for UI.

     Behavior:
       - Returns ACTIVE products only (IsActive = 1).
       - Optionally filters by:
           * SearchTerm (ProductName or Sku contains the term)
           * CategoryId
           * MinPrice / MaxPrice
       - Joins ProductCategories to return CategoryName along with CategoryId.
       - Ordered by newest first (CreatedAt DESC), then ProductName ASC.
       - Uses OFFSET/FETCH for pagination.
       - Returns:
           * Result set for current page.
           * @TotalCount for pagination metadata.
****************************************************************************************/
USE OrderManagement;
GO

IF OBJECT_ID('dbo.usp_BrowseProducts', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_BrowseProducts;
GO

CREATE PROCEDURE dbo.usp_BrowseProducts
(
    @PageNumber INT = 1,
    @PageSize   INT = 10,
    @SearchTerm NVARCHAR(100) = NULL,
    @CategoryId INT = NULL,
    @MinPrice   DECIMAL(18,2) = NULL,
    @MaxPrice   DECIMAL(18,2) = NULL,
    @TotalCount INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    ------------------------------------------------------------
    -- Guardrails for pagination
    ------------------------------------------------------------
    IF @PageNumber < 1 SET @PageNumber = 1;
    IF @PageSize   < 1 SET @PageSize   = 10;

    ------------------------------------------------------------
    -- Core filtered set into a temp table so we can:
    --   1) Page over it
    --   2) Get @TotalCount using the same filters
    ------------------------------------------------------------
    IF OBJECT_ID('tempdb..#FilteredProducts') IS NOT NULL
        DROP TABLE #FilteredProducts;

    CREATE TABLE #FilteredProducts
    (
        ProductId     INT,
        ProductName   NVARCHAR(200),
        Sku           NVARCHAR(50),
        UnitPrice     DECIMAL(18,2),
        IsActive      BIT,
        CreatedAt     DATETIME2(0),
        CategoryId    INT,
        CategoryName  NVARCHAR(100)
    );

    INSERT INTO #FilteredProducts
    (
        ProductId,
        ProductName,
        Sku,
        UnitPrice,
        IsActive,
        CreatedAt,
        CategoryId,
        CategoryName
    )
    SELECT
        p.ProductId,
        p.ProductName,
        p.Sku,
        p.UnitPrice,
        p.IsActive,
        p.CreatedAt,
        p.CategoryId,
        c.CategoryName
    FROM dbo.Products AS p
    INNER JOIN dbo.ProductCategories AS c
        ON p.CategoryId = c.CategoryId
    WHERE
        p.IsActive = 1
        -- Search filter (optional)
        AND (
            @SearchTerm IS NULL
            OR LTRIM(RTRIM(@SearchTerm)) = N''
            OR p.ProductName LIKE N'%' + @SearchTerm + N'%'
            OR p.Sku        LIKE N'%' + @SearchTerm + N'%'
        )
        -- Category filter (optional)
        AND (
            @CategoryId IS NULL
            OR p.CategoryId = @CategoryId
        )
        -- Min price filter (optional)
        AND (
            @MinPrice IS NULL
            OR p.UnitPrice >= @MinPrice
        )
        -- Max price filter (optional)
        AND (
            @MaxPrice IS NULL
            OR p.UnitPrice <= @MaxPrice
        );

    ------------------------------------------------------------
    -- Paged result: browse + search + filters
    ------------------------------------------------------------
    SELECT
        fp.ProductId,
        fp.ProductName,
        fp.Sku,
        fp.UnitPrice,
        fp.IsActive,
        fp.CreatedAt,
        fp.CategoryId,
        fp.CategoryName
    FROM #FilteredProducts AS fp
    ORDER BY
        fp.CreatedAt DESC,
        fp.ProductName ASC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;

    ------------------------------------------------------------
    -- Total count for current filters
    ------------------------------------------------------------
    SELECT @TotalCount = COUNT(*)
    FROM #FilteredProducts;
END;
GO

------------------------------------------------------------
-- Example calls for manual testing in SSMS
------------------------------------------------------------
DECLARE @Total INT;

-- 1) Simple browse, first page, no filters
EXEC dbo.usp_BrowseProducts
    @PageNumber = 1,
    @PageSize   = 10,
    @SearchTerm = NULL,
    @CategoryId = NULL,
    @MinPrice   = NULL,
    @MaxPrice   = NULL,
    @TotalCount = @Total OUTPUT;

SELECT @Total AS TotalMatchingProducts;
GO

-- 2) Search with filters (adjust CategoryId based on your data)
DECLARE @Total2 INT;

EXEC dbo.usp_BrowseProducts
    @PageNumber = 1,
    @PageSize   = 10,
    @SearchTerm = N'mouse',   -- try different terms
    @CategoryId = NULL,       -- set valid CategoryId to filter
    @MinPrice   = 500,
    @MaxPrice   = 5000,
    @TotalCount = @Total2 OUTPUT;

SELECT @Total2 AS TotalMatchingProducts_Search;
GO
