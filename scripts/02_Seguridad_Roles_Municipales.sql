-- 02_Seguridad_Roles_Municipales 
USE master;

-- 1. Eliminar usuarios de BD primero (dependen de los logins)
USE BD_GOBIERNO_MUNICIPAL;

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'usr_cajero')
    DROP USER usr_cajero;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'usr_liquidador')
    DROP USER usr_liquidador;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'usr_fiscalizador')
    DROP USER usr_fiscalizador;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'usr_auditor')
    DROP USER usr_auditor;

-- 2. Eliminar y recrear los logins 

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_cajero')
    DROP LOGIN login_cajero;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_liquidador')
    DROP LOGIN login_liquidador;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_fiscalizador')
    DROP LOGIN login_fiscalizador;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_auditor')
    DROP LOGIN login_auditor;

CREATE LOGIN login_cajero
    WITH PASSWORD = 'PassSegura2026*!', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;

CREATE LOGIN login_liquidador
    WITH PASSWORD = 'PassSegura2026*!', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;

CREATE LOGIN login_fiscalizador
    WITH PASSWORD = 'PassSegura2026*!', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;

CREATE LOGIN login_auditor
    WITH PASSWORD = 'PassSegura2026*!', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;


-- Confirmar que quedaron habilitados
SELECT name, is_disabled, type_desc, default_database_name
FROM sys.server_principals
WHERE name IN ('login_cajero', 'login_liquidador', 'login_fiscalizador', 'login_auditor');

-- 3. Establecer BD_GOBIERNO_MUNICIPAL como base por defecto
--    (evita el error "explicitly specified database" si el
--    cliente no la indica, y facilita la conexion)
ALTER LOGIN login_cajero        WITH DEFAULT_DATABASE = BD_GOBIERNO_MUNICIPAL;
ALTER LOGIN login_liquidador    WITH DEFAULT_DATABASE = BD_GOBIERNO_MUNICIPAL;
ALTER LOGIN login_fiscalizador  WITH DEFAULT_DATABASE = BD_GOBIERNO_MUNICIPAL;
ALTER LOGIN login_auditor       WITH DEFAULT_DATABASE = BD_GOBIERNO_MUNICIPAL;


-- 4. Recrear los usuarios en la base, ya vinculados a los
--    logins recien creados 
USE BD_GOBIERNO_MUNICIPAL;

CREATE USER usr_cajero        FOR LOGIN login_cajero;
CREATE USER usr_liquidador    FOR LOGIN login_liquidador;
CREATE USER usr_fiscalizador  FOR LOGIN login_fiscalizador;
CREATE USER usr_auditor       FOR LOGIN login_auditor;

-- Verificacion de mapeo correcto los login_asociado NO deben salir NULL
SELECT dp.name AS usuario_bd, dp.type_desc, sp.name AS login_asociado
FROM sys.database_principals dp
LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
WHERE dp.name IN ('usr_cajero', 'usr_liquidador', 'usr_fiscalizador', 'usr_auditor');

-- 5. Roles 
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'Rol_Cajero_Municipal')
    DROP ROLE Rol_Cajero_Municipal;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'Rol_Liquidador_Catastral')
    DROP ROLE Rol_Liquidador_Catastral;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'Rol_Fiscalizador_Tributario')
    DROP ROLE Rol_Fiscalizador_Tributario;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'Rol_Auditor')
    DROP ROLE Rol_Auditor;

CREATE ROLE Rol_Cajero_Municipal;
CREATE ROLE Rol_Liquidador_Catastral;
CREATE ROLE Rol_Fiscalizador_Tributario;
CREATE ROLE Rol_Auditor;

-- Asignacion
ALTER ROLE Rol_Cajero_Municipal        ADD MEMBER usr_cajero;
ALTER ROLE Rol_Liquidador_Catastral    ADD MEMBER usr_liquidador;
ALTER ROLE Rol_Fiscalizador_Tributario ADD MEMBER usr_fiscalizador;
ALTER ROLE Rol_Auditor                 ADD MEMBER usr_auditor;

