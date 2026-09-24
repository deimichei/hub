"""
Esecuzione del giro completo: caricamento file + script SQL.

Tutto avviene in UNA transazione (transaction.atomic): se qualcosa va
storto a meta', PostgreSQL annulla tutto e le tabelle restano come
prima dell'ultimo giro riuscito.
I risultati restano salvati nelle tabelle out_* e vengono letti da
risultati.py: la pagina li mostra anche riaprendola piu' tardi.
"""

import json
from pathlib import Path

from django.db import connection, transaction

from .caricamento import DOCUMENTI, RIFERIMENTI, carica_csv, carica_excel

CARTELLA_SQL = Path(__file__).resolve().parent / 'sql'

# Ordine degli script (come run_all.sql). I riferimenti vanno per primi:
# gli alias servono alla pulizia di Batch e Package.
SCRIPT = [
    '01_riferimenti.sql',
    '02_batch.sql',
    '03_sales_order.sql',
    '04_package.sql',
    '05_giacenza_3pl.sql',
    '10_confronto.sql',
]


def imposta_schema(cursore):
    # SET LOCAL vale solo dentro la transazione corrente: le tabelle
    # senza schema esplicito vengono cercate in "giacenza"
    cursore.execute('SET LOCAL search_path TO giacenza, public')


def crea_schema():
    """Installazione / aggiornamento dello schema "giacenza". Rilanciabile."""
    with transaction.atomic(), connection.cursor() as c:
        c.execute('CREATE SCHEMA IF NOT EXISTS giacenza')
        imposta_schema(c)
        for nome in ('00_schema.sql', '00b_schema_web.sql'):
            c.execute((CARTELLA_SQL / nome).read_text(encoding='utf-8'))


def esegui_giro(utente, file_riferimenti, file_documenti):
    """
    utente:           nome dell'utente che lancia il giro
    file_riferimenti: {'sku_alias': file, 'sku_old': file, 'batch_notes': file}
    file_documenti:   {'batch': file, 'sales_order': file, 'package': file, 'giacenza': file}
    """
    caricati, nomi = {}, {}
    with transaction.atomic(), connection.cursor() as c:
        imposta_schema(c)

        # 1. caricamento dei file nelle tabelle di staging
        for chiave in RIFERIMENTI:
            caricati[chiave] = carica_csv(c, chiave, file_riferimenti[chiave])
            nomi[chiave] = file_riferimenti[chiave].name
        for chiave in DOCUMENTI:
            caricati[chiave] = carica_excel(c, chiave, file_documenti[chiave])
            nomi[chiave] = file_documenti[chiave].name

        # 2. pulizia e confronto: gli stessi script della versione psql
        for nome in SCRIPT:
            c.execute((CARTELLA_SQL / nome).read_text(encoding='utf-8'))

        # 3. registro del giro (per il riquadro "Ultimo confronto")
        c.execute(
            'INSERT INTO giri (utente, file, righe) VALUES (%s, %s, %s)',
            [utente, json.dumps(nomi), json.dumps(caricati)],
        )
