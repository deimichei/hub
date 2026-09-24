-- ============================================================
-- VERSIONE WEB di 10_confronto.sql (generata da giacenza/sql/10_confronto.sql)
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
-- 10_confronto.sql
-- Confronto tra la giacenza secondo Zoho e la giacenza fisica
-- del 3PL, come faceva prog/pipeline.py.
--
-- Idea: quando in Zoho si prepara un pacco, la merce esce subito
-- dall'inventario Zoho, ma fisicamente resta al 3PL finche' il pacco
-- non parte. Quindi:
--   quanto dovrebbe esserci al 3PL = inventario Zoho + pacchi aperti ALS
--
-- Tabelle prodotte (ricalcolate da zero a ogni giro):
--   out_1_pacchi_als          pacchi aperti il cui ordine e' del magazzino ALS
--   out_2_pacchi_non_als      pacchi aperti di altri magazzini (lista a parte)
--   out_3_zoho_e_pacchi_als   inventario Zoho + pacchi ALS, per SKU + LOT
--   out_4_confronto           Zoho contro 3PL: differenza (delta) e categoria
--   out_5_sku_dismessi        SKU di sku_old.csv, tolti dal confronto (lista a parte)
--
-- Prerequisito: import 01-05 gia' eseguiti
--   (lo SKU e' gia' canonico: l'alias 402E -> 402 si applica negli import)
--
-- Uso: \i C:/Users/adeim/projects/giacenza/sql/10_confronto.sql
--
-- Tutto o niente: se un passo da' errore lo script si ferma e annulla tutto.
-- ============================================================

-- Le tabelle out_* sono risultati calcolati: si cancellano e si rifanno.
-- CASCADE cancella anche le viste export_* che le leggono (create da
-- 20_export.sql): senza, Postgres rifiuterebbe il DROP. Le viste vengono
-- ricreate da 20_export.sql, quindi dopo questo script va lanciato anche quello.
DROP TABLE IF EXISTS out_1_pacchi_als, out_2_pacchi_non_als,
                     out_3_zoho_e_pacchi_als, out_4_confronto, out_5_sku_dismessi
  CASCADE;

-- ------------------------------------------------------------
-- Tabella 1: pacchi aperti del magazzino ALS
--   Package -> Sales Order su so_number (relazione N a 1).
--   JOIN normale: tiene solo i pacchi il cui ordine e' ALS.
-- ------------------------------------------------------------
CREATE TABLE out_1_pacchi_als AS
SELECT p.so_number, p.sku, p.lot, s.wh, p.qty_open
FROM import_package_clean p
JOIN import_sales_order_clean s ON s.so_number = p.so_number;

-- ------------------------------------------------------------
-- Tabella 2: pacchi aperti NON ALS (lista a parte, da controllare)
--   LEFT JOIN + "IS NULL" = righe che NON trovano corrispondenza.
--   Due casi possibili: ordine di un altro magazzino (scarto corretto)
--   oppure ordine assente dal Sales Order (da verificare).
-- ------------------------------------------------------------
CREATE TABLE out_2_pacchi_non_als AS
SELECT p.so_number, p.sku, p.lot, p.qty_open
FROM import_package_clean p
LEFT JOIN import_sales_order_clean s ON s.so_number = p.so_number
WHERE s.so_number IS NULL;

-- ------------------------------------------------------------
-- Tabella 3: inventario Zoho + pacchi aperti ALS
--   a) la sottoquery "k" SOMMA i pacchi per SKU + LOT + magazzino:
--      lo stesso lotto puo' avere piu' righe di pacco, e senza somma
--      la riga del Batch verrebbe moltiplicata nel join
--   b) FULL OUTER JOIN: tiene tutti i lotti (solo Batch, solo pacchi, entrambi)
--   c) COALESCE: chiave dal lato presente, quantita' mancanti = 0
-- ------------------------------------------------------------
CREATE TABLE out_3_zoho_e_pacchi_als AS
SELECT COALESCE(b.sku, k.sku)                                  AS sku,
       COALESCE(b.lot, k.lot)                                  AS lot,
       COALESCE(b.wh,  k.wh)                                   AS wh,
       COALESCE(b.qty_zoho_onhand, 0)                          AS qty_zoho_onhand,
       COALESCE(k.qty_open, 0)                                 AS qty_open_packages,
       COALESCE(b.qty_zoho_onhand, 0) + COALESCE(k.qty_open, 0) AS qty_comparabile
FROM import_batch_clean b
FULL OUTER JOIN (
    SELECT sku, lot, wh, SUM(qty_open) AS qty_open
    FROM out_1_pacchi_als
    GROUP BY sku, lot, wh
) k ON k.sku = b.sku AND k.lot = b.lot AND k.wh = b.wh;