-- 6. Permisos 
-- CAJERO
GRANT SELECT ON Recaudaciones.LiquidacionesTributarias TO Rol_Cajero_Municipal;
GRANT INSERT ON Recaudaciones.CobrosVentanilla TO Rol_Cajero_Municipal;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Catastro TO Rol_Cajero_Municipal;
DENY UPDATE, DELETE ON Recaudaciones.CobrosVentanilla TO Rol_Cajero_Municipal;

-- LIQUIDADOR CATASTRAL
GRANT SELECT, INSERT, UPDATE ON Catastro.Contribuyentes TO Rol_Liquidador_Catastral;
GRANT SELECT, INSERT, UPDATE ON Catastro.Inmuebles TO Rol_Liquidador_Catastral;
GRANT SELECT ON Recaudaciones.PatentesComerciales TO Rol_Liquidador_Catastral;
GRANT SELECT, INSERT, UPDATE ON Recaudaciones.LiquidacionesTributarias TO Rol_Liquidador_Catastral;
DENY DELETE ON Catastro.Contribuyentes TO Rol_Liquidador_Catastral;
DENY DELETE ON Catastro.Inmuebles TO Rol_Liquidador_Catastral;
DENY DELETE ON Recaudaciones.LiquidacionesTributarias TO Rol_Liquidador_Catastral;

-- FISCALIZADOR TRIBUTARIO
GRANT SELECT ON Catastro.Contribuyentes TO Rol_Fiscalizador_Tributario;
GRANT SELECT ON Catastro.Inmuebles TO Rol_Fiscalizador_Tributario;
GRANT SELECT ON Recaudaciones.PatentesComerciales TO Rol_Fiscalizador_Tributario;
GRANT SELECT ON Recaudaciones.LiquidacionesTributarias TO Rol_Fiscalizador_Tributario;
GRANT SELECT ON Recaudaciones.CobrosVentanilla TO Rol_Fiscalizador_Tributario;

-- AUDITOR
GRANT SELECT ON Catastro.Contribuyentes TO Rol_Auditor;
GRANT SELECT ON Catastro.Inmuebles TO Rol_Auditor;
GRANT SELECT ON Recaudaciones.PatentesComerciales TO Rol_Auditor;
GRANT SELECT ON Recaudaciones.LiquidacionesTributarias TO Rol_Auditor;
GRANT SELECT ON Recaudaciones.CobrosVentanilla TO Rol_Auditor;

-- 7. Verificacion final: base ONLINE / MULTI_USER
SELECT name, state_desc, user_access_desc
FROM sys.databases
WHERE name = 'BD_GOBIERNO_MUNICIPAL';

-- Apartado de  pruebas no es necesario ejecutarlas 
USE master;
USE BD_GOBIERNO_MUNICIPAL;

-- PRUEBAS: usr_cajero
EXECUTE AS USER = 'usr_cajero';

    -- TC-01: Debe PERMITIR (GRANT SELECT explicito)
    SELECT * FROM Recaudaciones.LiquidacionesTributarias;

    -- TC-02: Debe PERMITIR (GRANT INSERT explicito)
    INSERT INTO Recaudaciones.CobrosVentanilla
        (id_liquidacion, numero_comprobante, monto_cobrado, cajero_ventanilla, metodo_pago)
    VALUES (1, 'COM-TEST-CAJ', 100.00, 'usr_cajero', 'Efectivo');

    -- TC-03: Debe DENEGAR (DENY explicito sobre CobrosVentanilla)
    UPDATE Recaudaciones.CobrosVentanilla SET monto_cobrado = 999 WHERE numero_comprobante = 'COM-TEST-CAJ';

    -- TC-04: Debe DENEGAR (DENY explicito sobre CobrosVentanilla)
    DELETE FROM Recaudaciones.CobrosVentanilla WHERE numero_comprobante = 'COM-TEST-CAJ';

    -- TC-05: Debe DENEGAR (DENY a nivel de todo el esquema Catastro)
    SELECT * FROM Catastro.Inmuebles;

    -- TC-06: Debe DENEGAR (DENY a nivel de todo el esquema Catastro)
    INSERT INTO Catastro.Contribuyentes (ci_nit, nombres_razon_social, tipo_persona, direccion_fiscal)
    VALUES ('TEST001', 'PRUEBA CAJERO', 'N', 'Direccion X');

