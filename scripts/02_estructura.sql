/* ============================================================
   01_Estructura_Municipal.sql
   Proyecto: BD_GOBIERNO_MUNICIPAL
   Responsable: Integrante 1 - Arquitecto de BD y Modelado de Datos
   Motor: Microsoft SQL Server (Developer Edition)

   Contenido:
   1. Creación de la base de datos con separación física de archivos
   2. Filegroup dedicado para tablas de alto crecimiento transaccional
   3. Esquemas Catastro y Recaudaciones
   4. Tablas principales con PK, FK y CHECK constraints
   5. Índices de soporte para el Job de mantenimiento (Integrante 2)
   ============================================================ */

USE master;

-- ------------------------------------------------------------
-- 0. Limpieza para entorno de laboratorio (recrear desde cero)
-- ------------------------------------------------------------
IF DB_ID('BD_GOBIERNO_MUNICIPAL') IS NOT NULL
BEGIN
    ALTER DATABASE BD_GOBIERNO_MUNICIPAL SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE BD_GOBIERNO_MUNICIPAL;
END

-- ------------------------------------------------------------
-- 1. Creación de la base de datos
--    Separación física: datos, log y un filegroup adicional
--    (FG_TRANSACCIONAL) para las tablas que más crecen
--    (Liquidaciones y Cobros), evitando que saturen el archivo
--    principal durante los periodos de descuento tributario.
--
--    AJUSTA las rutas de FILENAME según el disco de tu equipo.
-- ------------------------------------------------------------
CREATE DATABASE BD_GOBIERNO_MUNICIPAL
ON PRIMARY
(
    NAME = N'BD_GOBIERNO_MUNICIPAL_Data',
    FILENAME = N'C:\SQLData\BD_GOBIERNO_MUNICIPAL.mdf',
    SIZE = 256MB,
    FILEGROWTH = 64MB
),
FILEGROUP FG_TRANSACCIONAL
(
    NAME = N'BD_GOBIERNO_MUNICIPAL_Transaccional',
    FILENAME = N'C:\SQLData\BD_GOBIERNO_MUNICIPAL_Transaccional.ndf',
    SIZE = 512MB,
    FILEGROWTH = 128MB
)
LOG ON
(
    NAME = N'BD_GOBIERNO_MUNICIPAL_Log',
    FILENAME = N'C:\SQLLogs\BD_GOBIERNO_MUNICIPAL.ldf',
    SIZE = 128MB,
    FILEGROWTH = 64MB
);

ALTER DATABASE BD_GOBIERNO_MUNICIPAL SET RECOVERY FULL;
-- RECOVERY FULL es obligatorio: sin esto, Integrante 3 no puede
-- hacer backups de Log (.trn) para la cadena de contingencia.

USE BD_GOBIERNO_MUNICIPAL;

-- ------------------------------------------------------------
-- 2. Esquemas
-- ------------------------------------------------------------
CREATE SCHEMA Catastro AUTHORIZATION dbo;
CREATE SCHEMA Recaudaciones AUTHORIZATION dbo;

-- ------------------------------------------------------------
-- 3. Tablas del esquema CATASTRO
-- ------------------------------------------------------------
CREATE TABLE Catastro.Contribuyentes (
    id_contribuyente     INT IDENTITY(1,1) PRIMARY KEY,
    ci_nit               VARCHAR(20)  NOT NULL UNIQUE,
    nombres_razon_social VARCHAR(150) NOT NULL,
    tipo_persona         CHAR(1)      CHECK (tipo_persona IN ('N', 'J')), -- Natural o Jurídica
    telefono             VARCHAR(20),
    email                VARCHAR(100),
    direccion_fiscal     VARCHAR(200) NOT NULL,
    fecha_registro       DATETIME     DEFAULT GETDATE(),
    estado               VARCHAR(15)  DEFAULT 'Activo'
                          CHECK (estado IN ('Activo', 'Inactivo', 'Observado'))
);

CREATE TABLE Catastro.Inmuebles (
    id_inmueble        INT IDENTITY(1,1) PRIMARY KEY,
    codigo_catastral    VARCHAR(30) NOT NULL UNIQUE,
    id_contribuyente    INT NOT NULL
                         FOREIGN KEY REFERENCES Catastro.Contribuyentes(id_contribuyente),
    distrito_urbano     INT NOT NULL CHECK (distrito_urbano BETWEEN 1 AND 15),
    superficie_m2       DECIMAL(10,2) NOT NULL CHECK (superficie_m2 > 0),
    avaluo_catastral    DECIMAL(14,2) NOT NULL CHECK (avaluo_catastral >= 0),
    tipo_propiedad      VARCHAR(30) DEFAULT 'Residencial'
                         CHECK (tipo_propiedad IN ('Residencial', 'Comercial', 'Industrial', 'Terreno_Baldio')),
    direccion_predio    VARCHAR(200) NOT NULL
);

