/****************************************************************************************
    FILE: 01-usp-get-daily-revenue-trend.sql

    PURPOSE:
        Stored procedure to power a dashboard widget showing daily revenue and
        order counts over a configurable period defined by FromDate/ToDate, or
        over the full data range when no dates are provided.

    CONTENTS:
        1. Procedure: dbo.usp_GetDailyRevenueTrend
        2. Example calls for manual testing
****************************************************************************************/


/****************************************************************************************
    1️  STORED PROCEDURE: dbo.usp_GetDailyRevenueTrend
    ---------------------------------------------------
    SCENARIO:
      An internal dashboard needs a mini chart of:
        - Orders per day
        - Revenue per day
      for a selected period:
        - Explicit date range (FromDate/ToDate), OR
        - Full history (default) if no dates are provided.

    INPUTS:
      @FromDate DATE = NULL
        - Optional explicit start date (UTC date as stored in DB).

      @ToDate   DATE = NULL
        - Optional explicit end date (UTC date).

    BEHAVIOR:
      - If both @FromDate and @ToDate are provided:
          * Use that range.
      - If both are NULL:
          * Use MIN..MAX OrderDate (for completed statuses) as the range.
      - Considers only "completed/paid" statuses:
          * 'Paid', 'Shipped', 'Delivered'
      - Groups by DATE(OrderDate) (UTC date).
      - Returns per day:
          * OrderDate (date only)
          * OrdersCount
          * TotalRevenue
      - Sorted ascending by OrderDate (good for charts).
****************************************************************************************/
USE OrderManagement;
GO

IF OBJECT_ID('dbo.usp_GetDailyRevenueTrend', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetDailyRevenueTrend;
GO

CREATE PROCEDURE dbo.usp_GetDailyRevenueTrend
(
    @FromDate DATE = NULL,
    @ToDate   DATE = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @EffectiveFromDate DATE;
    DECLARE @EffectiveToDate   DATE;

    ------------------------------------------------------------
    -- 1. Determine effective date range
    ------------------------------------------------------------
    IF @FromDate IS NOT NULL AND @ToDate IS NOT NULL
    BEGIN
        SET @EffectiveFromDate = @FromDate;
        SET @EffectiveToDate   = @ToDate;
    END
    ELSE
    BEGIN
        -- Use full data range for completed orders
        SELECT
            @EffectiveFromDate = MIN(CAST(OrderDate AS DATE)),
            @EffectiveToDate   = MAX(CAST(OrderDate AS DATE))
        FROM dbo.Orders
        WHERE Status IN (N'Paid', N'Shipped', N'Delivered');

        -- If no data at all, return empty set
        IF @EffectiveFromDate IS NULL OR @EffectiveToDate IS NULL
        BEGIN
            SELECT
                CAST(NULL AS DATE)          AS OrderDate,
                CAST(NULL AS INT)           AS OrdersCount,
                CAST(NULL AS DECIMAL(18,2)) AS TotalRevenue
            WHERE 1 = 0; -- no rows
            RETURN;
        END;
    END;

    ------------------------------------------------------------
    -- 2. Aggregate orders by day within effective range
    ------------------------------------------------------------
    SELECT
        OrderDate    = CAST(o.OrderDate AS DATE),
        OrdersCount  = COUNT(*),
        TotalRevenue = SUM(o.TotalAmount)
    FROM dbo.Orders AS o
    WHERE
        CAST(o.OrderDate AS DATE) BETWEEN @EffectiveFromDate AND @EffectiveToDate
        AND o.Status IN (N'Paid', N'Shipped', N'Delivered')
    GROUP BY
        CAST(o.OrderDate AS DATE)
    ORDER BY
        OrderDate ASC;
END;
GO


/****************************************************************************************
    2️  MANUAL TESTS (run in SSMS)
****************************************************************************************/

-- A) Full history (whatever exists in Orders for completed statuses)
EXEC dbo.usp_GetDailyRevenueTrend;
GO

-- B) Explicit range (e.g., seeded data window)
EXEC dbo.usp_GetDailyRevenueTrend
    @FromDate = '2025-01-01',
    @ToDate   = '2025-12-31';
GO
