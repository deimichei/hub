-- ============================================================
-- VERSIONE WEB di 05_import_giacenza_3pl.sql (generata da giacenza/sql/05_import_giacenza_3pl.sql)
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
-- 05_import_giacenza_3pl.sql
-- Importa e pulisce la giacenza del 3PL (04_Giacenza_PDE.csv)
-- come faceva prog/clean/giacenze_clean.py.
--
-- Risultato: import_giacenza_clean = inventario fisico del
-- magazzino ALS, una riga per SKU + LOT, con:
--   qty_3pl      = quantita' totale (bloccati compresi)
--   qty_bloccata = di cui bloccata (Bloccato? = S)
-- Se contare i bloccati o no si decide nel confronto.
--
-- Prerequisito: tabelle create con 00_schema.sql
--
-- Uso normale:   lanciato da run_all.sql (che imposta input_dir)
-- Uso da solo:   \i C:/Users/adeim/projects/giacenza/sql/05_import_giacenza_3pl.sql
--
-- Rilanciabile: svuota e ricarica staging e tabella pulita.
-- Il cleaning_log invece NON si svuota: accumula i casi nel tempo.
-- Se un passo da' errore lo script si ferma e annulla tutto.
-- ============================================================

-- Cartella di input: se non l'ha gia' impostata run_all.sql, usa questa

-- ------------------------------------------------------------
-- A. STAGING: CSV grezzo (11 colonne, intestazione alla riga 1)
-- ------------------------------------------------------------

-- ENCODING 'UTF8': i CSV sono UTF-8 (psql su Windows altrimenti li legge come WIN1252)
-- ATTENZIONE: \copy deve restare su una sola riga, senza commenti sulla stessa riga

-- ------------------------------------------------------------
-- B. TABELLA PULITA import_giacenza_clean
-- ------------------------------------------------------------