-- ------------------------------------------------------------
-- 4. Tablas del esquema RECAUDACIONES
--    Liquidaciones y Cobros van en FG_TRANSACCIONAL: son las
--    que reciben carga masiva y crecen más rápido.
-- ------------------------------------------------------------
CREATE TABLE Recaudaciones.PatentesComerciales (
    id_patente          INT IDENTITY(1,1) PRIMARY KEY,
    numero_licencia     VARCHAR(25) NOT NULL UNIQUE,
    id_contribuyente    INT NOT NULL
                         FOREIGN KEY REFERENCES Catastro.Contribuyentes(id_contribuyente),
    actividad_economica VARCHAR(120) NOT NULL,
    categoria           VARCHAR(30) NOT NULL,
    monto_anual         DECIMAL(10,2) NOT NULL CHECK (monto_anual > 0),
    estado_licencia     VARCHAR(20) DEFAULT 'Vigente'
                         CHECK (estado_licencia IN ('Vigente', 'Suspendida', 'Clausurada'))
);

CREATE TABLE Recaudaciones.LiquidacionesTributarias (
    id_liquidacion      BIGINT IDENTITY(1,1) PRIMARY KEY,
    id_contribuyente    INT NOT NULL
                         FOREIGN KEY REFERENCES Catastro.Contribuyentes(id_contribuyente),
    concepto_tributario VARCHAR(50) NOT NULL
                         CHECK (concepto_tributario IN ('Impuesto_Inmueble', 'Patente_Comercial', 'Tasa_Aseo')),
    gestion_fiscal      INT NOT NULL CHECK (gestion_fiscal BETWEEN 2000 AND 2050),
    monto_determinado   DECIMAL(12,2) NOT NULL CHECK (monto_determinado >= 0),
    multas_intereses    DECIMAL(10,2) DEFAULT 0.00,
    monto_total         DECIMAL(12,2) NOT NULL,
    fecha_emision       DATETIME DEFAULT GETDATE(),
    estado_pago         VARCHAR(20) DEFAULT 'Pendiente'
                         CHECK (estado_pago IN ('Pendiente', 'Pagado', 'Prescrito', 'En_Mora'))
) ON FG_TRANSACCIONAL;

CREATE TABLE Recaudaciones.CobrosVentanilla (
    id_cobro            BIGINT IDENTITY(1,1) PRIMARY KEY,
    id_liquidacion      BIGINT NOT NULL
                         FOREIGN KEY REFERENCES Recaudaciones.LiquidacionesTributarias(id_liquidacion),
    numero_comprobante  VARCHAR(30) NOT NULL UNIQUE,
    monto_cobrado       DECIMAL(12,2) NOT NULL CHECK (monto_cobrado > 0),
    fecha_cobro         DATETIME DEFAULT GETDATE(),
    cajero_ventanilla   VARCHAR(50) NOT NULL,
    metodo_pago         VARCHAR(30) DEFAULT 'Efectivo'
                         CHECK (metodo_pago IN ('Efectivo', 'QR_Interbancario', 'Tarjeta_Debito'))
) ON FG_TRANSACCIONAL;

-- ------------------------------------------------------------
-- 5. Índices de soporte
--    Estos nombres están definidos en la guía: el Job de
--    mantenimiento de Integrante 2 los va a monitorear por
--    fragmentación, así que deben existir con este nombre exacto.
-- ------------------------------------------------------------
CREATE INDEX IX_Liquidaciones_Contribuyente_Estado
    ON Recaudaciones.LiquidacionesTributarias (id_contribuyente, estado_pago);

CREATE INDEX IX_Inmuebles_Distrito
    ON Catastro.Inmuebles (distrito_urbano);

-- ------------------------------------------------------------
-- 6. Verificación rápida
-- ------------------------------------------------------------
SELECT s.name AS esquema, t.name AS tabla
FROM sys.tables t
JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE s.name IN ('Catastro', 'Recaudaciones')
ORDER BY s.name, t.name;

/* ============================================================
   03_Procedimientos_Carga_Masiva.sql (Solución con Staging Table)
   Proyecto: BD_GOBIERNO_MUNICIPAL
   Responsable: Integrante 2 - Especialista en Migración y Rendimiento
   ============================================================ */

USE BD_GOBIERNO_MUNICIPAL;


