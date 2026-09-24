-- ============================================================
-- VERSIONE WEB di 02_import_batch.sql (generata da giacenza/sql/02_import_batch.sql)
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
-- 02_import_batch.sql
-- Importa e pulisce l'export "Batch Details" di Zoho (01_Batch.csv)
-- come faceva prog/clean/batch_clean.py.
--
-- Prerequisito: tabelle create con 00_schema.sql
--               riferimenti caricati con 01_import_riferimenti.sql (alias)
--
-- Uso normale:   lanciato da run_all.sql (che imposta input_dir)
-- Uso da solo:   \i C:/Users/adeim/projects/giacenza/sql/02_import_batch.sql
--                (usa la cartella predefinita qui sotto)
--
-- Rilanciabile: svuota e ricarica staging e import_batch_clean.
-- Il cleaning_log invece NON si svuota: accumula i casi nel tempo.
-- Se un passo da' errore lo script si ferma e annulla tutto.
-- ============================================================

-- Cartella di input: se non l'ha gia' impostata run_all.sql, usa questa

-- Controllo: gli alias devono essere gia' caricati (01_import_riferimenti.sql)

-- ------------------------------------------------------------
-- A. STAGING: CSV grezzo
-- ------------------------------------------------------------

-- Separatore ; . HEADER salta il blocco titolo di Zoho (5 righe tra virgolette).
-- ENCODING 'UTF8': i CSV sono UTF-8 (psql su Windows altrimenti li legge come WIN1252)
-- ATTENZIONE: \copy deve restare su una sola riga, senza commenti sulla stessa riga

-- Toglie la riga d'intestazione vera e la riga vuota finale
DELETE FROM import_batch_full
WHERE item_id = 'item_id'
   OR item_id IS NULL;

-- ------------------------------------------------------------
-- B. TABELLA FINALE import_batch_clean
-- ------------------------------------------------------------

-- Passo 0: svuota e toglie la chiave primaria
--          (le pulizie del LOT creano doppioni temporanei)
TRUNCATE import_batch_clean;
ALTER TABLE import_batch_clean DROP CONSTRAINT IF EXISTS import_batch_clean_pkey;

-- Copia dalla staging. sku_orig e lot_orig conservano i valori del file,
-- sku e lot verranno puliti dai passi successivi. wh prende 'ALS' dal DEFAULT.
INSERT INTO import_batch_clean (sku, lot, qty_zoho_onhand, sku_orig, lot_orig)
SELECT sku, batch_number, balance_quantity::numeric, sku, batch_number
FROM import_batch_full;

-- Passo 1: SKU senza spazi ai lati, maiuscolo
UPDATE import_batch_clean
SET sku = upper(trim(sku));

-- Passo 1b: ALIAS - SKU Zoho -> SKU canonico (es. 402E -> 402), da ref_sku_alias.
--          sku_orig conserva il codice Zoho; il cambio finisce nel cleaning_log
--          insieme alle altre pulizie dello SKU.
UPDATE import_batch_clean t
SET sku = a.sku_canonico
FROM ref_sku_alias a
WHERE t.sku = a.zoho_sku;

-- Passo 2: LOT senza spazi ai lati, maiuscolo
UPDATE import_batch_clean
SET lot = upper(trim(lot));

-- Passo 3: LOT senza prefisso "LOT." "LOT#" "LOT "
UPDATE import_batch_clean
SET lot = regexp_replace(lot, '^LOT[.#\s]+', '')
WHERE lot ~ '^LOT[.#\s]+';

-- Passo 4: LOT senza suffisso " MAN ..." (data di produzione)
UPDATE import_batch_clean
SET lot = trim(regexp_replace(lot, '\s+MAN\s+.*$', ''))
WHERE lot ~ '\s+MAN\s+';

-- Passo 5: LOT senza "-" e "_"  ('g' = tutte le occorrenze, non solo la prima)
UPDATE import_batch_clean
SET lot = regexp_replace(lot, '[-_]', '', 'g')
WHERE lot ~ '[-_]';

