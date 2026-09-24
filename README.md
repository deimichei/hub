# Hub – programmi web per clienti

Progetto Django che raccoglie più programmi piccoli per clienti. Ogni programma è
un'**app Django** con il suo **schema PostgreSQL**.

Programmi presenti:

| App | Schema DB | Cosa fa |
|---|---|---|
| `confronto` | `giacenza` | Confronto giacenze **Zoho** vs magazzino **3PL (ALS)**: carica 4 export Excel + 3 CSV di riferimento, pulisce SKU e lotti, confronta e mostra risultati, grafici e dettaglio per articolo/lotto |

## Tecnologie

- Python 3.13, gestito con [uv](https://docs.astral.sh/uv/)
- Django 6, psycopg 3, openpyxl, python-dotenv
- PostgreSQL (16 o più recente)
- Chart.js incluso nel progetto (`confronto/static/`), nessun CDN esterno

## Installazione (prima volta)

1. **Installa gli strumenti**: [uv](https://docs.astral.sh/uv/getting-started/installation/) e
   [PostgreSQL](https://www.postgresql.org/download/) (con psql). Python lo installa uv da solo.

2. **Scarica il progetto**
   ```
   git clone https://github.com/deimichei/hub.git
   cd hub
   ```

3. **Installa le librerie** (crea la cartella `.venv`)
   ```
   uv sync
   ```

4. **Crea il database** in psql
   ```sql
   CREATE DATABASE hub;
   ```

5. **Crea il file `.env`** copiando il modello e inserendo i tuoi dati
   ```
   copy .env.example .env        (Windows)
   cp .env.example .env          (Mac / Linux)
   ```
   Poi apri `.env` e compila `DB_PASSWORD` e `DJANGO_SECRET_KEY`.
   Una chiave nuova si genera con:
   ```
   uv run python -c "from django.core.management.utils import get_random_secret_key as k; print(k())"
   ```
   **Il file `.env` non va mai su git** (è già escluso in `.gitignore`).

6. **Crea le tabelle**
   ```
   uv run manage.py migrate
   uv run manage.py crea_schema_giacenza
   uv run manage.py createsuperuser
   ```

## Avvio

```
uv run manage.py runserver
```

Poi apri <http://127.0.0.1:8000/confronto/> (login con l'utente creato sopra).
Su Windows basta un doppio clic su `Avvia_hub.bat`.

Gestione utenti: <http://127.0.0.1:8000/admin/>

## Struttura dell'app `confronto`

| Percorso | Ruolo |
|---|---|
| `confronto/sql/` | logica in SQL: `00_schema.sql` (tabelle), `01…05` import e pulizia (riferimenti, Batch, Sales Order, Package, Giacenza 3PL), `10_confronto.sql` (confronto e categorie) |
| `confronto/caricamento.py` | legge gli Excel/CSV caricati e li scrive nelle tabelle `import_*_full` (colonne abbinate per nome) |
| `confronto/esecuzione.py` | esegue un giro completo in una sola transazione |
| `confronto/risultati.py` | prepara i dati per la pagina (riepilogo, grafici, raggruppamento per articolo) |
| `confronto/views.py`, `urls.py`, `forms.py`, `templates/` | pagine: `/confronto/` risultati, `/confronto/nuovo/` caricamento |
| `confronto/management/commands/crea_schema_giacenza.py` | crea/aggiorna lo schema `giacenza` |

Flusso dei dati nel database (schema `giacenza`):

```
file caricati → import_<doc>_full (grezzo) → import_<doc>_clean (pulito) → out_1 … out_5 (confronto)
                                  ↘ cleaning_log (storico dei casi di pulizia)
```

## File di input di un confronto

| Campo | File | Note |
|---|---|---|
| Batch (Zoho) | `.xlsx` | Batch Details, con riga di titolo sopra l'intestazione |
| Sales Order (Zoho) | `.xlsx` | serve a sapere quali ordini sono del magazzino ALS |
| Package (Zoho) | `.xlsx` | pacchi; si usano quelli non consegnati |
| Giacenza 3PL | `.xlsx` | Giacenza_PDE del magazzino |
| Alias SKU | `sku_alias_zoho.csv` | `zoho_sku,sku_canonico` (es. `402E,402`) |
| SKU dismessi | `sku_old.csv` | `no_sku,motivo` |
| Note sui lotti | `batch_notes.csv` | `Sku,batch,note` |

I dati dei clienti **non** sono nel repository.
