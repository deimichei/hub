-- ============================================================
-- VERSIONE WEB di 00_schema.sql (generata da giacenza/sql/00_schema.sql)
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
-- 00_schema.sql
-- Crea TUTTE le tabelle del database giacenza.
-- Si lancia una volta sola (o quando cambia la struttura).
-- Rilanciabile senza danni: IF NOT EXISTS non tocca le tabelle esistenti.
--
-- Uso (da psql): \i C:/Users/adeim/projects/giacenza/sql/00_schema.sql
--
-- Le staging (full_*) sono generate dalle intestazioni dei CSV in
-- BASE_DIR/24sett: tutte text, nomi in minuscolo senza spazi/accenti.
-- A destra, commentato, il nome originale quando e' diverso.
-- ============================================================

-- ============================================================
-- A. STAGING: dati grezzi, svuotate e ricaricate a ogni giro
-- ============================================================

-- Zoho Batch: 01_Batch.csv (27 colonne)
CREATE UNLOGGED TABLE IF NOT EXISTS import_batch_full (
  item_id                   text,
  item_name                 text,
  sku                       text,
  category_name             text,
  batch_id                  text,
  batch_number              text,
  age                       text,
  manufacturer_batch_number text,
  manufactured_date         text,
  expiry_date               text,
  in_quantity               text,
  new_in_quantity           text,
  out_quantity              text,
  balance_quantity          text,
  new_balance_quantity      text,
  selling_price             text,
  cost_price                text,
  profit                    text,
  inward_entity_number      text,
  inward_entity_id          text,
  in_entity_type            text,
  outward_entity_number     text,
  in_entity_date            text,
  out_entity_date           text,
  outward_entity_id         text,
  out_entity_type           text,
  status                    text
);

-- Zoho Sales Order: 02_Sales_Order.csv (87 colonne)
CREATE UNLOGGED TABLE IF NOT EXISTS import_sales_order_full (
  salesorder_id              text,   -- SalesOrder ID
  order_date                 text,   -- Order Date
  expected_shipment_date     text,   -- Expected Shipment Date
  salesorder_number          text,   -- SalesOrder Number
  status                     text,   -- Status
  custom_status              text,   -- Custom Status
  customer_id                text,   -- Customer ID
  location_id                text,   -- Location ID
  location_name              text,   -- Location Name
  sales_channel              text,   -- Sales Channel
  customer_name              text,   -- Customer Name
  is_inclusive_tax           text,   -- Is Inclusive Tax
  purchaseorder              text,   -- PurchaseOrder
  template_name              text,   -- Template Name
  currency_code              text,   -- Currency Code
  exchange_rate              text,   -- Exchange Rate
  discount_type              text,   -- Discount Type
  is_discount_before_tax     text,   -- Is Discount Before Tax
  entity_discount_amount     text,   -- Entity Discount Amount
  entity_discount_percent    text,   -- Entity Discount Percent
  item_name                  text,   -- Item Name
  product_id                 text,   -- Product ID
  sku                        text,   -- SKU
  upc                        text,   -- UPC
  mpn                        text,   -- MPN
  ean                        text,   -- EAN
  isbn                       text,   -- ISBN
  kit_combo_item_name        text,   -- Kit Combo Item Name
  account                    text,   -- Account
  item_desc                  text,   -- Item Desc
  quantityordered            text,   -- QuantityOrdered
  quantityinvoiced           text,   -- QuantityInvoiced
  quantitypacked             text,   -- QuantityPacked
  quantitycancelled          text,   -- QuantityCancelled
  usage_unit                 text,   -- Usage unit
  line_item_location_id      text,   -- Line Item Location ID
  line_item_location_name    text,   -- Line Item Location Name
  item_price                 text,   -- Item Price
  discount                   text,   -- Discount
  discount_amount            text,   -- Discount Amount
  tax_id                     text,   -- Tax ID
  item_tax                   text,   -- Item Tax
  item_tax_2                 text,   -- Item Tax %
  item_tax_amount            text,   -- Item Tax Amount
  item_tax_type              text,   -- Item Tax Type
  esclude_da_vendite         text,   -- Esclude da Vendite
  centro_di_costo            text,   -- Centro di Costo
  iva_estera                 text,   -- IVA estera
  item_total                 text,   -- Item Total
  subtotal                   text,   -- SubTotal
  total                      text,   -- Total
  shipping_charge            text,   -- Shipping Charge
  shipping_charge_tax_id     text,   -- Shipping Charge Tax ID
  shipping_charge_tax_amount text,   -- Shipping Charge Tax Amount
  shipping_charge_tax_name   text,   -- Shipping Charge Tax Name
  shipping_charge_tax        text,   -- Shipping Charge Tax %
  shipping_charge_tax_type   text,   -- Shipping Charge Tax Type
  adjustment                 text,   -- Adjustment
  adjustment_description     text,   -- Adjustment Description
  sales_person               text,   -- Sales Person
  payment_terms              text,   -- Payment Terms
  payment_terms_label        text,   -- Payment Terms Label
  notes                      text,   -- Notes
  terms_conditions           text,   -- Terms & Conditions
  delivery_method            text,   -- Delivery Method
  source                     text,   -- Source
  billing_address            text,   -- Billing Address
  billing_street2            text,   -- Billing Street2
  billing_city               text,   -- Billing City
  billing_state              text,   -- Billing State
  billing_country            text,   -- Billing Country
  billing_code               text,   -- Billing Code
  billing_fax                text,   -- Billing Fax
  billing_phone              text,   -- Billing Phone
  shipping_address           text,   -- Shipping Address
  shipping_street2           text,   -- Shipping Street2
  shipping_city              text,   -- Shipping City
  shipping_state             text,   -- Shipping State
  shipping_country           text,   -- Shipping Country
  shipping_code              text,   -- Shipping Code
  shipping_fax               text,   -- Shipping Fax
  shipping_phone             text,   -- Shipping Phone
  cf_delivery_terms          text,   -- CF.Delivery Terms
  cf_delivery_place          text,   -- CF.Delivery Place
  cf_rappresentante_fiscale  text,   -- CF.Rappresentante fiscale
  cf_causale                 text,   -- CF.Causale
  cf_note_portale            text   -- CF.Note Portale
);

