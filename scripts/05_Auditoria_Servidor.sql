--********
--- auditoria 
USE master;

IF NOT EXISTS (SELECT 1 FROM sys.server_audits WHERE name = 'Audit_Gobierno_Municipal')
BEGIN CREATE SERVER AUDIT Audit_Gobierno_Municipal
    TO FILE (
        FILEPATH = '/ProyectoABD/audit/', -- ruta de tu archivo  ej C:/ProyectoABD/audit
        MAXSIZE = 100 MB,
        MAX_ROLLOVER_FILES = 10,
        RESERVE_DISK_SPACE = OFF
    ) WITH (ON_FAILURE = CONTINUE);
END;

ALTER SERVER AUDIT Audit_Gobierno_Municipal WITH (STATE = ON);

-- con la BD
USE BD_GOBIERNO_MUNICIPAL;

IF NOT EXISTS ( SELECT 1 FROM sys.database_audit_specifications WHERE name = 'AuditSpec_Gobierno_Municipal')
BEGIN CREATE DATABASE AUDIT SPECIFICATION AuditSpec_Gobierno_Municipal FOR SERVER AUDIT Audit_Gobierno_Municipal
    ADD (
        SELECT, INSERT, UPDATE, DELETE
        ON OBJECT::Catastro.Inmuebles
        BY public
    ),
    ADD (
        SELECT, INSERT, UPDATE, DELETE
        ON OBJECT::Recaudaciones.LiquidacionesTributarias
        BY public
    ),

    ADD (
        SELECT, INSERT, UPDATE, DELETE
        ON OBJECT::Recaudaciones.PatentesComerciales
        BY public
    ),

    ADD (
        SELECT, INSERT, UPDATE, DELETE
        ON OBJECT::Recaudaciones.CobrosVentanilla
        BY public
    );
END;

ALTER DATABASE AUDIT SPECIFICATION AuditSpec_Gobierno_Municipal
WITH (STATE = ON);

-- consulta 
SELECT event_time, server_principal_name, database_principal_name, action_id, succeeded, schema_name, object_name, statement
FROM sys.fn_get_audit_file (
    '/ProyectoABD/audit/*.sqlaudit',  -- ruta de tu archivo  ej C:/ProyectoABD/audit
    DEFAULT,
    DEFAULT
)
ORDER BY event_time DESC;


-- PRUEBAS DE AUDITORIA NO ES NECESARIO EJECUTARLO SI NO DECEA REALIZAR PRUEBAS 
USE BD_GOBIERNO_MUNICIPAL;

-- 0 Confirmar que la auditoria esta activa antes de probar
USE master;
SELECT name, is_state_enabled
FROM sys.server_audits
WHERE name = 'Audit_Gobierno_Municipal';

USE BD_GOBIERNO_MUNICIPAL;
SELECT name, is_state_enabled
FROM sys.database_audit_specifications
WHERE name = 'AuditSpec_Gobierno_Municipal';


-- 1. Datos base
INSERT INTO Catastro.Contribuyentes (ci_nit, nombres_razon_social, tipo_persona, telefono, email, direccion_fiscal)
VALUES
('AUD-001', 'CONTRIBUYENTE PRUEBA UNO', 'N', '70000001', 'prueba1@test.com', 'Direccion Prueba 1'),
('AUD-002', 'CONTRIBUYENTE PRUEBA DOS', 'N', '70000002', 'prueba2@test.com', 'Direccion Prueba 2'),
('AUD-003', 'CONTRIBUYENTE PRUEBA TRES', 'J', '70000003', 'prueba3@test.com', 'Direccion Prueba 3');

INSERT INTO Catastro.Inmuebles (codigo_catastral, id_contribuyente, distrito_urbano, superficie_m2, avaluo_catastral, direccion_predio)
SELECT 'AUD-INM-001', id_contribuyente, 1, 100.00, 50000.00, 'Predio Prueba 1'
FROM Catastro.Contribuyentes WHERE ci_nit = 'AUD-001';

INSERT INTO Catastro.Inmuebles (codigo_catastral, id_contribuyente, distrito_urbano, superficie_m2, avaluo_catastral, direccion_predio)
SELECT 'AUD-INM-002', id_contribuyente, 2, 150.00, 75000.00, 'Predio Prueba 2'
FROM Catastro.Contribuyentes WHERE ci_nit = 'AUD-002';

INSERT INTO Catastro.Inmuebles (codigo_catastral, id_contribuyente, distrito_urbano, superficie_m2, avaluo_catastral, direccion_predio)
SELECT 'AUD-INM-003', id_contribuyente, 3, 200.00, 100000.00, 'Predio Prueba 3'
FROM Catastro.Contribuyentes WHERE ci_nit = 'AUD-003';

INSERT INTO Recaudaciones.LiquidacionesTributarias (id_contribuyente, concepto_tributario, gestion_fiscal, monto_determinado)
SELECT id_contribuyente, 'Impuesto_Inmueble', 2026, 500.00
FROM Catastro.Contribuyentes WHERE ci_nit = 'AUD-001';