-- Passo 0: svuota e toglie la chiave (prima dell'accorpamento ci sono doppioni)
TRUNCATE import_giacenza_clean;
ALTER TABLE import_giacenza_clean DROP CONSTRAINT IF EXISTS import_giacenza_clean_pkey;

-- Passo D: copia le righe con un lotto vero.
--   Scarta i lotti finti "." e "MAT PUBBLICITARIO" e i lotti vuoti
--   (il Python li trasformava per errore nel testo "NAN").
--   qty_bloccata = quantita' della riga se Bloccato? = S, altrimenti 0:
--   accorpando, le somme danno totale e parte bloccata.
INSERT INTO import_giacenza_clean (lot, qty_3pl, qty_bloccata, descr_orig, codice_orig, lot_orig)
SELECT numero_lotto,
       quantita::numeric,
       CASE WHEN trim(bloccato) = 'S' THEN quantita::numeric ELSE 0 END,
       descrizione,
       codice_articolo,
       numero_lotto
FROM import_giacenza_full
WHERE numero_lotto IS NOT NULL
  AND trim(numero_lotto) NOT IN ('.', 'MAT PUBBLICITARIO');

-- Passo E: SKU ricavato dalla DESCRIZIONE, non da "Codice articolo"
--   (verificato sui dati reali: il codice articolo spesso e' un codice a barre).
--   Stessa regola di sku_from_descrizione() in giacenze_clean.py,
--   verificata riga per riga contro il Python (0 differenze):
--     1. c'e' " -"                     -> testo prima di " -"     (202 - GLOW PEEL -> 202)
--     2. c'e' un trattino - o lungo    -> testo prima del trattino (010-BANDS PINK -> 010)
--     3. inizia con codice di 3-6 car. -> quel codice             (015WG WHITE GOLD -> 015WG)
--     4. altrimenti                    -> prima parola
--   \M = fine parola (come \b in Python)
--   \u2013 e \u2014 = trattini lunghi (en dash, em dash), scritti come codice
--   Unicode e non come carattere: psql su Windows legge i file come WIN1252
--   e il carattere vero arriverebbe al server storpiato (errore silenzioso).
UPDATE import_giacenza_clean
SET sku = upper(trim(coalesce(descr_orig, '')));

UPDATE import_giacenza_clean
SET sku = CASE
            WHEN sku = '' THEN ''
            WHEN strpos(sku, ' -') > 0
              THEN trim(split_part(sku, ' -', 1))
            WHEN trim(regexp_replace(sku, '\s?[-\u2013\u2014].*$', '')) <> '' AND sku ~ '[-\u2013\u2014]'
              THEN trim(regexp_replace(sku, '\s?[-\u2013\u2014].*$', ''))
            WHEN sku ~ '^[A-Z0-9]{3,6}\M'
              THEN substring(sku from '^([A-Z0-9]{3,6})\M')
            ELSE split_part(sku, ' ', 1)
          END;

-- Passo F: pulizia SKU e LOT, stesse regole degli altri documenti
UPDATE import_giacenza_clean
SET sku = upper(trim(sku));

UPDATE import_giacenza_clean
SET lot = upper(trim(lot));

UPDATE import_giacenza_clean
SET lot = regexp_replace(lot, '^LOT[.#\s]+', '')
WHERE lot ~ '^LOT[.#\s]+';

UPDATE import_giacenza_clean
SET lot = trim(regexp_replace(lot, '\s+MAN\s+.*$', ''))
WHERE lot ~ '\s+MAN\s+';

-- 'g' = tutte le occorrenze, non solo la prima
UPDATE import_giacenza_clean
SET lot = regexp_replace(lot, '[-_]', '', 'g')
WHERE lot ~ '[-_]';

-- ------------------------------------------------------------
-- Passo G: CLEANING_LOG (prima di accorpare)
--   ON CONFLICT: se il caso e' gia' noto aggiorna last_seen;
--   times_seen sale solo se e' un giorno nuovo.
-- ------------------------------------------------------------

-- LOT modificati dalla pulizia
INSERT INTO cleaning_log AS c (source, field, sku, value_orig, value_clean)
SELECT DISTINCT 'giacenza', 'lot', sku, lot_orig, lot
FROM import_giacenza_clean
WHERE lot_orig IS DISTINCT FROM lot
ON CONFLICT (source, field, sku, value_orig) DO UPDATE
SET value_clean = EXCLUDED.value_clean,
    times_seen  = c.times_seen + CASE WHEN c.last_seen < current_date THEN 1 ELSE 0 END,
    last_seen   = current_date;

-- "Codice articolo" diverso dallo SKU ricavato dalla descrizione
-- (value_orig = codice scritto nel file, value_clean = SKU vero).
-- Non si registra ogni descrizione: sarebbe rumore a ogni giro.
INSERT INTO cleaning_log AS c (source, field, sku, value_orig, value_clean)
SELECT DISTINCT 'giacenza', 'codice_articolo', sku, coalesce(codice_orig, ''), sku
FROM import_giacenza_clean
WHERE upper(trim(codice_orig)) IS DISTINCT FROM sku
ON CONFLICT (source, field, sku, value_orig) DO UPDATE
SET value_clean = EXCLUDED.value_clean,
    times_seen  = c.times_seen + CASE WHEN c.last_seen < current_date THEN 1 ELSE 0 END,
    last_seen   = current_date;

-- Doppioni che il passo H sta per accorpare
-- (nella giacenza sono frequenti: stesso lotto in piu' colli/posizioni)
INSERT INTO cleaning_log AS c (source, field, sku, value_orig, value_clean)
SELECT 'giacenza', 'doppione', sku, string_agg(DISTINCT lot_orig, ' | '), lot
FROM import_giacenza_clean
GROUP BY sku, lot, wh
HAVING count(*) > 1
ON CONFLICT (source, field, sku, value_orig) DO UPDATE
SET value_clean = EXCLUDED.value_clean,
    times_seen  = c.times_seen + CASE WHEN c.last_seen < current_date THEN 1 ELSE 0 END,
    last_seen   = current_date;

-- Passo H: accorpa per SKU + LOT sommando totale e parte bloccata.
--          I campi *_orig conservano tutte le varianti, separate da " | "
WITH vecchie AS (
  DELETE FROM import_giacenza_clean
  RETURNING *
)
INSERT INTO import_giacenza_clean (sku, lot, wh, qty_3pl, qty_bloccata, descr_orig, codice_orig, lot_orig)
SELECT sku, lot, wh,
       SUM(qty_3pl),
       SUM(qty_bloccata),
       string_agg(DISTINCT descr_orig,  ' | '),
       string_agg(DISTINCT codice_orig, ' | '),
       string_agg(DISTINCT lot_orig,    ' | ')
FROM vecchie
GROUP BY sku, lot, wh;

-- Passo I: rimette la chiave primaria (fallisce se restano doppioni)
ALTER TABLE import_giacenza_clean
  ADD CONSTRAINT import_giacenza_clean_pkey PRIMARY KEY (sku, lot, wh);

-- ------------------------------------------------------------
-- C. CONTROLLI
-- ------------------------------------------------------------
SELECT count(*)                                                   AS righe_file,
       count(*) FILTER (WHERE trim(numero_lotto) = '.')                 AS lotto_punto,
       count(*) FILTER (WHERE trim(numero_lotto) = 'MAT PUBBLICITARIO') AS mat_pubblicitario,
       count(*) FILTER (WHERE numero_lotto IS NULL)                     AS lotto_vuoto,
       count(*) FILTER (WHERE trim(bloccato) = 'S')                     AS bloccate
FROM import_giacenza_full;

SELECT count(*)          AS righe_sku_lot,
       SUM(qty_3pl)      AS qty_totale,
       SUM(qty_bloccata) AS qty_bloccata
FROM import_giacenza_clean;

SELECT field,
       count(*) FILTER (WHERE last_seen  = current_date) AS visti_oggi,
       count(*) FILTER (WHERE first_seen = current_date) AS nuovi_oggi
FROM cleaning_log
WHERE source = 'giacenza'
GROUP BY field
ORDER BY field;