-- Zoho Package: 03_Package.csv (47 colonne)
CREATE UNLOGGED TABLE IF NOT EXISTS import_package_full (
  packageitemid       text,   -- PackageItemID
  packing_date        text,   -- Packing Date
  packing_number      text,   -- Packing Number
  notes               text,   -- Notes
  so_number           text,   -- SO Number
  customer_name       text,   -- Customer Name
  status              text,   -- Status
  item_name           text,   -- Item Name
  quantity_packed     text,   -- Quantity Packed
  sku                 text,   -- SKU
  item_price          text,   -- Item Price
  length              text,   -- Length
  width               text,   -- Width
  height              text,   -- Height
  dimension_unit      text,   -- Dimension Unit
  weight              text,   -- Weight
  net_weight          text,   -- Net Weight
  weight_unit         text,   -- Weight Unit
  kit_combo_item_name text,   -- Kit Combo Item Name
  batch_id            text,   -- Batch ID
  batch_reference     text,   -- Batch Reference#
  manufacturer_batch  text,   -- Manufacturer Batch#
  manufactured_date   text,   -- Manufactured Date
  expiry_date         text,   -- Expiry Date
  quantity_out        text,   -- Quantity Out
  billing_address     text,   -- Billing Address
  billing_address_2   text,   -- Billing Address
  billing_city        text,   -- Billing City
  billing_state       text,   -- Billing State
  billing_country     text,   -- Billing Country
  billing_code        text,   -- Billing Code
  billing_fax         text,   -- Billing Fax
  billing_phone       text,   -- Billing Phone
  billing_attention   text,   -- Billing Attention
  shipping_address    text,   -- Shipping Address
  shipping_address_2  text,   -- Shipping Address
  shipping_city       text,   -- Shipping City
  shipping_state      text,   -- Shipping State
  shipping_country    text,   -- Shipping Country
  shipping_code       text,   -- Shipping Code
  shipping_fax        text,   -- Shipping Fax
  shipping_phone      text,   -- Shipping Phone
  shipping_attention  text,   -- Shipping Attention
  cf_delivery_terms   text,   -- CF.Delivery Terms
  cf_delivery_place   text,   -- CF.Delivery Place
  cf_package_details  text,   -- CF.Package Details
  cf_tracking_number  text   -- CF.Tracking Number
);

-- 3PL Giacenza PDE: 04_Giacenza_PDE.csv (11 colonne)
CREATE UNLOGGED TABLE IF NOT EXISTS import_giacenza_full (
  codice_articolo text,   -- Codice articolo
  descrizione     text,   -- Descrizione
  quantita        text,   -- Quantita (con accento)
  qualita         text,   -- Qualita (con accento)
  numero_fattura  text,   -- Numero fattura
  data_scadenza   text,   -- Data scadenza
  numero_lotto    text,   -- Numero lotto
  bloccato        text,   -- Bloccato?
  numero_collo    text,   -- Numero collo
  numero_prebolla text,   -- Numero prebolla
  destinatario    text   -- Destinatario
);