-- Passo 6: scarta righe senza SKU/LOT o righe di totale
DELETE FROM import_batch_clean
WHERE sku = '' OR lot = ''
   OR sku ILIKE '%total%' OR lot ILIKE '%total%';

-- ------------------------------------------------------------
-- Passo 6b: CLEANING_LOG (prima di accorpare, finche' ogni riga
--           ha ancora il suo valore originale)
--   ON CONFLICT: se il caso e' gia' noto aggiorna last_seen;
--   times_seen sale solo se e' un giorno nuovo (rilanciare lo
--   script piu' volte nello stesso giorno non gonfia il conteggio)
-- ------------------------------------------------------------

-- LOT modificati dalla pulizia
INSERT INTO cleaning_log AS c (source, field, sku, value_orig, value_clean)
SELECT DISTINCT 'batch', 'lot', sku, lot_orig, lot
FROM import_batch_clean
WHERE lot_orig IS DISTINCT FROM lot
ON CONFLICT (source, field, sku, value_orig) DO UPDATE
SET value_clean = EXCLUDED.value_clean,
    times_seen  = c.times_seen + CASE WHEN c.last_seen < current_date THEN 1 ELSE 0 END,
    last_seen   = current_date;

-- SKU modificati dalla pulizia
INSERT INTO cleaning_log AS c (source, field, sku, value_orig, value_clean)
SELECT DISTINCT 'batch', 'sku', sku, sku_orig, sku
FROM import_batch_clean
WHERE sku_orig IS DISTINCT FROM sku
ON CONFLICT (source, field, sku, value_orig) DO UPDATE
SET value_clean = EXCLUDED.value_clean,
    times_seen  = c.times_seen + CASE WHEN c.last_seen < current_date THEN 1 ELSE 0 END,
    last_seen   = current_date;

-- Doppioni che il passo 7 sta per accorpare (value_orig = varianti originali)
INSERT INTO cleaning_log AS c (source, field, sku, value_orig, value_clean)
SELECT 'batch', 'doppione', sku, string_agg(lot_orig, ' | ' ORDER BY lot_orig), lot
FROM import_batch_clean
GROUP BY sku, lot, wh
HAVING count(*) > 1
ON CONFLICT (source, field, sku, value_orig) DO UPDATE
SET value_clean = EXCLUDED.value_clean,
    times_seen  = c.times_seen + CASE WHEN c.last_seen < current_date THEN 1 ELSE 0 END,
    last_seen   = current_date;

-- Passo 7: accorpa i doppioni (stesso sku + lot + wh) sommando le quantita'.
--          sku_orig / lot_orig conservano tutte le varianti, separate da " | "
--          DELETE ... RETURNING passa le righe cancellate all'INSERT: un solo comando
WITH vecchie AS (
  DELETE FROM import_batch_clean
  RETURNING *
)
INSERT INTO import_batch_clean (sku, lot, wh, qty_zoho_onhand, sku_orig, lot_orig)
SELECT sku, lot, wh,
       SUM(qty_zoho_onhand),
       string_agg(DISTINCT sku_orig, ' | '),
       string_agg(DISTINCT lot_orig, ' | ')
FROM vecchie
GROUP BY sku, lot, wh;

-- Passo 9: rimette la chiave primaria (fallisce se restano doppioni)
ALTER TABLE import_batch_clean
  ADD CONSTRAINT import_batch_clean_pkey PRIMARY KEY (sku, lot, wh);

-- ------------------------------------------------------------
-- C. CONTROLLI
-- ------------------------------------------------------------
SELECT
  (SELECT count(*) FROM import_batch_full)                       AS righe_staging,
  (SELECT count(*) FROM import_batch_clean)                            AS righe_finali,
  (SELECT SUM(balance_quantity::numeric) FROM import_batch_full) AS totale_staging,
  (SELECT SUM(qty_zoho_onhand) FROM import_batch_clean)                AS totale_finale;

SELECT field,
       count(*) FILTER (WHERE last_seen  = current_date) AS visti_oggi,
       count(*) FILTER (WHERE first_seen = current_date) AS nuovi_oggi
FROM cleaning_log
WHERE source = 'batch'
GROUP BY field
ORDER BY field;
