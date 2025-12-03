/****************************************************************************************
    FILE: 04-confirm-order-payment.sql

    PURPOSE:
        Defines the stored procedure used to confirm a payment for an order and
        mark the order as paid (Stage-01 payment success flow).

    CONTENTS:
        1. Procedure: dbo.usp_ConfirmOrderPayment
        2. Manual test block
****************************************************************************************/


/****************************************************************************************
    1️  STORED PROCEDURE: dbo.usp_ConfirmOrderPayment
    ---------------------------------------------------
    SCENARIO:
      Payment gateway callback or payment success API is called.
      Backend needs to:
        - Record the payment in Payments table
        - Update the order status to 'Paid'

    INPUTS:
      @OrderId         INT
          The order being paid.

      @PaidAmount      DECIMAL(18,2)
          Amount paid by the customer.
          Stage-01 assumption: full payment only (must match order total).

      @Method          NVARCHAR(20)
          Payment method, e.g. 'Card', 'UPI', 'NetBanking', 'COD'.

      @ReferenceNumber NVARCHAR(100)
          Payment reference / transaction ID coming from the gateway.

    OUTPUTS:
      (none as parameters for now; the procedure performs changes.
       You can query Orders/Payments afterwards.)

    BEHAVIOR (Stage-01 rules):
      - Validates:
          * Order exists.
          * Order is currently 'Pending'.
          * Order has a positive TotalAmount.
          * No previous payments exist for that order (no double payment).
          * @PaidAmount exactly matches the order's TotalAmount.
      - Inserts a new row into dbo.Payments:
          * OrderId, PaidAmount, PaidAt (SYSUTCDATETIME()), Method, ReferenceNumber
      - Updates dbo.Orders:
          * Status = 'Paid'
      - Runs inside a transaction (all-or-nothing behavior).

      NOTE:
        All timestamps are stored in UTC using SYSUTCDATETIME().
        Frontend/backends should convert to user's local timezone when displaying.
****************************************************************************************/
USE OrderManagement;
GO

