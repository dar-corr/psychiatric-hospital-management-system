/*
  Пробные учётные записи: demo_admin, demo_doctor, demo_nurse.
  Пароль для всех: Demo2026!
  ВНИМАНИЕ: этот пароль публичный, использовать только для локальной демо-БД!
  Хеш рассчитан тем же способом, что в Utils/PasswordHelper.cs:
  SHA-256 от UTF-8 байтов, 64 шестнадцатеричных символа.
*/
USE [PsychiatricHospitalDB];
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Username = N'demo_admin')
    INSERT INTO dbo.Users (Username, PasswordHash, FullName, [Role])
    VALUES (N'demo_admin', N'DCA83B66653FE863D15EE28B02CFBE058CC89505E3587988C7940F6C2362CE6C', N'Демо-администратор', N'admin');
IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Username = N'demo_doctor')
    INSERT INTO dbo.Users (Username, PasswordHash, FullName, [Role])
    VALUES (N'demo_doctor', N'DCA83B66653FE863D15EE28B02CFBE058CC89505E3587988C7940F6C2362CE6C', N'Демо-врач', N'doctor');
IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Username = N'demo_nurse')
    INSERT INTO dbo.Users (Username, PasswordHash, FullName, [Role])
    VALUES (N'demo_nurse', N'DCA83B66653FE863D15EE28B02CFBE058CC89505E3587988C7940F6C2362CE6C', N'Демо-медсестра', N'nurse');

-- Палаты, нужные для регистрации пациентов через интерфейс.
IF NOT EXISTS (SELECT 1 FROM dbo.Wards WHERE WardNumber = N'101')
    INSERT INTO dbo.Wards (WardNumber, Department, TotalBeds)
    VALUES (N'101', N'Острое', 3);
IF NOT EXISTS (SELECT 1 FROM dbo.Wards WHERE WardNumber = N'102')
    INSERT INTO dbo.Wards (WardNumber, Department, TotalBeds)
    VALUES (N'102', N'Острое', 2);
IF NOT EXISTS (SELECT 1 FROM dbo.Wards WHERE WardNumber = N'201')
    INSERT INTO dbo.Wards (WardNumber, Department, TotalBeds)
    VALUES (N'201', N'Реабилитация', 4);
GO

PRINT N'Демо-пользователи и палаты добавлены (если отсутствовали).';
SELECT Username, FullName, [Role], IsActive FROM dbo.Users WHERE Username LIKE N'demo_%';
SELECT WardNumber, Department, TotalBeds, OccupiedBeds FROM dbo.Wards ORDER BY WardNumber;
GO
