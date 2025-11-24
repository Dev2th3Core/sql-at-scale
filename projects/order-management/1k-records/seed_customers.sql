-- Generates ~150 customers with realistic-looking names, emails, and phone numbers

USE OrderManagement;
GO

-- Optional: clear existing data for repeatability during learning
DELETE FROM dbo.Customers;
GO

------------------------------
-- 1. Helper name lists
------------------------------
DECLARE @FirstNames TABLE (Id INT IDENTITY(1,1), FirstName NVARCHAR(100));
DECLARE @LastNames  TABLE (Id INT IDENTITY(1,1), LastName  NVARCHAR(100));
DECLARE @EmailDomains TABLE (Id INT IDENTITY(1,1), Domain NVARCHAR(100));

INSERT INTO @FirstNames (FirstName)
VALUES
('Aarav'), ('Vivaan'), ('Aditya'), ('Vihaan'), ('Arjun'),
('Reyansh'), ('Mohit'), ('Rahul'), ('Rohit'), ('Siddharth'),
('Neha'), ('Priya'), ('Kavya'), ('Ananya'), ('Isha'),
('Riya'), ('Sonia'), ('Pooja'), ('Divya'), ('Esha'),
('Kiran'), ('Sagar'), ('Nikhil'), ('Akshay'), ('Chetan'),
('Meera'), ('Shruti'), ('Payal'), ('Radhika'), ('Swati');

INSERT INTO @LastNames (LastName)
VALUES
('Shah'), ('Patil'), ('Kulkarni'), ('Iyer'), ('Rao'),
('Mehta'), ('Desai'), ('Joshi'), ('Gupta'), ('Verma'),
('Chauhan'), ('Reddy'), ('Nair'), ('Kapoor'), ('Malhotra'),
('Bhatia'), ('Jain'), ('Agarwal'), ('Shinde'), ('Yadav'),
('Khan'), ('Shetty'), ('Sawant'), ('Gokhale'), ('Pawar'),
('Mishra'), ('Srivastava'), ('Pandey'), ('Chatterjee'), ('Das');

INSERT INTO @EmailDomains (Domain)
VALUES
('gmail.com'),
('mail.com'),
('yahoo.com'),
('hotmail.com'),
('icloud.com');

DECLARE @FirstCount INT = (SELECT COUNT(*) FROM @FirstNames);
DECLARE @LastCount  INT = (SELECT COUNT(*) FROM @LastNames);
DECLARE @DomainCount INT = (SELECT COUNT(*) FROM @EmailDomains);

------------------------------
-- 2. Loop to create ~150 customers
------------------------------
DECLARE @TargetCustomers INT = 150;
DECLARE @i INT = 1;

WHILE @i <= @TargetCustomers
BEGIN
    -- Random picks
    DECLARE @FirstId INT = 1 + ABS(CHECKSUM(NEWID())) % @FirstCount;
    DECLARE @LastId  INT = 1 + ABS(CHECKSUM(NEWID())) % @LastCount;
    DECLARE @DomainId INT = 1 + ABS(CHECKSUM(NEWID())) % @DomainCount;

    DECLARE @FirstName NVARCHAR(100);
    DECLARE @LastName  NVARCHAR(100);
    DECLARE @Domain    NVARCHAR(100);

    SELECT @FirstName = FirstName FROM @FirstNames WHERE Id = @FirstId;
    SELECT @LastName  = LastName  FROM @LastNames  WHERE Id = @LastId;
    SELECT @Domain    = Domain    FROM @EmailDomains WHERE Id = @DomainId;

    -- Build email like: firstname.lastnameNN@example.com (lowercase)
    DECLARE @Email NVARCHAR(255) =
        LOWER(
            REPLACE(@FirstName, ' ', '') + '.' +
            REPLACE(@LastName,  ' ', '') +
            CAST(@i AS NVARCHAR(10)) + '@' + @Domain
        );

    -- Simple pseudo-random phone in Indian mobile range
    -- base "9000000000" + offset
    DECLARE @PhoneNumber NVARCHAR(20) =
        CAST(9000000000 + @i AS NVARCHAR(20));

    INSERT INTO dbo.Customers (FirstName, LastName, Email, PhoneNumber)
    VALUES (@FirstName, @LastName, @Email, @PhoneNumber);

    SET @i += 1;
END
GO

-- Quick sanity check
SELECT TOP 10 *
FROM dbo.Customers
ORDER BY CustomerId;
GO

-- Quick Count Check
SELECT COUNT(*) AS TotalCustomers
FROM dbo.Customers;
GO