-- ============================================================
-- B. RIFERIMENTI: file mantenuti a mano (separatore , senza BOM)
--    Svuotati e ricaricati a ogni giro, come le staging.
-- ============================================================

-- sku_alias_zoho.csv: SKU Zoho -> SKU canonico (es. 402E -> 402)
CREATE TABLE IF NOT EXISTS ref_sku_alias (
  zoho_sku     text NOT NULL PRIMARY KEY,
  sku_canonico text NOT NULL
);

-- sku_old.csv: SKU dismessi, esclusi dal confronto
CREATE TABLE IF NOT EXISTS ref_sku_old (
  no_sku text NOT NULL PRIMARY KEY,
  motivo text
);

-- batch_notes.csv: note manuali su singoli lotti
CREATE TABLE IF NOT EXISTS ref_batch_notes (
  sku   text NOT NULL,
  batch text NOT NULL,
  note  text,
  CONSTRAINT ref_batch_notes_pkey PRIMARY KEY (sku, batch)
);

-- ============================================================
-- C. TABELLE FINALI (pulite)
--    Si aggiungono man mano
--    quando scriviamo i rispettivi script di import.
-- ============================================================

CREATE TABLE IF NOT EXISTS import_batch_clean (
  sku             text    NOT NULL,
  lot             text    NOT NULL,
  qty_zoho_onhand numeric NOT NULL,
  wh              text    NOT NULL DEFAULT 'ALS',
  CONSTRAINT import_batch_clean_pkey PRIMARY KEY (sku, lot, wh)
);

-- valori originali, prima della pulizia (servono al cleaning_log)
ALTER TABLE import_batch_clean ADD COLUMN IF NOT EXISTS sku_orig text;
ALTER TABLE import_batch_clean ADD COLUMN IF NOT EXISTS lot_orig text;

-- Sales Order: quali ordini (SO) partono dal magazzino ALS
CREATE TABLE IF NOT EXISTS import_sales_order_clean (
  so_number text NOT NULL,
  wh        text NOT NULL DEFAULT 'ALS',
  CONSTRAINT import_sales_order_clean_pkey PRIMARY KEY (so_number, wh)
);

-- Package: pacchi aperti (non consegnati), una riga per riga di pacco.
-- Nessun accorpamento, quindi la chiave e' un contatore automatico (id).
CREATE TABLE IF NOT EXISTS import_package_clean (
  id        bigint  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  so_number text    NOT NULL,
  sku       text    NOT NULL,
  lot       text    NOT NULL,
  qty_open  numeric NOT NULL,
  sku_orig  text,
  lot_orig  text
);

-- Giacenza 3PL: inventario fisico del magazzino ALS, accorpato per SKU + LOT.
-- qty_3pl = totale (bloccati compresi), qty_bloccata = di cui bloccata.
-- Se contare i bloccati o no si decide nel confronto (10_confronto.sql).
CREATE TABLE IF NOT EXISTS import_giacenza_clean (
  sku          text    NOT NULL DEFAULT '',
  lot          text    NOT NULL,
  wh           text    NOT NULL DEFAULT 'ALS',
  qty_3pl      numeric NOT NULL,
  qty_bloccata numeric NOT NULL,
  descr_orig   text,
  codice_orig  text,
  lot_orig     text,
  CONSTRAINT import_giacenza_clean_pkey PRIMARY KEY (sku, lot, wh)
);

-- ============================================================
-- D. CLEANING_LOG: archivio dei casi di pulizia
--    NON si svuota mai. Una riga per ogni caso distinto:
--    se ricompare, si aggiornano solo last_seen e times_seen.
-- ============================================================

CREATE TABLE IF NOT EXISTS cleaning_log (
  source      text    NOT NULL,                      -- documento: batch, package, giacenza...
  field       text    NOT NULL,                      -- colonna pulita: sku, lot
  sku         text    NOT NULL DEFAULT '',           -- contesto: a quale SKU appartiene
  value_orig  text    NOT NULL,                      -- valore com'era nel file
  value_clean text    NOT NULL,                      -- valore dopo la pulizia
  first_seen  date    NOT NULL DEFAULT current_date, -- prima volta vista
  last_seen   date    NOT NULL DEFAULT current_date, -- ultima volta vista
  times_seen  integer NOT NULL DEFAULT 1,            -- in quanti giri e' comparso
  CONSTRAINT cleaning_log_pkey PRIMARY KEY (source, field, sku, value_orig)
);

