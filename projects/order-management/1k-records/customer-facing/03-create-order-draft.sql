/****************************************************************************************
    FILE: 03-create-order-draft.sql

    PURPOSE:
        Defines the table-valued parameter type and the stored procedure used to create
        an order draft (Stage-01 checkout flow).

    CONTENTS:
        1. Type: dbo.CartItemType
        2. Procedure: dbo.usp_CreateOrderDraft
****************************************************************************************/


/****************************************************************************************
    1️  TABLE-VALUED TYPE: dbo.CartItemType
    ----------------------------------------
    Purpose:
      Represents the shopping cart items coming from the backend.
      Mimics a real-world scenario where the backend gathers cart info and calls SQL.

    Columns:
      ProductId INT       -- must exist in Products
      Quantity  INT > 0   -- quantity for that product
****************************************************************************************/
USE OrderManagement;
GO

IF TYPE_ID('dbo.CartItemType') IS NOT NULL
    DROP TYPE dbo.CartItemType;
GO

CREATE TYPE dbo.CartItemType AS TABLE
(
    ProductId INT NOT NULL,
    Quantity  INT NOT NULL CHECK (Quantity > 0)
);
GO



/****************************************************************************************
    2️  STORED PROCEDURE: dbo.usp_CreateOrderDraft
    ------------------------------------------------
    SCENARIO:
      Customer clicks “Place Order”.
      Backend has the customer ID and their selected items.
      We create:
         - A new Order (Status = 'Pending')
         - OrderItems for each product
         - The correct total amount

    INPUTS:
      @CustomerId  INT
          Customer placing the order.
      @CartItems   dbo.CartItemType READONLY
          Table-valued parameter containing:
              ProductId, Quantity

    OUTPUTS:
      @OrderId     INT OUTPUT
          Newly created OrderId.
      @TotalAmount DECIMAL(18,2) OUTPUT
          Final order amount after inserting items.

    BEHAVIOR:
      - Validates:
          * Customer exists & is active
          * Cart is not empty
          * All product IDs exist
      - Creates Order with:
            Status = 'Pending'
            TotalAmount = 0
            OrderDate = SYSUTCDATETIME() (always use UTC timestamps)
      - Aggregates cart items (in case duplicates exist)
      - Inserts OrderItems using UnitPrice from Products
      - Computes TotalAmount as SUM(LineTotal)
      - Updates Orders.TotalAmount
      - Runs inside a transaction (atomic behavior)
****************************************************************************************/

IF OBJECT_ID('dbo.usp_CreateOrderDraft', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CreateOrderDraft;
GO

CREATE PROCEDURE dbo.usp_CreateOrderDraft
(
    @CustomerId  INT,
    @CartItems   dbo.CartItemType READONLY,
    @OrderId     INT OUTPUT,
    @TotalAmount DECIMAL(18,2) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;   -- Auto rollback on SQL errors

    DECLARE @ErrorMessage NVARCHAR(4000);

    BEGIN TRY

        --------------------------------------------------------------------------------
        -- 1. VALIDATIONS
        --------------------------------------------------------------------------------

        -- Customer exists & active
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

        -- Cart not empty
        IF NOT EXISTS (SELECT 1 FROM @CartItems)
        BEGIN
            RAISERROR('Cart is empty. Cannot create order.', 16, 1);
            RETURN;
        END;

        -- All ProductIds valid
        IF EXISTS (
            SELECT ci.ProductId
            FROM @CartItems AS ci
            LEFT JOIN dbo.Products AS p
                ON ci.ProductId = p.ProductId
            WHERE p.ProductId IS NULL
        )
        BEGIN
            RAISERROR('Cart contains invalid ProductId(s).', 16, 1);
            RETURN;
        END;



        --------------------------------------------------------------------------------
        -- 2. BEGIN TRANSACTION
        --------------------------------------------------------------------------------
        BEGIN TRAN;



        --------------------------------------------------------------------------------
        -- 3. INSERT ORDER HEADER
        --------------------------------------------------------------------------------
        INSERT INTO dbo.Orders (CustomerId, OrderDate, Status, TotalAmount)
        VALUES (@CustomerId, SYSUTCDATETIME(), N'Pending', 0);

        SET @OrderId = SCOPE_IDENTITY();



        --------------------------------------------------------------------------------
        -- 4. INSERT ORDER ITEMS
        --------------------------------------------------------------------------------
        ;WITH CartAggregated AS
        (
            SELECT
                ProductId,
                SUM(Quantity) AS Quantity
            FROM @CartItems
            GROUP BY ProductId
        )
        INSERT INTO dbo.OrderItems (OrderId, ProductId, Quantity, UnitPrice)
        SELECT
            @OrderId,
            ca.ProductId,
            ca.Quantity,
            p.UnitPrice
        FROM CartAggregated AS ca
        JOIN dbo.Products AS p
            ON ca.ProductId = p.ProductId;



        --------------------------------------------------------------------------------
        -- 5. COMPUTE TOTAL & UPDATE ORDER
        --------------------------------------------------------------------------------
        SELECT @TotalAmount = ISNULL(SUM(LineTotal), 0)
        FROM dbo.OrderItems
        WHERE OrderId = @OrderId;

        UPDATE dbo.Orders
        SET TotalAmount = @TotalAmount
        WHERE OrderId = @OrderId;



        --------------------------------------------------------------------------------
        -- 6. COMMIT TRANSACTION
        --------------------------------------------------------------------------------
        COMMIT TRAN;

    END TRY
    BEGIN CATCH

        -- Roll back if needed
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;

        -- Re-throw descriptive error
        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR('Error in usp_CreateOrderDraft: %s', 16, 1, @ErrorMessage);
        RETURN;

    END CATCH
END;
GO



/****************************************************************************************
    3️  MANUAL TEST (run in SSMS)
****************************************************************************************/

-- Simulate the cart
DECLARE @Cart dbo.CartItemType;
INSERT INTO @Cart (ProductId, Quantity)
SELECT TOP 3 ProductId, 2
FROM dbo.Products
ORDER BY ProductId;

DECLARE @OrderId INT;
DECLARE @Total DECIMAL(18,2);

EXEC dbo.usp_CreateOrderDraft
    @CustomerId  = 1,
    @CartItems   = @Cart,
    @OrderId     = @OrderId OUTPUT,
    @TotalAmount = @Total OUTPUT;

SELECT @OrderId AS CreatedOrderId,
       @Total    AS OrderTotalAmount;

SELECT * FROM dbo.Orders     WHERE OrderId = @OrderId;
SELECT * FROM dbo.OrderItems WHERE OrderId = @OrderId;
GO
