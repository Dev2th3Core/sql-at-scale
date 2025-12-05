/****************************************************************************************
    FILE: 07-usp-cancel-my-order.sql

    PURPOSE:
        Stored procedure to allow a customer to cancel their own order,
        only if it is still in 'Pending' status and has no payments.

    CONTENTS:
        1. Procedure: dbo.usp_CancelMyOrder
        2. Manual test block
****************************************************************************************/


/****************************************************************************************
    1️  STORED PROCEDURE: dbo.usp_CancelMyOrder
    -------------------------------------------
    SCENARIO:
      Customer is on the "My Orders" page and clicks "Cancel" on a specific order.
      Backend must:
        - Ensure the order belongs to that customer
        - Ensure the order is still 'Pending'
        - Ensure no payment exists (Stage-01: no refund logic)
        - Update the order status to 'Cancelled'

    INPUTS:
      @CustomerId INT
        - Logged-in customer's ID (authorization context).

      @OrderId    INT
        - The order the customer is trying to cancel.

    OUTPUTS:
      (none via parameters; changes are applied to Orders table.)

    STAGE-01 BEHAVIOR:
      - Validations:
          * Customer exists & is active.
          * Order exists AND belongs to that customer.
          * Order status is 'Pending'.
          * No row exists in Payments for this order.
      - If any validation fails -> RAISERROR and do nothing.
      - If all checks pass:
          * Update Orders.Status to 'Cancelled'.
      - Wrapped in TRY/CATCH + transaction for future extensibility
        (e.g., refund logic in Stage-02).

    NOTE:
      We do not track CancelledAt timestamp in Stage-01 schema,
      but this SP is ready to be extended when such a column is added.
****************************************************************************************/
USE OrderManagement;
GO

IF OBJECT_ID('dbo.usp_CancelMyOrder', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CancelMyOrder;
GO

CREATE PROCEDURE dbo.usp_CancelMyOrder
(
    @CustomerId INT,
    @OrderId    INT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;  -- ensures runtime errors rollback the transaction

    DECLARE @ErrorMessage NVARCHAR(4000);
    DECLARE @OrderStatus  NVARCHAR(20);
    DECLARE @HasPayment   BIT;

    BEGIN TRY
        --------------------------------------------------------------------
        -- 1. Validate customer
        --------------------------------------------------------------------
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

        --------------------------------------------------------------------
        -- 2. Validate order belongs to this customer and get its status
        --------------------------------------------------------------------
        SELECT
            @OrderStatus = o.Status
        FROM dbo.Orders AS o
        WHERE o.OrderId    = @OrderId
          AND o.CustomerId = @CustomerId;

        IF @OrderStatus IS NULL
        BEGIN
            RAISERROR('Order does not exist or does not belong to the specified customer.', 16, 1);
            RETURN;
        END;

        --------------------------------------------------------------------
        -- 3. Order must be in 'Pending' status
        --------------------------------------------------------------------
        IF @OrderStatus <> N'Pending'
        BEGIN
            RAISERROR('Only orders in Pending status can be cancelled at Stage-01.', 16, 1);
            RETURN;
        END;

        --------------------------------------------------------------------
        -- 4. Ensure no payment exists for this order (Stage-01 rule)
        --------------------------------------------------------------------
        SELECT @HasPayment =
            CASE WHEN EXISTS (
                SELECT 1
                FROM dbo.Payments AS p
                WHERE p.OrderId = @OrderId
            )
            THEN 1 ELSE 0 END;

        IF @HasPayment = 1
        BEGIN
            RAISERROR('Cannot cancel an order that already has a payment in Stage-01.', 16, 1);
            RETURN;
        END;

        --------------------------------------------------------------------
        -- 5. Perform the cancellation inside a transaction
        --------------------------------------------------------------------
        BEGIN TRAN;

        UPDATE dbo.Orders
        SET Status = N'Cancelled'
        WHERE OrderId    = @OrderId
          AND CustomerId = @CustomerId
          AND Status     = N'Pending';

        -- Optional: check that exactly one row was updated
        IF @@ROWCOUNT = 0
        BEGIN
            -- This means the status changed between checks, or some race condition occurred
            RAISERROR('Order could not be cancelled. It may have been updated by another process.', 16, 1);
            ROLLBACK TRAN;
            RETURN;
        END;

        COMMIT TRAN;

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;

        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR('Error in usp_CancelMyOrder: %s', 16, 1, @ErrorMessage);
        RETURN;

    END CATCH
END;
GO



/****************************************************************************************
    2️  MANUAL TEST (run in SSMS)
****************************************************************************************/

DECLARE @TestCustomerId INT;
DECLARE @TestOrderId    INT;

-- Find a Pending order with no payment
SELECT TOP 1
    @TestOrderId    = o.OrderId,
    @TestCustomerId = o.CustomerId
FROM dbo.Orders o
LEFT JOIN dbo.Payments p
    ON p.OrderId = o.OrderId
WHERE o.Status = N'Pending'
  AND p.OrderId IS NULL
ORDER BY o.OrderId;

PRINT 'Testing usp_CancelMyOrder for CustomerId = '
      + CAST(ISNULL(@TestCustomerId, 0) AS NVARCHAR(20))
      + ', OrderId = '
      + CAST(ISNULL(@TestOrderId, 0) AS NVARCHAR(20));

IF @TestOrderId IS NOT NULL AND @TestCustomerId IS NOT NULL
BEGIN
    EXEC dbo.usp_CancelMyOrder
        @CustomerId = @TestCustomerId,
        @OrderId    = @TestOrderId;

    -- Verify
    SELECT * FROM dbo.Orders WHERE OrderId = @TestOrderId;
END
ELSE
BEGIN
    PRINT 'No suitable Pending order without payment found for test.';
END;
GO
