USE [master];
GO
IF DB_ID(N'PsychiatricHospitalDB') IS NULL
BEGIN
    CREATE DATABASE [PsychiatricHospitalDB];
END;
GO
USE [PsychiatricHospitalDB];
GO

-- 1. Users
IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Users (
        UserId       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Users PRIMARY KEY,
        Username     NVARCHAR(50) NOT NULL,
        PasswordHash NVARCHAR(256) NOT NULL,
        FullName     NVARCHAR(150) NOT NULL,
        [Role]       NVARCHAR(20) NOT NULL,
        IsActive     BIT NOT NULL CONSTRAINT DF_Users_IsActive DEFAULT (1),
        CreatedAt    DATETIME NOT NULL CONSTRAINT DF_Users_CreatedAt DEFAULT (GETDATE()),
        LastLogin    DATETIME NULL,
        CONSTRAINT UQ_Users_Username UNIQUE (Username),
        CONSTRAINT CK_Users_Role CHECK ([Role] IN (N'doctor', N'nurse', N'admin'))
    );
END;
GO

-- 2. Wards (до Patients из-за внешнего ключа)
IF OBJECT_ID(N'dbo.Wards', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Wards (
        WardId       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Wards PRIMARY KEY,
        WardNumber   NVARCHAR(10) NOT NULL,
        Department   NVARCHAR(100) NOT NULL,
        TotalBeds    INT NOT NULL,
        OccupiedBeds INT NOT NULL CONSTRAINT DF_Wards_OccupiedBeds DEFAULT (0),
        CONSTRAINT UQ_Wards_WardNumber UNIQUE (WardNumber),
        CONSTRAINT CK_Wards_TotalBeds CHECK (TotalBeds > 0),
        CONSTRAINT CK_Wards_OccupiedBeds CHECK (OccupiedBeds >= 0 AND OccupiedBeds <= TotalBeds)
    );
END;
GO

-- 3. Patients
IF OBJECT_ID(N'dbo.Patients', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Patients (
        PatientId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Patients PRIMARY KEY,
        CardNumber     NVARCHAR(20) NOT NULL,
        FullName       NVARCHAR(150) NOT NULL,
        BirthDate      DATE NOT NULL,
        ContactInfo    NVARCHAR(200) NULL,
        AdmissionDate  DATETIME NOT NULL CONSTRAINT DF_Patients_AdmissionDate DEFAULT (GETDATE()),
        Diagnosis      NVARCHAR(500) NULL,
        [Status]       NVARCHAR(20) NOT NULL CONSTRAINT DF_Patients_Status DEFAULT (N'active'),
        DischargeDate  DATETIME NULL,
        WardId         INT NULL,
        CONSTRAINT UQ_Patients_CardNumber UNIQUE (CardNumber),
        CONSTRAINT CK_Patients_Status CHECK ([Status] IN (N'active', N'discharged')),
        CONSTRAINT FK_Patients_Wards FOREIGN KEY (WardId)
            REFERENCES dbo.Wards(WardId) ON DELETE NO ACTION
    );
END;
GO

-- 4. MedicalRecords
IF OBJECT_ID(N'dbo.MedicalRecords', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MedicalRecords (
        RecordId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_MedicalRecords PRIMARY KEY,
        PatientId     INT NOT NULL,
        DoctorId      INT NOT NULL,
        RecordDate    DATETIME NOT NULL CONSTRAINT DF_MedicalRecords_RecordDate DEFAULT (GETDATE()),
        [Description] NVARCHAR(MAX) NOT NULL,
        CreatedAt     DATETIME NOT NULL CONSTRAINT DF_MedicalRecords_CreatedAt DEFAULT (GETDATE()),
        RecordType    NVARCHAR(50) NOT NULL CONSTRAINT DF_MedicalRecords_RecordType DEFAULT (N'осмотр'),
        CONSTRAINT CK_MedicalRecords_RecordType CHECK
            (LOWER(RecordType) IN (N'осмотр', N'консультация', N'изменение_состояния', N'анализы', N'назначение')),
        CONSTRAINT FK_MedicalRecords_Patients FOREIGN KEY (PatientId)
            REFERENCES dbo.Patients(PatientId) ON DELETE NO ACTION,
        CONSTRAINT FK_MedicalRecords_Users FOREIGN KEY (DoctorId)
            REFERENCES dbo.Users(UserId) ON DELETE NO ACTION
    );
END;
GO

-- 5. Prescriptions
IF OBJECT_ID(N'dbo.Prescriptions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Prescriptions (
        PrescriptionId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Prescriptions PRIMARY KEY,
        PatientId        INT NOT NULL,
        DoctorId         INT NOT NULL,
        PrescriptionType NVARCHAR(50) NOT NULL,
        [Name]           NVARCHAR(200) NOT NULL,
        Dosage           NVARCHAR(100) NULL,
        Frequency        NVARCHAR(100) NOT NULL,
        Duration         INT NOT NULL,
        StartDate        DATE NOT NULL,
        EndDate          DATE NOT NULL,
        [Status]         NVARCHAR(50) NOT NULL CONSTRAINT DF_Prescriptions_Status DEFAULT (N'Активно'),
        CancelReason     NVARCHAR(500) NULL,
        Notes            NVARCHAR(MAX) NULL,
        CreatedAt        DATETIME NOT NULL CONSTRAINT DF_Prescriptions_CreatedAt DEFAULT (GETDATE()),
        CanceledAt       DATETIME NULL,
        CanceledBy       INT NULL,
        CONSTRAINT CK_Prescriptions_Type CHECK (PrescriptionType IN (N'Медикамент', N'Процедура')),
        CONSTRAINT CK_Prescriptions_Status CHECK ([Status] IN (N'Активно', N'Завершено', N'Отменено')),
        CONSTRAINT CK_Prescriptions_Duration CHECK (Duration > 0),
        CONSTRAINT FK_Prescriptions_Patient FOREIGN KEY (PatientId)
            REFERENCES dbo.Patients(PatientId) ON DELETE NO ACTION,
        CONSTRAINT FK_Prescriptions_Doctor FOREIGN KEY (DoctorId)
            REFERENCES dbo.Users(UserId) ON DELETE NO ACTION,
        CONSTRAINT FK_Prescriptions_CanceledBy FOREIGN KEY (CanceledBy)
            REFERENCES dbo.Users(UserId) ON DELETE NO ACTION
    );
END;
GO

-- 6. PrescriptionExecutions
IF OBJECT_ID(N'dbo.PrescriptionExecutions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.PrescriptionExecutions (
        ExecutionId    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PrescriptionExecutions PRIMARY KEY,
        PrescriptionId INT NOT NULL,
        ExecutedBy     INT NOT NULL,
        ExecutionDate  DATETIME NOT NULL CONSTRAINT DF_PrescriptionExecutions_ExecutionDate DEFAULT (GETDATE()),
        Notes          NVARCHAR(500) NULL,
        CreatedAt      DATETIME NOT NULL CONSTRAINT DF_PrescriptionExecutions_CreatedAt DEFAULT (GETDATE()),
        CONSTRAINT FK_Executions_Prescription FOREIGN KEY (PrescriptionId)
            REFERENCES dbo.Prescriptions(PrescriptionId) ON DELETE NO ACTION,
        CONSTRAINT FK_Executions_User FOREIGN KEY (ExecutedBy)
            REFERENCES dbo.Users(UserId) ON DELETE NO ACTION
    );
END;
GO

-- 7. Discharges
IF OBJECT_ID(N'dbo.Discharges', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Discharges (
        DischargeId    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Discharges PRIMARY KEY,
        PatientId      INT NOT NULL,
        DischargeDate  DATETIME NOT NULL,
        Reason         NVARCHAR(200) NOT NULL,
        FinalDiagnosis NVARCHAR(MAX) NOT NULL,
        DischargedBy   INT NOT NULL,
        CreatedAt      DATETIME NOT NULL CONSTRAINT DF_Discharges_CreatedAt DEFAULT (GETDATE()),
        CONSTRAINT FK_Discharges_Patients FOREIGN KEY (PatientId)
            REFERENCES dbo.Patients(PatientId) ON DELETE NO ACTION,
        CONSTRAINT FK_Discharges_Users FOREIGN KEY (DischargedBy)
            REFERENCES dbo.Users(UserId) ON DELETE NO ACTION
    );
END;
GO

-- 8. AuditLog
IF OBJECT_ID(N'dbo.AuditLog', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AuditLog (
        LogId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AuditLog PRIMARY KEY,
        UserId     INT NOT NULL,
        [Action]   NVARCHAR(100) NOT NULL,
        EntityType NVARCHAR(50) NOT NULL,
        EntityId   INT NULL,
        [Timestamp] DATETIME NOT NULL CONSTRAINT DF_AuditLog_Timestamp DEFAULT (GETDATE()),
        Details    NVARCHAR(500) NULL,
        CONSTRAINT FK_AuditLog_Users FOREIGN KEY (UserId)
            REFERENCES dbo.Users(UserId) ON DELETE NO ACTION
    );
END;
GO

-- Индексы для поиска и фильтрации. CardNumber уже индексируется UNIQUE-ограничением.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Patients_Status' AND object_id = OBJECT_ID(N'dbo.Patients'))
    CREATE INDEX IX_Patients_Status ON dbo.Patients([Status]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MedicalRecords_PatientId' AND object_id = OBJECT_ID(N'dbo.MedicalRecords'))
    CREATE INDEX IX_MedicalRecords_PatientId ON dbo.MedicalRecords(PatientId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MedicalRecords_RecordDate' AND object_id = OBJECT_ID(N'dbo.MedicalRecords'))
    CREATE INDEX IX_MedicalRecords_RecordDate ON dbo.MedicalRecords(RecordDate);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Prescriptions_PatientId' AND object_id = OBJECT_ID(N'dbo.Prescriptions'))
    CREATE INDEX IX_Prescriptions_PatientId ON dbo.Prescriptions(PatientId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Prescriptions_Status' AND object_id = OBJECT_ID(N'dbo.Prescriptions'))
    CREATE INDEX IX_Prescriptions_Status ON dbo.Prescriptions([Status]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Executions_PrescriptionId' AND object_id = OBJECT_ID(N'dbo.PrescriptionExecutions'))
    CREATE INDEX IX_Executions_PrescriptionId ON dbo.PrescriptionExecutions(PrescriptionId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Discharges_PatientId' AND object_id = OBJECT_ID(N'dbo.Discharges'))
    CREATE INDEX IX_Discharges_PatientId ON dbo.Discharges(PatientId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Discharges_DischargeDate' AND object_id = OBJECT_ID(N'dbo.Discharges'))
    CREATE INDEX IX_Discharges_DischargeDate ON dbo.Discharges(DischargeDate);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_AuditLog_Timestamp' AND object_id = OBJECT_ID(N'dbo.AuditLog'))
    CREATE INDEX IX_AuditLog_Timestamp ON dbo.AuditLog([Timestamp]);
GO

PRINT N'Готово: структура PsychiatricHospitalDB создана/проверена. Демо-данные добавляются отдельно.';
SELECT name AS TableName FROM sys.tables WHERE schema_id = SCHEMA_ID(N'dbo') ORDER BY name;
GO
