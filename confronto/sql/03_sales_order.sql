-- ============================================================
-- VERSIONE WEB di 03_import_sales_order.sql (generata da giacenza/sql/03_import_sales_order.sql)
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
-- 03_import_sales_order.sql
-- Importa e pulisce l'export Sales Order di Zoho (02_Sales_Order.csv)
-- come faceva prog/clean/sales_order_clean.py.
--
-- Risultato: import_sales_order_clean = elenco degli ordini (SO)
-- che partono dal magazzino ALS. Serve al confronto per sapere
-- quali pacchi (Package) sono del 3PL.
--
-- Prerequisito: tabelle create con 00_schema.sql
--
-- Uso normale:   lanciato da run_all.sql (che imposta input_dir)
-- Uso da solo:   \i C:/Users/adeim/projects/giacenza/sql/03_import_sales_order.sql
--
-- Rilanciabile: svuota e ricarica staging e tabella pulita.
-- Nessuna voce nel cleaning_log: qui non si correggono valori,
-- si filtra soltanto.
-- ============================================================

-- Cartella di input: se non l'ha gia' impostata run_all.sql, usa questa

-- ------------------------------------------------------------
-- A. STAGING: CSV grezzo (87 colonne, intestazione alla riga 1)
-- ------------------------------------------------------------

-- ENCODING 'UTF8': i CSV sono UTF-8 (psql su Windows altrimenti li legge come WIN1252)
-- ATTENZIONE: \copy deve restare su una sola riga, senza commenti sulla stessa riga

-- ------------------------------------------------------------
-- B. TABELLA PULITA import_sales_order_clean
--    Un solo INSERT fa i 5 passi dello schema di sales_order_clean.py:
--    1. tiene 2 colonne          -> salesorder_number, line_item_location_name
--    2. rinomina                 -> so_number, wh
--    3. filtra il magazzino ALS  -> WHERE line_item_location_name = 'ALS Swiss SA'
--       (NON "location_name": vale sempre 'ALS Swiss SA', e' la sede
--        dell'ordine, non il magazzino da cui parte la riga)
--    4. 'ALS Swiss SA' -> 'ALS'  -> valore fisso, come nel Batch
--    5. toglie i duplicati       -> DISTINCT (un ordine ha piu' righe)
-- ------------------------------------------------------------
TRUNCATE import_sales_order_clean;

INSERT INTO import_sales_order_clean (so_number, wh)
SELECT DISTINCT salesorder_number, 'ALS'
FROM import_sales_order_full
WHERE line_item_location_name = 'ALS Swiss SA';

-- ------------------------------------------------------------
-- C. CONTROLLI
-- ------------------------------------------------------------
SELECT line_item_location_name,
       count(*)                          AS righe,
       count(DISTINCT salesorder_number) AS ordini
FROM import_sales_order_full
GROUP BY line_item_location_name
ORDER BY righe DESC;

SELECT count(*) AS ordini_als FROM import_sales_order_clean;
