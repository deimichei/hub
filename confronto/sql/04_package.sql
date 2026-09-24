-- ============================================================
-- VERSIONE WEB di 04_import_package.sql (generata da giacenza/sql/04_import_package.sql)
-- Differenze rispetto alla versione psql:
--   * niente comandi psql (\copy, \echo, \if, \set, \c ...)
--   * niente BEGIN/COMMIT: la transazione unica la apre Django
--   * niente TRUNCATE delle tabelle di caricamento: il caricamento
--     dei file (xlsx/csv) lo fa Python PRIMA di questo script
--   * search_path = giacenza lo imposta Django: le tabelle stanno
--     nello schema "giacenza" del database "hub"
-- La logica (pulizia, confronto) e' IDENTICA alla versione psql.
-- ============================================================

-- ============================================================
-- 04_import_package.sql
-- Importa e pulisce l'export Package di Zoho (03_Package.csv)
-- come faceva prog/clean/package_clean.py.
--
-- Risultato: import_package_clean = righe dei pacchi APERTI
-- (non ancora consegnati): merce uscita da Zoho ma non ancora
-- dal magazzino fisico. Nel confronto (10_confronto.sql) si
-- collegano a import_sales_order_clean tramite so_number per
-- sapere se sono del magazzino ALS.
--
-- Prerequisito: tabelle create con 00_schema.sql
--               riferimenti caricati con 01_import_riferimenti.sql (alias)
--
-- Uso normale:   lanciato da run_all.sql (che imposta input_dir)
-- Uso da solo:   \i C:/Users/adeim/projects/giacenza/sql/04_import_package.sql
--
-- Rilanciabile: svuota e ricarica staging e tabella pulita.
-- Il cleaning_log invece NON si svuota: accumula i casi nel tempo.
-- Se un passo da' errore lo script si ferma e annulla tutto.
-- ============================================================

-- Cartella di input: se non l'ha gia' impostata run_all.sql, usa questa

-- Controllo: gli alias devono essere gia' caricati (01_import_riferimenti.sql)

-- ------------------------------------------------------------
-- A. STAGING: CSV grezzo (47 colonne, intestazione alla riga 1)
--    I campi vuoti vengono caricati come NULL.
-- ------------------------------------------------------------

-- ENCODING 'UTF8': i CSV sono UTF-8 (psql su Windows altrimenti li legge come WIN1252)
-- ATTENZIONE: \copy deve restare su una sola riga, senza commenti sulla stessa riga

-- ------------------------------------------------------------
-- B. TABELLA PULITA import_package_clean
-- ------------------------------------------------------------

-- Passo 0: svuota; RESTART IDENTITY fa ripartire il contatore id da 1
TRUNCATE import_package_clean RESTART IDENTITY;

-- Passi 1-4 del Python in un solo INSERT:
--   1-2. tiene e rinomina 5 colonne (status serve solo al filtro)
--   3.   scarta i pacchi "delivered" (stato normalizzato: minuscolo, senza spazi)
--   4.   scarta le righe senza lotto (Batch Reference# vuoto = NULL)
-- sku_orig e lot_orig conservano i valori del file per il cleaning_log.
-- Differenza voluta dal Python: una quantita' non numerica fa fermare lo
-- script con un errore invece di diventare 0 in silenzio.
INSERT INTO import_package_clean (so_number, sku, lot, qty_open, sku_orig, lot_orig)
SELECT so_number, sku, batch_reference, quantity_out::numeric, sku, batch_reference
FROM import_package_full
WHERE lower(trim(status)) <> 'delivered'
  AND batch_reference IS NOT NULL;

-- Passo 5: pulizia SKU e LOT, stesse regole del Batch (utils.norm_sku / norm_lot)
UPDATE import_package_clean
SET sku = upper(trim(sku));

-- Passo 5a-bis: ALIAS - SKU Zoho -> SKU canonico (es. 402E -> 402), da ref_sku_alias.
--          sku_orig conserva il codice Zoho; il cambio finisce nel cleaning_log
--          insieme alle altre pulizie dello SKU.
UPDATE import_package_clean t
SET sku = a.sku_canonico
FROM ref_sku_alias a
WHERE t.sku = a.zoho_sku;

UPDATE import_package_clean
SET lot = upper(trim(lot));

UPDATE import_package_clean
SET lot = regexp_replace(lot, '^LOT[.#\s]+', '')
WHERE lot ~ '^LOT[.#\s]+';

UPDATE import_package_clean
SET lot = trim(regexp_replace(lot, '\s+MAN\s+.*$', ''))
WHERE lot ~ '\s+MAN\s+';

-- 'g' = tutte le occorrenze, non solo la prima
UPDATE import_package_clean
SET lot = regexp_replace(lot, '[-_]', '', 'g')
WHERE lot ~ '[-_]';

-- ------------------------------------------------------------
-- Passo 6: CLEANING_LOG
--   ON CONFLICT: se il caso e' gia' noto aggiorna last_seen;
--   times_seen sale solo se e' un giorno nuovo.
--   Niente righe "doppione": il Package non accorpa.
-- ------------------------------------------------------------

-- LOT modificati dalla pulizia
INSERT INTO cleaning_log AS c (source, field, sku, value_orig, value_clean)
SELECT DISTINCT 'package', 'lot', sku, lot_orig, lot
FROM import_package_clean
WHERE lot_orig IS DISTINCT FROM lot
ON CONFLICT (source, field, sku, value_orig) DO UPDATE
SET value_clean = EXCLUDED.value_clean,
    times_seen  = c.times_seen + CASE WHEN c.last_seen < current_date THEN 1 ELSE 0 END,
    last_seen   = current_date;

-- SKU modificati dalla pulizia
INSERT INTO cleaning_log AS c (source, field, sku, value_orig, value_clean)
SELECT DISTINCT 'package', 'sku', sku, sku_orig, sku
FROM import_package_clean
WHERE sku_orig IS DISTINCT FROM sku
ON CONFLICT (source, field, sku, value_orig) DO UPDATE
SET value_clean = EXCLUDED.value_clean,
    times_seen  = c.times_seen + CASE WHEN c.last_seen < current_date THEN 1 ELSE 0 END,
    last_seen   = current_date;

-- ------------------------------------------------------------
-- C. CONTROLLI
-- ------------------------------------------------------------
SELECT status,
       count(*)                                        AS righe,
       count(*) FILTER (WHERE batch_reference IS NULL) AS senza_lotto
FROM import_package_full
GROUP BY status
ORDER BY righe DESC;

SELECT count(*)                  AS righe,
       count(DISTINCT so_number) AS ordini,
       SUM(qty_open)             AS qty_totale
FROM import_package_clean;

SELECT field,
       count(*) FILTER (WHERE last_seen  = current_date) AS visti_oggi,
       count(*) FILTER (WHERE first_seen = current_date) AS nuovi_oggi
FROM cleaning_log
WHERE source = 'package'
GROUP BY field
ORDER BY field;
