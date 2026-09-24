-- ============================================================
-- 00b_schema_web.sql  (solo versione web)
-- Registro dei giri eseguiti dalla pagina: serve a mostrare
-- "Ultimo confronto" (data, utente, file usati, righe caricate)
-- anche riaprendo la pagina in un secondo momento.
-- ============================================================

CREATE TABLE IF NOT EXISTS giri (
  id          bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  eseguito_il timestamptz NOT NULL DEFAULT now(),
  utente      text        NOT NULL,
  file        jsonb       NOT NULL,   -- {"batch": "Batch.xlsx", ...}
  righe       jsonb       NOT NULL    -- {"batch": 131, ...} righe caricate
);
