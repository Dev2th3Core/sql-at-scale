-- Generates ~80 products with realistic-ish names, SKUs, and prices

USE OrderManagement;
GO

-- Optional: clear existing data for repeatability during learning
DELETE FROM dbo.Products;
GO

------------------------------
-- 1. Helper lookup tables
------------------------------
DECLARE @Categories TABLE (Id INT IDENTITY(1,1), Category NVARCHAR(50));
DECLARE @Types      TABLE (Id INT IDENTITY(1,1), TypeName NVARCHAR(100));

INSERT INTO @Categories (Category)
VALUES
(N'Electronics'),
(N'Accessories'),
(N'Office'),
(N'Gaming'),
(N'Audio'),
(N'Mobile'),
(N'Laptop'),
(N'Network');

INSERT INTO @Types (TypeName)
VALUES
(N'Wireless Mouse'),
(N'Mechanical Keyboard'),
(N'USB-C Cable'),
(N'HDMI Cable'),
(N'Laptop Stand'),
(N'Monitor 24-inch'),
(N'Monitor 27-inch'),
(N'Headphones Over-Ear'),
(N'Earbuds'),
(N'Bluetooth Speaker'),
(N'Webcam'),
(N'Router Dual-Band'),
(N'External HDD 1TB'),
(N'SSD 512GB'),
(N'Power Bank'),
(N'Phone Charger'),
(N'Wireless Charger'),
(N'Mouse Pad'),
(N'Office Chair'),
(N'Desk Lamp');

DECLARE @CategoryCount INT = (SELECT COUNT(*) FROM @Categories);
DECLARE @TypeCount     INT = (SELECT COUNT(*) FROM @Types);

------------------------------
-- 2. Loop to create ~80 products
------------------------------
DECLARE @TargetProducts INT = 80;
DECLARE @i INT = 1;

WHILE @i <= @TargetProducts
BEGIN
    DECLARE @CategoryId INT = 1 + ABS(CHECKSUM(NEWID())) % @CategoryCount;
    DECLARE @TypeId     INT = 1 + ABS(CHECKSUM(NEWID())) % @TypeCount;

    DECLARE @Category NVARCHAR(50);
    DECLARE @TypeName NVARCHAR(100);

    SELECT @Category = Category FROM @Categories WHERE Id = @CategoryId;
    SELECT @TypeName = TypeName FROM @Types WHERE Id = @TypeId;

    -- Build a product name like: "Electronics – Wireless Mouse"
    DECLARE @ProductName NVARCHAR(200) =
        @Category + N' – ' + @TypeName;

    --------------------------------------------------------
    -- Price logic: base price by category + small variation
    --------------------------------------------------------
    DECLARE @BasePrice DECIMAL(18,2);

    SET @BasePrice =
        CASE @Category
            WHEN N'Electronics' THEN 2500.00
            WHEN N'Gaming'      THEN 4000.00
            WHEN N'Audio'       THEN 2000.00
            WHEN N'Mobile'      THEN 1500.00
            WHEN N'Laptop'      THEN 45000.00
            WHEN N'Network'     THEN 3000.00
            WHEN N'Office'      THEN 1800.00
            WHEN N'Accessories' THEN 800.00
            ELSE 1000.00
        END;

    -- Random factor between 0.8x and 1.2x
    DECLARE @RandPercent INT = ABS(CHECKSUM(NEWID())) % 41 + 80; -- 80 to 120
    DECLARE @UnitPrice DECIMAL(18,2) =
        ROUND(@BasePrice * (@RandPercent / 100.0), 2);

    --------------------------------------------------------
    -- SKU logic: CAT-XXX (e.g., ELE-001, GAM-015)
    --------------------------------------------------------
    DECLARE @CategoryCode NVARCHAR(3) =
        UPPER(LEFT(REPLACE(@Category, N' ', N''), 3));

    DECLARE @Sku NVARCHAR(50) =
        @CategoryCode + '-' +
        RIGHT('000' + CAST(@i AS NVARCHAR(10)), 3);

    --------------------------------------------------------
    -- IsActive: 90% active, 10% inactive
    --------------------------------------------------------
    DECLARE @IsActive BIT =
        CASE WHEN (@i % 10) = 0 THEN 0 ELSE 1 END;

    INSERT INTO dbo.Products (ProductName, Sku, UnitPrice, IsActive)
    VALUES (@ProductName, @Sku, @UnitPrice, @IsActive);

    SET @i += 1;
END
GO

-- Quick sanity check
SELECT TOP 10 ProductId, ProductName, Sku, UnitPrice, IsActive
FROM dbo.Products
ORDER BY ProductId;
GO

-- Quick Count Check
SELECT COUNT(*) AS TotalProducts
FROM dbo.Products
GO