REVERT;

-- PRUEBAS: usr_liquidador
EXECUTE AS USER = 'usr_liquidador';

    -- TC-07: Debe PERMITIR (GRANT SELECT, INSERT, UPDATE)
    SELECT * FROM Catastro.Contribuyentes;

    -- TC-08: Debe PERMITIR (GRANT INSERT)
    INSERT INTO Catastro.Contribuyentes (ci_nit, nombres_razon_social, tipo_persona, direccion_fiscal)
    VALUES ('TEST002', 'PRUEBA LIQUIDADOR', 'N', 'Direccion Y');

    -- TC-09: Debe PERMITIR (GRANT UPDATE)
    UPDATE Catastro.Contribuyentes SET telefono = '77777777' WHERE ci_nit = 'TEST002';

    -- TC-10: Debe DENEGAR (DENY explicito DELETE)
    DELETE FROM Catastro.Contribuyentes WHERE ci_nit = 'TEST002';

    -- TC-11: Debe PERMITIR (GRANT SELECT sobre Patentes)
    SELECT * FROM Recaudaciones.PatentesComerciales;

    -- TC-12: Debe DENEGAR (no tiene ningun permiso otorgado sobre esta tabla)
    INSERT INTO Recaudaciones.PatentesComerciales (numero_licencia, id_contribuyente, actividad_economica, categoria, monto_anual)
    VALUES ('LIC-TEST', 1, 'Prueba', 'A', 500);

    -- TC-13: Debe DENEGAR (no tiene ningun permiso otorgado sobre esta tabla)
    SELECT * FROM Recaudaciones.CobrosVentanilla;

REVERT;

-- PRUEBAS: usr_fiscalizador
EXECUTE AS USER = 'usr_fiscalizador';

    -- TC-14: Debe PERMITIR (GRANT SELECT)
    SELECT * FROM Catastro.Contribuyentes;

    -- TC-15: Debe PERMITIR (GRANT SELECT)
    SELECT * FROM Recaudaciones.LiquidacionesTributarias;

    -- TC-16: Debe PERMITIR (GRANT SELECT)
    SELECT * FROM Recaudaciones.CobrosVentanilla;

    -- TC-17: Debe DENEGAR (rol de solo lectura, sin GRANT de escritura)
    UPDATE Catastro.Contribuyentes SET telefono = '11111111' WHERE ci_nit = 'TEST002';

    -- TC-18: Debe DENEGAR (rol de solo lectura, sin GRANT de escritura)
    INSERT INTO Recaudaciones.CobrosVentanilla
        (id_liquidacion, numero_comprobante, monto_cobrado, cajero_ventanilla, metodo_pago)
    VALUES (1, 'COM-TEST-FISC', 50.00, 'usr_fiscalizador', 'Efectivo');

REVERT;

-- PRUEBAS: usr_auditor
EXECUTE AS USER = 'usr_auditor';

    -- TC-19: Debe PERMITIR (GRANT SELECT)
    SELECT * FROM Catastro.Inmuebles;

    -- TC-20: Debe PERMITIR (GRANT SELECT)
    SELECT * FROM Recaudaciones.PatentesComerciales;

    -- TC-21: Debe DENEGAR (rol de solo lectura, sin GRANT de escritura)
    DELETE FROM Recaudaciones.LiquidacionesTributarias WHERE id_liquidacion = 1;

    -- TC-22: Debe DENEGAR (rol de solo lectura, sin GRANT de escritura)
    UPDATE Catastro.Inmuebles SET avaluo_catastral = 0 WHERE id_inmueble = 1;

REVERT;

-- Limpieza de los datos de prueba ingresados (como admin)
DELETE FROM Recaudaciones.CobrosVentanilla WHERE numero_comprobante = 'COM-TEST-CAJ';
DELETE FROM Catastro.Contribuyentes WHERE ci_nit IN ('TEST001', 'TEST002');
