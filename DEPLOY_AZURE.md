# Messa online su Microsoft Azure

Guida passo per passo per pubblicare l'hub (Django + PostgreSQL) su Azure,
nella regione **Germany West Central** (Francoforte, dati in Germania).

Risultato: `https://<nome-app>.azurewebsites.net/confronto/`, con login.

Servizi usati:

| Servizio Azure | Ruolo | Taglia consigliata per iniziare |
|---|---|---|
| **App Service** (Linux, Python 3.13) | fa girare Django | Basic **B1** |
| **Azure Database for PostgreSQL – Flexible Server** | database | Burstable **B1ms**, PostgreSQL 16 o 17 |

> Imposta subito un **budget con avviso** (Cost Management → Budgets) per evitare sorprese.

---

## 1. Database PostgreSQL

1. Portale Azure → *Crea una risorsa* → **Azure Database for PostgreSQL – Flexible Server**.
2. Impostazioni principali:
   - Regione: **Germany West Central**
   - Versione PostgreSQL: 16 o 17
   - Calcolo: **Burstable, B1ms**
   - Autenticazione: *solo PostgreSQL*; scegli **utente amministratore** e **password** (annotali)
3. Rete: **Accesso pubblico**, con la casella
   **"Consenti l'accesso pubblico da qualsiasi servizio di Azure"** attiva.
   (Per usare psql dal proprio PC aggiungere anche il proprio indirizzo IP.)
4. Dopo la creazione: *Database* → **Aggiungi** → nome **`hub`**.

Non serve creare le tabelle a mano: lo fa l'app al primo avvio (`startup.sh`).

## 2. App Service

1. *Crea una risorsa* → **App Web**.
   - Pubblica: **Codice**
   - Stack di runtime: **Python 3.13**
   - Sistema operativo: **Linux**
   - Regione: **Germany West Central**
   - Piano: **Basic B1**
2. **Distribuzione da GitHub**: nell'app → *Centro distribuzione* → origine **GitHub** →
   repository `hub`, ramo `main`. Azure crea un'azione GitHub che pubblica
   automaticamente a ogni `git push`.
3. *Configurazione* → *Impostazioni generali* → **Comando di avvio**:
   ```
   bash startup.sh
   ```

## 3. Impostazioni dell'applicazione (il ".env" di Azure)

Nell'app → *Impostazioni* → **Variabili d'ambiente** → *Impostazioni app*:

| Nome | Valore |
|---|---|
| `DJANGO_SECRET_KEY` | una chiave nuova e lunga (vedi README), **diversa** da quella del PC |
| `DJANGO_DEBUG` | `False` |
| `DB_NAME` | `hub` |
| `DB_USER` | utente amministratore del database |
| `DB_PASSWORD` | password del database |
| `DB_HOST` | `<nome-server>.postgres.database.azure.com` |
| `DB_PORT` | `5432` |
| `DB_SSLMODE` | `require` |
| `SCM_DO_BUILD_DURING_DEPLOYMENT` | `true` (Azure installa le librerie da `requirements.txt`) |
| `DJANGO_SUPERUSER_USERNAME` | (facoltativo) nome dell'amministratore da creare al primo avvio |
| `DJANGO_SUPERUSER_EMAIL` | (facoltativo) sua email |
| `DJANGO_SUPERUSER_PASSWORD` | (facoltativo) sua password |

Non serve impostare `DJANGO_ALLOWED_HOSTS`: l'indirizzo `*.azurewebsites.net`
viene aggiunto automaticamente (variabile `WEBSITE_HOSTNAME` di Azure).
Con un dominio proprio (es. `hub.adeimichei.com`) aggiungere:
`DJANGO_ALLOWED_HOSTS=hub.adeimichei.com` e
`DJANGO_CSRF_TRUSTED_ORIGINS=https://hub.adeimichei.com`.

Dopo aver creato l'amministratore, le tre variabili `DJANGO_SUPERUSER_*`
si possono cancellare.

## 4. Primo avvio e verifica

1. Salva le impostazioni: l'app si riavvia ed esegue `startup.sh`:
   `collectstatic` → `migrate` → `crea_schema_giacenza` → (admin) → `gunicorn`.
2. Apri `https://<nome-app>.azurewebsites.net/admin/` e accedi.
3. In *Utenti* crea l'utente per chi deve provare il programma
   (utente normale, non amministratore).
4. Apri `https://<nome-app>.azurewebsites.net/confronto/` → *Nuovo confronto*.

Log in caso di problemi: nell'app → **Flusso di log** (Log stream).

## Aggiornamenti

Ogni `git push` sul ramo `main` ripubblica l'app. Le modifiche alle tabelle
vengono applicate al riavvio da `startup.sh` (tutti i passi sono rilanciabili).

## Note

- Upload: i 7 file di un confronto sono qualche MB, ben sotto i limiti di App Service.
- Un confronto dura ~15 secondi; `gunicorn` ha un timeout di 600 secondi.
- I dati caricati restano solo nel database (schema `giacenza`), in Germania.
- Firmare il contratto sul trattamento dei dati (DPA) di Microsoft e, con il cliente, l'accordo relativo.