-- ------------------------------------------------------------
-- Tabella 4: confronto Zoho contro 3PL
--   FULL OUTER JOIN su SKU + LOT + magazzino.
--   qty_3pl comprende la merce bloccata (verificato sul report del
--   03/09: anche Zoho la conta); qty_bloccata resta come informazione.
--   delta = Zoho confrontabile - 3PL
--     positivo: Zoho ha piu' di quanto c'e' al 3PL
--     negativo: il 3PL ha piu' di quanto sa Zoho
-- ------------------------------------------------------------
CREATE TABLE out_4_confronto AS
SELECT COALESCE(z.sku, g.sku)                                   AS sku,
       COALESCE(z.lot, g.lot)                                   AS lot,
       COALESCE(z.wh,  g.wh)                                    AS wh,
       COALESCE(z.qty_zoho_onhand, 0)                           AS qty_zoho_onhand,
       COALESCE(z.qty_open_packages, 0)                         AS qty_open_packages,
       COALESCE(z.qty_comparabile, 0)                           AS qty_comparabile,
       COALESCE(g.qty_3pl, 0)                                   AS qty_3pl,
       COALESCE(g.qty_bloccata, 0)                              AS qty_bloccata,
       COALESCE(z.qty_comparabile, 0) - COALESCE(g.qty_3pl, 0)  AS delta
FROM out_3_zoho_e_pacchi_als z
FULL OUTER JOIN import_giacenza_clean g
  ON g.sku = z.sku AND g.lot = z.lot AND g.wh = z.wh;

-- Categoria: stesse regole di classify_row() in pipeline.py,
-- provate nell'ordine (la prima vera vince). 0.01 = tolleranza TOL di config.py
--   aligned               nessuna differenza
--   timing-open-packages  la differenza e' esattamente pari ai pacchi aperti
--   3pl-only              Zoho = 0, il 3PL ha merce
--   zoho-only             3PL = 0, Zoho ha merce
--   investigate           tutti gli altri casi: differenza da capire
ALTER TABLE out_4_confronto ADD COLUMN categoria text;

UPDATE out_4_confronto
SET categoria = CASE
                  WHEN abs(delta) <= 0.01                     THEN 'aligned'
                  WHEN abs(delta - qty_open_packages) <= 0.01 THEN 'timing-open-packages'
                  WHEN qty_comparabile = 0 AND qty_3pl > 0    THEN '3pl-only'
                  WHEN qty_3pl = 0 AND qty_comparabile > 0    THEN 'zoho-only'
                  ELSE 'investigate'
                END;

-- ------------------------------------------------------------
-- Tabella 5: SKU dismessi (ref_sku_old), messi da parte con il motivo
--   e poi tolti dal confronto principale (foglio "Register" del report)
-- ------------------------------------------------------------
CREATE TABLE out_5_sku_dismessi AS
SELECT c.*, o.motivo
FROM out_4_confronto c
JOIN ref_sku_old o ON o.no_sku = c.sku;

DELETE FROM out_4_confronto c
USING ref_sku_old o
WHERE o.no_sku = c.sku;

-- ------------------------------------------------------------
-- CONTROLLI
-- ------------------------------------------------------------
SELECT (SELECT count(*) FROM out_1_pacchi_als)        AS pacchi_als,
       (SELECT count(*) FROM out_2_pacchi_non_als)    AS pacchi_non_als,
       (SELECT count(*) FROM out_3_zoho_e_pacchi_als) AS zoho_e_pacchi,
       (SELECT count(*) FROM out_4_confronto)         AS confronto,
       (SELECT count(*) FROM out_5_sku_dismessi)      AS sku_dismessi;

SELECT (SELECT SUM(qty_comparabile) FROM out_3_zoho_e_pacchi_als)          AS zoho_tab3,
       (SELECT SUM(qty_comparabile) FROM out_4_confronto)
     + (SELECT COALESCE(SUM(qty_comparabile), 0) FROM out_5_sku_dismessi)  AS zoho_tab4_5,
       (SELECT SUM(qty_3pl) FROM import_giacenza_clean)                    AS tpl_import,
       (SELECT SUM(qty_3pl) FROM out_4_confronto)
     + (SELECT COALESCE(SUM(qty_3pl), 0) FROM out_5_sku_dismessi)          AS tpl_tab4_5;

SELECT categoria,
       count(*)        AS righe,
       SUM(abs(delta)) AS differenza_totale
FROM out_4_confronto
GROUP BY categoria
ORDER BY righe DESC;