IF OBJECT_ID('dbo.usp_ConfirmOrderPayment', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_ConfirmOrderPayment;
GO

CREATE PROCEDURE dbo.usp_ConfirmOrderPayment
(
    @OrderId         INT,
    @PaidAmount      DECIMAL(18,2),
    @Method          NVARCHAR(20),
    @ReferenceNumber NVARCHAR(100)
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;  -- auto-rollback on errors

    DECLARE @ErrorMessage NVARCHAR(4000);
    DECLARE @OrderTotal   DECIMAL(18,2);
    DECLARE @OrderStatus  NVARCHAR(20);
    DECLARE @AlreadyPaid  DECIMAL(18,2);

    BEGIN TRY
        --------------------------------------------------------------------------------
        -- 1. VALIDATIONS
        --------------------------------------------------------------------------------

        -- 1.1 Check that order exists and get its details
        SELECT
            @OrderTotal  = TotalAmount,
            @OrderStatus = Status
        FROM dbo.Orders
        WHERE OrderId = @OrderId;

        IF @OrderTotal IS NULL
        BEGIN
            RAISERROR('Order not found for the given OrderId.', 16, 1);
            RETURN;
        END;

        -- 1.2 Stage-01: Only allow payment when order is Pending
        IF @OrderStatus <> N'Pending'
        BEGIN
            RAISERROR('Order is not in Pending status. Cannot confirm payment.', 16, 1);
            RETURN;
        END;

        -- 1.3 Order total must be positive
        IF @OrderTotal <= 0
        BEGIN
            RAISERROR('Order total amount is not positive. Cannot confirm payment.', 16, 1);
            RETURN;
        END;

        -- 1.4 PaidAmount must be positive
        IF @PaidAmount <= 0
        BEGIN
            RAISERROR('PaidAmount must be greater than zero.', 16, 1);
            RETURN;
        END;

        -- 1.5 Check if there are existing payments (Stage-01: disallow any previous payment)
        SELECT @AlreadyPaid = ISNULL(SUM(PaidAmount), 0)
        FROM dbo.Payments
        WHERE OrderId = @OrderId;

        IF @AlreadyPaid > 0
        BEGIN
            RAISERROR('Order already has a recorded payment. Duplicate payment not allowed in Stage-01.', 16, 1);
            RETURN;
        END;

        -- 1.6 Stage-01 rule: require full payment (no partial payments)
        IF @PaidAmount <> @OrderTotal
        BEGIN
            RAISERROR('PaidAmount must exactly match the Order total in Stage-01.', 16, 1);
            RETURN;
        END;



        --------------------------------------------------------------------------------
        -- 2. BEGIN TRANSACTION
        --------------------------------------------------------------------------------
        BEGIN TRAN;



        --------------------------------------------------------------------------------
        -- 3. INSERT PAYMENT
        --------------------------------------------------------------------------------
        INSERT INTO dbo.Payments (OrderId, PaidAmount, PaidAt, Method, ReferenceNumber)
        VALUES (@OrderId, @PaidAmount, SYSUTCDATETIME(), @Method, @ReferenceNumber);



        --------------------------------------------------------------------------------
        -- 4. UPDATE ORDER STATUS TO 'Paid'
        --------------------------------------------------------------------------------
        UPDATE dbo.Orders
        SET Status = N'Paid'
        WHERE OrderId = @OrderId;



        --------------------------------------------------------------------------------
        -- 5. COMMIT TRANSACTION
        --------------------------------------------------------------------------------
        COMMIT TRAN;

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;

        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR('Error in usp_ConfirmOrderPayment: %s', 16, 1, @ErrorMessage);
        RETURN;

    END CATCH
END;
GO



/****************************************************************************************
    2️  MANUAL TEST (run in SSMS)
    NOTE:
      For a clean test, pick an order that:
        - Exists
        - Has Status = 'Pending'
        - Has no existing payments
      You can create one via usp_CreateOrderDraft.
****************************************************************************************/

-- Example: create a small "pending" order draft first (if needed)
-- (Assumes usp_CreateOrderDraft and CartItemType are present and working)

-- DECLARE @Cart dbo.CartItemType;
-- INSERT INTO @Cart (ProductId, Quantity)
-- SELECT TOP 1 ProductId, 1
-- FROM dbo.Products
-- ORDER BY ProductId;
--
-- DECLARE @NewOrderId INT;
-- DECLARE @NewOrderTotal DECIMAL(18,2);
--
-- EXEC dbo.usp_CreateOrderDraft
--     @CustomerId  = 1,
--     @CartItems   = @Cart,
--     @OrderId     = @NewOrderId OUTPUT,
--     @TotalAmount = @NewOrderTotal OUTPUT;
--
-- SELECT @NewOrderId AS NewOrderId, @NewOrderTotal AS NewOrderTotal;

-- Now confirm payment for that order (replace @TestOrderId and @TestAmount appropriately):

DECLARE @TestOrderId INT;
DECLARE @TestAmount  DECIMAL(18,2);

-- Pick any Pending order with no payments
SELECT TOP 1
    @TestOrderId = o.OrderId,
    @TestAmount  = o.TotalAmount
FROM dbo.Orders o
LEFT JOIN dbo.Payments p ON p.OrderId = o.OrderId
WHERE o.Status = N'Pending'
  AND p.OrderId IS NULL
ORDER BY o.OrderId;

PRINT 'Testing payment confirmation for OrderId = ' + CAST(ISNULL(@TestOrderId, 0) AS NVARCHAR(20));

IF @TestOrderId IS NOT NULL
BEGIN
    EXEC dbo.usp_ConfirmOrderPayment
        @OrderId         = @TestOrderId,
        @PaidAmount      = @TestAmount,
        @Method          = N'UPI',
        @ReferenceNumber = N'TEST-REF-123';

    -- Check updated order and payment
    SELECT * FROM dbo.Orders   WHERE OrderId = @TestOrderId;
    SELECT * FROM dbo.Payments WHERE OrderId = @TestOrderId;
END
ELSE
BEGIN
    PRINT 'No suitable Pending order found for test.';
END;
GO
