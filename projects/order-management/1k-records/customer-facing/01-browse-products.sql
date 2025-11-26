-- Scenario:
--   Customer opens the products page OR types in a search box.
--   Frontend calls this API with debounced search input.
--
-- Inputs:
--   @PageNumber INT       -- 1-based
--   @PageSize   INT       -- e.g. 10, 20, 50
--   @SearchTerm NVARCHAR(100) = NULL
--
-- Behavior:
--   - Returns ACTIVE products only (IsActive = 1)
--   - If @SearchTerm is NULL/empty: simple browse
--   - If @SearchTerm has value: filters by name or SKU containing the term
--   - Ordered by newest first, then name
--   - Uses OFFSET/FETCH for pagination

USE OrderManagement;
GO

------------------------------------------------------------
-- Example parameters (for manual testing in SSMS)
------------------------------------------------------------
DECLARE @PageNumber INT       = 1;         -- try 1, 2, 3...
DECLARE @PageSize   INT       = 10;        -- try 10, 20...
DECLARE @SearchTerm NVARCHAR(100) = N'';   -- try N'mouse', N'KEY-0', or N''

------------------------------------------------------------
-- Core query: browse + search
------------------------------------------------------------
SELECT
    p.ProductId,
    p.ProductName,
    p.Sku,
    p.UnitPrice,
    p.IsActive,
    p.CreatedAt
FROM dbo.Products AS p
WHERE
    p.IsActive = 1
    AND (
        @SearchTerm IS NULL
        OR LTRIM(RTRIM(@SearchTerm)) = N''
        OR p.ProductName LIKE N'%' + @SearchTerm + N'%'
        OR p.Sku        LIKE N'%' + @SearchTerm + N'%'
    )
ORDER BY
    p.CreatedAt DESC,
    p.ProductName ASC
OFFSET (@PageNumber - 1) * @PageSize ROWS
FETCH NEXT @PageSize ROWS ONLY;
GO

------------------------------------------------------------
-- (Optional) Total count for current filter
-- Used by backend to compute total pages in UI.
------------------------------------------------------------
DECLARE @SearchTerm NVARCHAR(100) = N'';   -- try N'mouse', N'KEY-0', or N''

SELECT COUNT(*) AS TotalMatchingProducts
FROM dbo.Products AS p
WHERE
    p.IsActive = 1
    AND (
        @SearchTerm IS NULL
        OR LTRIM(RTRIM(@SearchTerm)) = N''
        OR p.ProductName LIKE N'%' + @SearchTerm + N'%'
        OR p.Sku        LIKE N'%' + @SearchTerm + N'%'
    );
GO