-- 2. usr_cajero: INSERT (permitido) SELECT (permitido) intento de acceso a Catastro (denegado)
EXECUTE AS USER = 'usr_cajero';

    SELECT * FROM Recaudaciones.LiquidacionesTributarias;

    INSERT INTO Recaudaciones.CobrosVentanilla
        (id_liquidacion, numero_comprobante, monto_cobrado, cajero_ventanilla, metodo_pago)
    SELECT id_liquidacion, 'AUD-COM-001', 500.00, 'usr_cajero', 'Efectivo'
    FROM Recaudaciones.LiquidacionesTributarias
    WHERE monto_determinado = 500.00;

    BEGIN TRY
        SELECT * FROM Catastro.Inmuebles WHERE codigo_catastral LIKE 'AUD-INM-%';
    END TRY
    BEGIN CATCH
        PRINT 'usr_cajero: acceso a Catastro.Inmuebles denegado ';
    END CATCH;

REVERT;


-- 3. usr_liquidador: SELECT/UPDATE (permitido) sobre Inmuebles
EXECUTE AS USER = 'usr_liquidador';

    SELECT * FROM Catastro.Inmuebles WHERE codigo_catastral LIKE 'AUD-INM-%';

    UPDATE Catastro.Inmuebles
    SET avaluo_catastral = avaluo_catastral * 1.05
    WHERE codigo_catastral LIKE 'AUD-INM-%';

    BEGIN TRY
        DELETE FROM Catastro.Inmuebles WHERE codigo_catastral = 'AUD-INM-001';
    END TRY
    BEGIN CATCH
        PRINT 'usr_liquidador: DELETE denegado (esperado)';
    END CATCH;

REVERT;

-- 4. usr_fiscalizador solo SELECT (permitido) escritura (denegado)
EXECUTE AS USER = 'usr_fiscalizador';

    SELECT * FROM Catastro.Inmuebles WHERE codigo_catastral LIKE 'AUD-INM-%';
    SELECT * FROM Recaudaciones.LiquidacionesTributarias;

    BEGIN TRY
        UPDATE Catastro.Inmuebles SET avaluo_catastral = 1 WHERE codigo_catastral = 'AUD-INM-002';
    END TRY
    BEGIN CATCH
        PRINT 'usr_fiscalizador: UPDATE denegado ';
    END CATCH;

REVERT;


-- tiempo de espera 
WAITFOR DELAY '00:00:03';

-- 5. Consultar auditoria: operaciones capturadas por usuario
SELECT
    event_time,
    database_principal_name AS usuario,
    CASE action_id
        WHEN 'IN' THEN 'INSERT'
        WHEN 'SL' THEN 'SELECT'
        WHEN 'UP' THEN 'UPDATE'
        WHEN 'DL' THEN 'DELETE'
        ELSE action_id
    END AS accion,
    succeeded,
    schema_name,
    object_name,
    statement
FROM sys.fn_get_audit_file('/ProyectoABD/audit/*.sqlaudit', DEFAULT, DEFAULT)    -- ruta de tu archivo  ej C:/ProyectoABD/audit
WHERE database_principal_name IN ('usr_cajero', 'usr_liquidador', 'usr_fiscalizador')
ORDER BY event_time DESC;

-- 6. Conteo por usuario 
SELECT
    database_principal_name AS usuario,
    COUNT(*) AS eventos_capturados
FROM sys.fn_get_audit_file('/ProyectoABD/audit/*.sqlaudit', DEFAULT, DEFAULT)  -- ruta de tu archivo  ej C:/ProyectoABD/audit
WHERE database_principal_name IN ('usr_cajero', 'usr_liquidador', 'usr_fiscalizador')
GROUP BY database_principal_name;


-- 7. Limpieza (como admin)
DELETE FROM Recaudaciones.CobrosVentanilla WHERE numero_comprobante = 'AUD-COM-001';
DELETE FROM Recaudaciones.LiquidacionesTributarias WHERE id_contribuyente IN
    (SELECT id_contribuyente FROM Catastro.Contribuyentes WHERE ci_nit IN ('AUD-001','AUD-002','AUD-003'));
DELETE FROM Catastro.Inmuebles WHERE codigo_catastral LIKE 'AUD-INM-%';
DELETE FROM Catastro.Contribuyentes WHERE ci_nit IN ('AUD-001', 'AUD-002', 'AUD-003');

--  resumen - total de eventos por usuario
SELECT
    database_principal_name AS usuario,
    COUNT(*) AS eventos_capturados
FROM sys.fn_get_audit_file('/ProyectoABD/audit/*.sqlaudit', DEFAULT, DEFAULT)  -- ruta de tu archivo  ej C:/ProyectoABD/audit
WHERE database_principal_name IN ('usr_cajero', 'usr_liquidador', 'usr_fiscalizador')
GROUP BY database_principal_name
ORDER BY usuario;