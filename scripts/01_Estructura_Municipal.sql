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
GO

-- ------------------------------------------------------------
-- 0. Limpieza para entorno de laboratorio (recrear desde cero)
-- ------------------------------------------------------------
IF DB_ID('BD_GOBIERNO_MUNICIPAL') IS NOT NULL
BEGIN
    ALTER DATABASE BD_GOBIERNO_MUNICIPAL SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE BD_GOBIERNO_MUNICIPAL;
END
GO

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
GO

ALTER DATABASE BD_GOBIERNO_MUNICIPAL SET RECOVERY FULL;
-- RECOVERY FULL es obligatorio: sin esto, Integrante 3 no puede
-- hacer backups de Log (.trn) para la cadena de contingencia.
GO

USE BD_GOBIERNO_MUNICIPAL;
GO

-- ------------------------------------------------------------
-- 2. Esquemas
-- ------------------------------------------------------------
CREATE SCHEMA Catastro AUTHORIZATION dbo;
GO
CREATE SCHEMA Recaudaciones AUTHORIZATION dbo;
GO

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
GO

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
GO

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
GO

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
GO

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
GO

-- ------------------------------------------------------------
-- 5. Índices de soporte
--    Estos nombres están definidos en la guía: el Job de
--    mantenimiento de Integrante 2 los va a monitorear por
--    fragmentación, así que deben existir con este nombre exacto.
-- ------------------------------------------------------------
CREATE INDEX IX_Liquidaciones_Contribuyente_Estado
    ON Recaudaciones.LiquidacionesTributarias (id_contribuyente, estado_pago);
GO

CREATE INDEX IX_Inmuebles_Distrito
    ON Catastro.Inmuebles (distrito_urbano);
GO

-- ------------------------------------------------------------
-- 6. Verificación rápida
-- ------------------------------------------------------------
SELECT s.name AS esquema, t.name AS tabla
FROM sys.tables t
JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE s.name IN ('Catastro', 'Recaudaciones')
ORDER BY s.name, t.name;
GO