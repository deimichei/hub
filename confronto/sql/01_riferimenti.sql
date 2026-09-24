-- ============================================================
-- VERSIONE WEB di 01_import_riferimenti.sql (generata da giacenza/sql/01_import_riferimenti.sql)
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
-- 01_import_riferimenti.sql
-- Carica i 3 file di riferimento mantenuti a mano,
-- come faceva prog/clean/reference_clean.py.
--
--   sku_alias_zoho.csv -> ref_sku_alias   (SKU Zoho -> SKU canonico)
--                         AZIONE negli import di Batch e Package: lo SKU Zoho
--                         viene sostituito da quello canonico (402E -> 402).
--                         Per questo i riferimenti si caricano PER PRIMI.
--   sku_old.csv        -> ref_sku_old     (SKU dismessi + motivo)
--                         AZIONE nel confronto: esclusi, elencati a parte
--   batch_notes.csv    -> ref_batch_notes (note su SKU + lotto)
--                         SOLO COMMENTO nell'export: non cambia i numeri
--
-- Attenzione: questi file usano la VIRGOLA come separatore (non ;)
--
-- Prerequisito: tabelle create con 00_schema.sql
--
-- Uso normale:   lanciato da run_all.sql (che imposta input_dir)
-- Uso da solo:   \i C:/Users/adeim/projects/giacenza/sql/01_import_riferimenti.sql
--
-- Rilanciabile: svuota e ricarica le 3 tabelle.
-- Se un passo da' errore lo script si ferma e annulla tutto.
-- ============================================================

-- Cartella di input: se non l'ha gia' impostata run_all.sql, usa questa

-- ------------------------------------------------------------
-- Passo 0: svuota e toglie le chiavi
--          (la normalizzazione puo' creare doppioni temporanei,
--           es. "402e" e "402E" diventano uguali)
-- ------------------------------------------------------------
ALTER TABLE ref_sku_alias   DROP CONSTRAINT IF EXISTS ref_sku_alias_pkey;
ALTER TABLE ref_sku_old     DROP CONSTRAINT IF EXISTS ref_sku_old_pkey;
ALTER TABLE ref_batch_notes DROP CONSTRAINT IF EXISTS ref_batch_notes_pkey;

-- ------------------------------------------------------------
-- Passo A: caricamento (separatore , senza BOM)
-- ATTENZIONE: \copy deve restare su una sola riga, senza commenti sulla stessa riga
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- Passo B: normalizzazione, stesse regole dei documenti
-- ------------------------------------------------------------
UPDATE ref_sku_alias
SET zoho_sku     = upper(trim(zoho_sku)),
    sku_canonico = upper(trim(sku_canonico));

UPDATE ref_sku_old
SET no_sku = upper(trim(no_sku)),
    motivo = coalesce(trim(motivo), '');

UPDATE ref_batch_notes
SET sku   = upper(trim(sku)),
    batch = upper(trim(batch)),
    note  = coalesce(trim(note), '');

UPDATE ref_batch_notes
SET batch = regexp_replace(batch, '^LOT[.#\s]+', '')
WHERE batch ~ '^LOT[.#\s]+';

UPDATE ref_batch_notes
SET batch = trim(regexp_replace(batch, '\s+MAN\s+.*$', ''))
WHERE batch ~ '\s+MAN\s+';

-- 'g' = tutte le occorrenze, non solo la prima
UPDATE ref_batch_notes
SET batch = regexp_replace(batch, '[-_]', '', 'g')
WHERE batch ~ '[-_]';

-- ------------------------------------------------------------
-- Passo C: toglie i doppioni tenendo l'ULTIMA riga del file
--          (come drop_duplicates(keep="last") nel Python).
--          ctid = indirizzo nascosto della riga: le righe caricate
--          prima hanno ctid piu' basso, quindi si cancellano quelle.
-- ------------------------------------------------------------
DELETE FROM ref_sku_alias a USING ref_sku_alias b
WHERE a.zoho_sku = b.zoho_sku AND a.ctid < b.ctid;

DELETE FROM ref_sku_old a USING ref_sku_old b
WHERE a.no_sku = b.no_sku AND a.ctid < b.ctid;

DELETE FROM ref_batch_notes a USING ref_batch_notes b
WHERE a.sku = b.sku AND a.batch = b.batch AND a.ctid < b.ctid;

-- ------------------------------------------------------------
-- Passo D: rimette le chiavi
-- ------------------------------------------------------------
ALTER TABLE ref_sku_alias   ADD CONSTRAINT ref_sku_alias_pkey   PRIMARY KEY (zoho_sku);
ALTER TABLE ref_sku_old     ADD CONSTRAINT ref_sku_old_pkey     PRIMARY KEY (no_sku);
ALTER TABLE ref_batch_notes ADD CONSTRAINT ref_batch_notes_pkey PRIMARY KEY (sku, batch);

-- ------------------------------------------------------------
-- CONTROLLI
-- ------------------------------------------------------------
SELECT (SELECT count(*) FROM ref_sku_alias)   AS alias,
       (SELECT count(*) FROM ref_sku_old)     AS sku_dismessi,
       (SELECT count(*) FROM ref_batch_notes) AS note;