-- 1. Limpiar dependencias previas si vas a reintentar la carga
DELETE FROM Recaudaciones.CobrosVentanilla;
DELETE FROM Recaudaciones.LiquidacionesTributarias;
DELETE FROM Recaudaciones.PatentesComerciales;
DELETE FROM Catastro.Inmuebles;
DELETE FROM Catastro.Contribuyentes;


-- 2. Activar estadísticas para medir rendimiento y tiempos (Requerido para el informe §5.2)
SET STATISTICS TIME ON;
SET STATISTICS IO ON;


-- 3. Crear una tabla temporal (staging) con las 7 columnas exactas del CSV
CREATE TABLE #StagingContribuyentes (
    ci_nit               VARCHAR(20)  NOT NULL,
    nombres_razon_social VARCHAR(150) NOT NULL,
    tipo_persona         CHAR(1)      NOT NULL,
    telefono             VARCHAR(20),
    email                VARCHAR(100),
    direccion_fiscal     VARCHAR(200) NOT NULL,
    estado               VARCHAR(15)  NOT NULL
);


-- 4. Ejecutar el BULK INSERT hacia la tabla temporal (sin conflictos de IDENTITY)
BULK INSERT #StagingContribuyentes
FROM 'C:\xampp\htdocs\ProyectoBD\data\padron_contribuyentes.csv'
WITH (
    DATAFILETYPE = 'char',
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2,           -- Salta la cabecera del archivo CSV
    TABLOCK                 -- Optimización de bloqueo de tabla
);


-- 5. Migrar los datos desde la tabla temporal hacia la tabla oficial de la BD
INSERT INTO Catastro.Contribuyentes (
    ci_nit,
    nombres_razon_social,
    tipo_persona,
    telefono,
    email,
    direccion_fiscal,
    estado
)
SELECT 
    ci_nit,
    nombres_razon_social,
    tipo_persona,
    telefono,
    email,
    direccion_fiscal,
    estado
FROM #StagingContribuyentes;


-- 6. Limpiar y eliminar la tabla temporal
DROP TABLE #StagingContribuyentes;


-- 7. Desactivar estadísticas
SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;


-- 8. Verificación de éxito
SELECT COUNT(*) AS TotalContribuyentesCargados 
FROM Catastro.Contribuyentes;

SELECT TOP 5 * FROM Catastro.Contribuyentes;

/* ============================================================
   04_Jobs_Mantenimiento_Agente.sql (Con limpieza de cursor)
   Proyecto: BD_GOBIERNO_MUNICIPAL
   Responsable: Integrante 2 - Especialista en Migración y Rendimiento
   ============================================================ */

USE BD_GOBIERNO_MUNICIPAL;


-- ============================================================
-- 1. Script de Mantenimiento de Índices por Fragmentación
-- ============================================================

-- Línea de seguridad: Si el cursor ya existe de una ejecución anterior, lo borramos de memoria
IF CURSOR_STATUS('global', 'CursorIndices') >= -1
BEGIN
    DEALLOCATE CursorIndices;
END

DECLARE @NombreTabla NVARCHAR(128);
DECLARE @NombreIndice NVARCHAR(128);
DECLARE @Fragmentacion FLOAT;
DECLARE @SqlStmt NVARCHAR(MAX);

DECLARE CursorIndices CURSOR FOR
SELECT 
    OBJECT_NAME(s.object_id) AS Tabla,
    i.name AS Indice,
    s.avg_fragmentation_in_percent AS Fragmentacion
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') s
INNER JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE s.avg_fragmentation_in_percent > 10.0 
  AND s.index_id > 0;

OPEN CursorIndices;
FETCH NEXT FROM CursorIndices INTO @NombreTabla, @NombreIndice, @Fragmentacion;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF @Fragmentacion >= 10.0 AND @Fragmentacion < 30.0
    BEGIN
        SET @SqlStmt = N'ALTER INDEX ' + QUOTENAME(@NombreIndice) + 
                       N' ON Catastro.' + QUOTENAME(@NombreTabla) + N' REORGANIZE;';
        EXEC sp_executesql @SqlStmt;
    end
    ELSE IF @Fragmentacion >= 30.0
    BEGIN
        SET @SqlStmt = N'ALTER INDEX ' + QUOTENAME(@NombreIndice) + 
                       N' ON Catastro.' + QUOTENAME(@NombreTabla) + N' REBUILD;';
        EXEC sp_executesql @SqlStmt;
    END

    FETCH NEXT FROM CursorIndices INTO @NombreTabla, @NombreIndice, @Fragmentacion;
END

CLOSE CursorIndices;
DEALLOCATE CursorIndices;


-- ============================================================
-- 2. Verificación de Integridad de la Base de Datos
-- ============================================================
DBCC CHECKDB ('BD_GOBIERNO_MUNICIPAL') WITH NO_INFOMSGS;

