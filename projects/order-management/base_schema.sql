-- base_schema.sql – core schema for order-management (shared across stages)

IF DB_ID('OrderManagement') IS NULL
BEGIN
    CREATE DATABASE OrderManagement;
END
GO

USE OrderManagement;
GO

-- Drop tables if they already exist (for re-runs during learning)
IF OBJECT_ID('dbo.Payments', 'U') IS NOT NULL DROP TABLE dbo.Payments;
IF OBJECT_ID('dbo.OrderItems', 'U') IS NOT NULL DROP TABLE dbo.OrderItems;
IF OBJECT_ID('dbo.Orders', 'U') IS NOT NULL DROP TABLE dbo.Orders;
IF OBJECT_ID('dbo.Products', 'U') IS NOT NULL DROP TABLE dbo.Products;
IF OBJECT_ID('dbo.Customers', 'U') IS NOT NULL DROP TABLE dbo.Customers;
GO

-- Customers
CREATE TABLE dbo.Customers
(
    CustomerId      INT IDENTITY(1,1) CONSTRAINT PK_Customers PRIMARY KEY CLUSTERED,
    FirstName       NVARCHAR(100)     NOT NULL,
    LastName        NVARCHAR(100)     NOT NULL,
    Email           NVARCHAR(255)     NOT NULL,
    PhoneNumber     NVARCHAR(20)      NULL,
    CreatedAt       DATETIME2(0)      NOT NULL CONSTRAINT DF_Customers_CreatedAt DEFAULT (SYSUTCDATETIME()),
    IsActive        BIT               NOT NULL CONSTRAINT DF_Customers_IsActive DEFAULT (1),

    CONSTRAINT UQ_Customers_Email UNIQUE (Email)
);
GO

-- Products
CREATE TABLE dbo.Products
(
    ProductId       INT IDENTITY(1,1) CONSTRAINT PK_Products PRIMARY KEY CLUSTERED,
    ProductName     NVARCHAR(200)     NOT NULL,
    Sku             NVARCHAR(50)      NOT NULL,
    UnitPrice       DECIMAL(18,2)     NOT NULL,
    IsActive        BIT               NOT NULL CONSTRAINT DF_Products_IsActive DEFAULT (1),
    CreatedAt       DATETIME2(0)      NOT NULL CONSTRAINT DF_Products_CreatedAt DEFAULT (SYSUTCDATETIME()),

    CONSTRAINT UQ_Products_Sku UNIQUE (Sku)
);
GO

-- Orders
CREATE TABLE dbo.Orders
(
    OrderId         INT IDENTITY(1,1) CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED,
    CustomerId      INT               NOT NULL,
    OrderDate       DATETIME2(0)      NOT NULL CONSTRAINT DF_Orders_OrderDate DEFAULT (SYSUTCDATETIME()),
    Status          NVARCHAR(20)      NOT NULL,  -- e.g. 'Pending', 'Paid', 'Shipped', 'Cancelled'
    TotalAmount     DECIMAL(18,2)     NOT NULL CONSTRAINT DF_Orders_TotalAmount DEFAULT (0),

    CONSTRAINT FK_Orders_Customers
        FOREIGN KEY (CustomerId) REFERENCES dbo.Customers(CustomerId)
);
GO

-- OrderItems
CREATE TABLE dbo.OrderItems
(
    OrderItemId     INT IDENTITY(1,1) CONSTRAINT PK_OrderItems PRIMARY KEY CLUSTERED,
    OrderId         INT               NOT NULL,
    ProductId       INT               NOT NULL,
    Quantity        INT               NOT NULL CHECK (Quantity > 0),
    UnitPrice       DECIMAL(18,2)     NOT NULL,
    LineTotal       AS (Quantity * UnitPrice) PERSISTED,

    CONSTRAINT FK_OrderItems_Orders
        FOREIGN KEY (OrderId) REFERENCES dbo.Orders(OrderId),

    CONSTRAINT FK_OrderItems_Products
        FOREIGN KEY (ProductId) REFERENCES dbo.Products(ProductId)
);
GO

-- Payments
CREATE TABLE dbo.Payments
(
    PaymentId       INT IDENTITY(1,1) CONSTRAINT PK_Payments PRIMARY KEY CLUSTERED,
    OrderId         INT               NOT NULL,
    PaidAmount      DECIMAL(18,2)     NOT NULL,
    PaidAt          DATETIME2(0)      NOT NULL CONSTRAINT DF_Payments_PaidAt DEFAULT (SYSUTCDATETIME()),
    Method          NVARCHAR(20)      NOT NULL,  -- e.g. 'Card', 'UPI', 'NetBanking', 'COD'
    ReferenceNumber NVARCHAR(100)     NULL,

    CONSTRAINT FK_Payments_Orders
        FOREIGN KEY (OrderId) REFERENCES dbo.Orders(OrderId)
);
GO
