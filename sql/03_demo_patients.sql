/*
    - 7 пациентов (6 на лечении, 1 выписан);
    - 11 медицинских записей;
    - 8 назначений (активные, завершённые, отменённые);
    - 7 отметок выполнения назначений;
    - 1 запись о выписке.

  Повторный запуск: если все 7 демо-карт существуют, ничего не меняет.
  Если есть только часть демо-карт, остановится с ошибкой: не будет
  дублировать связанные медицинские записи или вмешиваться в данные.

  Скрипт НЕ удаляет данные и НЕ меняет существующие пользовательские
  записи. Для загрузки нужны демо-учётные записи и палаты из файла 02.
*/
USE [PsychiatricHospitalDB];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @DoctorId INT = (
        SELECT UserId FROM dbo.Users
        WHERE Username = N'demo_doctor' AND [Role] = N'doctor' AND IsActive = 1
    );
    DECLARE @NurseId INT = (
        SELECT UserId FROM dbo.Users
        WHERE Username = N'demo_nurse' AND [Role] = N'nurse' AND IsActive = 1
    );

    IF @DoctorId IS NULL OR @NurseId IS NULL
        THROW 51001, N'Нет тестового врача или медсестры. Сначала выполните 02_demo_data.sql.', 1;

    IF (SELECT COUNT(*) FROM dbo.Wards WHERE WardNumber IN (N'101', N'102', N'201')) <> 3
        THROW 51002, N'Не найдены демо-палаты 101, 102 и 201. Сначала выполните 02_demo_data.sql.', 1;

    DECLARE @ExistingDemoPatients INT = (
        SELECT COUNT(*) FROM dbo.Patients
        WHERE CardNumber IN (
            N'DEMO-001', N'DEMO-002', N'DEMO-003', N'DEMO-004',
            N'DEMO-005', N'DEMO-006', N'DEMO-007'
        )
    );

    IF @ExistingDemoPatients = 7
    BEGIN
        PRINT N'Все семь демо-пациентов уже существуют. Повторная загрузка пропущена.';
    END
    ELSE
    BEGIN
        IF @ExistingDemoPatients <> 0
            THROW 51003, N'Найден неполный набор DEMO-001 ... DEMO-007. Во избежание дублей загрузка остановлена.', 1;

        -- Проверяем корректность счётчиков палат и достаточное число мест.
        -- Этот скрипт должен запускаться на пустых/корректно учтённых палатах.
        IF EXISTS (
            SELECT 1
            FROM dbo.Wards w
            INNER JOIN (VALUES
                (N'101', 2), (N'102', 2), (N'201', 2)
            ) needed(WardNumber, NewPatients) ON needed.WardNumber = w.WardNumber
            OUTER APPLY (
                SELECT COUNT(*) AS ActualOccupied
                FROM dbo.Patients p
                WHERE p.WardId = w.WardId AND p.[Status] = N'active'
            ) patientsInWard
            WHERE w.OccupiedBeds <> patientsInWard.ActualOccupied
               OR w.TotalBeds - w.OccupiedBeds < needed.NewPatients
        )
            THROW 51004, N'В одной из демо-палат недостаточно мест или OccupiedBeds не совпадает с активными пациентами.', 1;

        -- Номера карт DEMO-* специально НЕ пересекаются с MK-YYYY-NNN,
        -- которые автоматически генерирует приложение.
        DECLARE @PatientData TABLE (
            CardNumber NVARCHAR(20) NOT NULL PRIMARY KEY,
            FullName NVARCHAR(150) NOT NULL,
            BirthDate DATE NOT NULL,
            AdmissionDays INT NOT NULL,
            Diagnosis NVARCHAR(500) NOT NULL,
            [Status] NVARCHAR(20) NOT NULL,
            DischargeDays INT NULL,
            WardNumber NVARCHAR(10) NULL
        );

        INSERT INTO @PatientData
            (CardNumber, FullName, BirthDate, AdmissionDays, Diagnosis, [Status], DischargeDays, WardNumber)
        VALUES
            (N'DEMO-001', N'Алексей Тестов',       '1998-05-12', -12, N'Тревожное расстройство', N'active',     NULL, N'101'),
            (N'DEMO-002', N'Вера Примерова',       '2001-11-23',  -4, N'Депрессивный эпизод',  N'active',     NULL, N'101'),
            (N'DEMO-003', N'Илья Демонстрационный','1985-07-10', -18, N'Расстройство адаптации',N'active',     NULL, N'102'),
            (N'DEMO-004', N'Марина Учебная',       '1994-04-03',  -7, N'Тревожное расстройство', N'active',     NULL, N'102'),
            (N'DEMO-005', N'Кирилл Образцов',      '1979-10-09', -23, N'Депрессивный эпизод',  N'active',     NULL, N'201'),
            (N'DEMO-006', N'Нина Тестовая',        '1996-02-17',  -9, N'Расстройство адаптации',N'active',     NULL, N'201'),
            (N'DEMO-007', N'Олег Примеров',        '1990-08-11', -35, N'Тревожное расстройство', N'discharged',   -5, NULL);

        INSERT INTO dbo.Patients
            (CardNumber, FullName, BirthDate, ContactInfo, AdmissionDate,
             Diagnosis, [Status], DischargeDate, WardId)
        SELECT d.CardNumber, d.FullName, d.BirthDate,
               N'Учебные данные, контакт отсутствует',
               DATEADD(DAY, d.AdmissionDays, GETDATE()),
               d.Diagnosis, d.[Status],
               CASE WHEN d.DischargeDays IS NULL THEN NULL
                    ELSE DATEADD(DAY, d.DischargeDays, GETDATE()) END,
               w.WardId
        FROM @PatientData d
        LEFT JOIN dbo.Wards w ON w.WardNumber = d.WardNumber;

        -- Обновляем счётчики мест для шести размещённых пациентов.
        UPDATE w
        SET w.OccupiedBeds = w.OccupiedBeds + d.NewPatients
        FROM dbo.Wards w
        INNER JOIN (VALUES
            (N'101', 2), (N'102', 2), (N'201', 2)
        ) d(WardNumber, NewPatients) ON d.WardNumber = w.WardNumber;

        -- Разные виды записей для проверки истории и фильтрации медкарты.
        DECLARE @RecordData TABLE (
            CardNumber NVARCHAR(20) NOT NULL,
            DaysAgo INT NOT NULL,
            RecordType NVARCHAR(50) NOT NULL,
            [Description] NVARCHAR(1000) NOT NULL
        );

        INSERT INTO @RecordData VALUES
            (N'DEMO-001', -11, N'осмотр',               N'Первичный осмотр. Запись: состояние фиксируется для демонстрации медицинской карты.'),
            (N'DEMO-001',  -2, N'изменение_состояния', N'Повторная оценка состояния. Запись: отмечена динамика наблюдения.'),
            (N'DEMO-002',  -3, N'консультация',        N'Первичная консультация. Запись: собран анамнез и намечен план наблюдения.'),
            (N'DEMO-003', -17, N'осмотр',              N'Осмотр после поступления. Запись: зафиксированы основные жалобы.'),
            (N'DEMO-003',  -6, N'анализы',             N'Запись: результаты условных лабораторных исследований зарегистрированы.'),
            (N'DEMO-004',  -5, N'консультация',        N'Учебная консультация: обсуждён план дальнейших наблюдений.'),
            (N'DEMO-005', -21, N'осмотр',              N'Первичный осмотр.'),
            (N'DEMO-005',  -3, N'изменение_состояния', N'Повторное наблюдение.'),
            (N'DEMO-006',  -8, N'осмотр',              N'Первичный осмотр. Запись для заполнения хронологии.'),
            (N'DEMO-007', -30, N'осмотр',              N'Первичный осмотр ранее поступившего пациента.'),
            (N'DEMO-007',  -7, N'консультация',        N'Заключительная консультация перед выпиской.');

        INSERT INTO dbo.MedicalRecords
            (PatientId, DoctorId, RecordDate, [Description], RecordType)
        SELECT p.PatientId, @DoctorId,
               DATEADD(DAY, r.DaysAgo, GETDATE()),
               r.[Description], r.RecordType
        FROM @RecordData r
        INNER JOIN dbo.Patients p ON p.CardNumber = r.CardNumber;

        -- Частота соответствует значениям, используемым в WPF ComboBox.
        DECLARE @PrescriptionData TABLE (
            CardNumber NVARCHAR(20) NOT NULL,
            [Name] NVARCHAR(200) NOT NULL,
            PrescriptionType NVARCHAR(50) NOT NULL,
            Dosage NVARCHAR(100) NULL,
            Frequency NVARCHAR(100) NOT NULL,
            Duration INT NOT NULL,
            StartDays INT NOT NULL,
            [Status] NVARCHAR(50) NOT NULL,
            CancelReason NVARCHAR(500) NULL,
            Notes NVARCHAR(300) NULL,
            CanceledDays INT NULL
        );

        INSERT INTO @PrescriptionData VALUES
            (N'DEMO-001', N'Контроль самочувствия',         N'Процедура',  NULL,                   N'Один раз в день',                             14,  -3, N'Активно',    NULL, NULL, NULL),
            (N'DEMO-001', N'Учебный препарат А',           N'Медикамент', N'1 усл. ед. (демо)',   N'Два раза в день (утро, вечер)',             14,  -2, N'Активно',    NULL, N'Вымышленный препарат, только для тестирования.', NULL),
            (N'DEMO-002', N'Индивидуальная консультация',  N'Процедура',  NULL,                   N'По необходимости',                         10,  -2, N'Активно',    NULL, NULL, NULL),
            (N'DEMO-003', N'Оценка качества сна',          N'Процедура',  NULL,                   N'Один раз в день',                           21,  -7, N'Активно',    NULL, NULL, NULL),
            (N'DEMO-004', N'Ежедневное наблюдение',        N'Процедура',  NULL,                   N'Один раз в день',                           14,  -1, N'Активно',    NULL, NULL, NULL),
            (N'DEMO-005', N'Групповая консультация',       N'Процедура',  NULL,                   N'Один раз в день',                            5, -15, N'Завершено',  NULL, N'Учебное завершённое назначение.', NULL),
            (N'DEMO-006', N'Учебный препарат Б',           N'Медикамент', N'1 усл. ед. (демо)',   N'Один раз в день',                           10,  -8, N'Отменено', N'Отменено по демонстрационному сценарию', N'Вымышленный препарат.', -4),
            (N'DEMO-007', N'Заключительная консультация',  N'Процедура',  NULL,                   N'Один раз в день',                            5, -12, N'Завершено',  NULL, N'Проведена до выписки.', NULL);

        INSERT INTO dbo.Prescriptions
            (PatientId, DoctorId, PrescriptionType, [Name], Dosage,
             Frequency, Duration, StartDate, EndDate, [Status],
             CancelReason, Notes, CreatedAt, CanceledAt, CanceledBy)
        SELECT p.PatientId, @DoctorId, d.PrescriptionType, d.[Name], d.Dosage,
               d.Frequency, d.Duration,
               CONVERT(DATE, DATEADD(DAY, d.StartDays, GETDATE())),
               DATEADD(DAY, d.Duration, CONVERT(DATE, DATEADD(DAY, d.StartDays, GETDATE()))),
               d.[Status], d.CancelReason, d.Notes,
               DATEADD(DAY, d.StartDays, GETDATE()),
               CASE WHEN d.CanceledDays IS NULL THEN NULL
                    ELSE DATEADD(DAY, d.CanceledDays, GETDATE()) END,
               CASE WHEN d.[Status] = N'Отменено' THEN @DoctorId ELSE NULL END
        FROM @PrescriptionData d
        INNER JOIN dbo.Patients p ON p.CardNumber = d.CardNumber;

        DECLARE @ExecutionData TABLE (
            CardNumber NVARCHAR(20) NOT NULL,
            PrescriptionName NVARCHAR(200) NOT NULL,
            DaysAgo INT NOT NULL,
            MinuteOfDay INT NOT NULL,
            Notes NVARCHAR(500) NULL
        );

        INSERT INTO @ExecutionData VALUES
            (N'DEMO-001', N'Контроль самочувствия',         -2,  540, N'Отметка выполнения учебной процедуры.'),
            (N'DEMO-001', N'Контроль самочувствия',         -1,  540, N'Повторная отметка выполнения.'),
            (N'DEMO-001', N'Учебный препарат А',           -1,  480, N'Учебная отметка, препарат вымышленный.'),
            (N'DEMO-001', N'Учебный препарат А',           -1, 1200, N'Учебная вечерняя отметка.'),
            (N'DEMO-003', N'Оценка качества сна',          -2,  540, N'Проведена учебная оценка сна.'),
            (N'DEMO-005', N'Групповая консультация',      -13,  660, N'Учебная групповая консультация.'),
            (N'DEMO-007', N'Заключительная консультация', -10,  600, N'Учебная консультация до выписки.');

        INSERT INTO dbo.PrescriptionExecutions
            (PrescriptionId, ExecutedBy, ExecutionDate, Notes)
        SELECT pr.PrescriptionId, @NurseId,
               DATEADD(MINUTE, e.MinuteOfDay,
                   DATEADD(DAY, e.DaysAgo, CONVERT(DATETIME, CONVERT(DATE, GETDATE())))),
               e.Notes
        FROM @ExecutionData e
        INNER JOIN dbo.Patients p ON p.CardNumber = e.CardNumber
        INNER JOIN dbo.Prescriptions pr
            ON pr.PatientId = p.PatientId AND pr.[Name] = e.PrescriptionName;

        -- Выписанный пациент отображается в фильтре "Выписан" и отчётах.
        INSERT INTO dbo.Discharges
            (PatientId, DischargeDate, Reason, FinalDiagnosis, DischargedBy)
        SELECT p.PatientId, p.DischargeDate,
               N'Завершение демонстрационного наблюдения',
               N'Заключительный диагноз в учебном примере: наблюдение завершено.',
               @DoctorId
        FROM dbo.Patients p WHERE p.CardNumber = N'DEMO-007';

        PRINT N'Учебные пациенты, история, назначения и выписка добавлены.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

-- Итоговое состояние демо-пациентов и счётчиков палат.
SELECT p.CardNumber, p.FullName, p.[Status], w.WardNumber,
       (SELECT COUNT(*) FROM dbo.MedicalRecords mr WHERE mr.PatientId = p.PatientId) AS RecordsCount,
       (SELECT COUNT(*) FROM dbo.Prescriptions pr WHERE pr.PatientId = p.PatientId) AS PrescriptionsCount
FROM dbo.Patients p
LEFT JOIN dbo.Wards w ON w.WardId = p.WardId
WHERE p.CardNumber IN (
    N'DEMO-001', N'DEMO-002', N'DEMO-003', N'DEMO-004',
    N'DEMO-005', N'DEMO-006', N'DEMO-007'
)
ORDER BY p.CardNumber;

SELECT WardNumber, TotalBeds, OccupiedBeds, TotalBeds - OccupiedBeds AS AvailableBeds
FROM dbo.Wards
WHERE WardNumber IN (N'101', N'102', N'201')
ORDER BY WardNumber;
GO
