#!/bin/bash
# ============================================================
# startup.sh - comando di avvio sul server (Azure App Service o altro Linux)
# In Azure: Configurazione -> Impostazioni generali -> Comando di avvio:
#     bash startup.sh
# Ogni avvio aggiorna il database e poi avvia Django con gunicorn.
# Tutti i passi sono rilanciabili senza danni.
# ============================================================
set -e

# 0. file statici (Chart.js, stile dell'admin) nella cartella staticfiles/
#    (di solito lo fa gia' la build di Azure: ripeterlo non fa danni)
python manage.py collectstatic --noinput

# 1. tabelle di Django (utenti, sessioni...)
python manage.py migrate --noinput

# 2. schema "giacenza" e tabelle del confronto (IF NOT EXISTS)
python manage.py crea_schema_giacenza

# 3. utente amministratore, SOLO se impostato nelle variabili d'ambiente
#    (DJANGO_SUPERUSER_USERNAME / _EMAIL / _PASSWORD). Se esiste gia', si prosegue.
#    Un errore qui (es. email non valida) viene segnalato nel log ma non blocca l'avvio.
if [ -n "$DJANGO_SUPERUSER_USERNAME" ]; then
    if python manage.py shell -c "from django.contrib.auth import get_user_model as U; import sys; sys.exit(0 if U().objects.filter(username='$DJANGO_SUPERUSER_USERNAME').exists() else 1)"; then
        echo "Utente admin '$DJANGO_SUPERUSER_USERNAME' gia' presente."
    else
        python manage.py createsuperuser --noinput || echo "ATTENZIONE: creazione dell'utente admin non riuscita (vedi messaggio sopra)."
    fi
fi

# 4. server web di produzione. --timeout 600: un confronto con file grandi
#    puo' richiedere qualche decina di secondi
exec gunicorn hub.wsgi --bind=0.0.0.0:8000 --workers 2 --timeout 600
