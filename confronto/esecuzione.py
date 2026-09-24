"""
Esecuzione del giro completo: caricamento file + script SQL + risultati.

Tutto avviene in UNA transazione (transaction.atomic): se qualcosa va
storto a meta', PostgreSQL annulla tutto e le tabelle restano come
prima dell'ultimo giro riuscito.
"""

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


def _imposta_schema(cursore):
    # SET LOCAL vale solo dentro questa transazione: le tabelle senza
    # schema esplicito vengono cercate in "giacenza"
    cursore.execute('SET LOCAL search_path TO giacenza, public')


def crea_schema():
    """Prima installazione: schema "giacenza" e tutte le tabelle (00_schema.sql)."""
    with transaction.atomic(), connection.cursor() as c:
        c.execute('CREATE SCHEMA IF NOT EXISTS giacenza')
        _imposta_schema(c)
        c.execute((CARTELLA_SQL / '00_schema.sql').read_text(encoding='utf-8'))


def esegui_giro(file_riferimenti, file_documenti):
    """
    file_riferimenti: {'sku_alias': file, 'sku_old': file, 'batch_notes': file}
    file_documenti:   {'batch': file, 'sales_order': file, 'package': file, 'giacenza': file}
    Restituisce un dizionario con conteggi, riepilogo e righe del confronto.
    """
    caricati = {}
    with transaction.atomic(), connection.cursor() as c:
        _imposta_schema(c)

        # 1. caricamento dei file nelle tabelle di staging
        for chiave in RIFERIMENTI:
            caricati[chiave] = carica_csv(c, chiave, file_riferimenti[chiave])
        for chiave in DOCUMENTI:
            caricati[chiave] = carica_excel(c, chiave, file_documenti[chiave])

        # 2. pulizia e confronto: gli stessi script della versione psql
        for nome in SCRIPT:
            c.execute((CARTELLA_SQL / nome).read_text(encoding='utf-8'))

        # 3. risultati per la pagina
        c.execute(
            'SELECT categoria, count(*), SUM(abs(delta)) '
            'FROM out_4_confronto GROUP BY categoria ORDER BY 3 DESC, 1'
        )
        riepilogo = c.fetchall()

        c.execute(
            'SELECT c.sku, c.lot, c.qty_zoho_onhand, c.qty_open_packages, '
            '       c.qty_comparabile, c.qty_3pl, c.qty_bloccata, c.delta, '
            '       c.categoria, n.note '
            'FROM out_4_confronto c '
            'LEFT JOIN ref_batch_notes n ON n.sku = c.sku AND n.batch = c.lot '
            "ORDER BY c.categoria = 'aligned', c.categoria, abs(c.delta) DESC, c.sku, c.lot"
        )
        righe = c.fetchall()

        c.execute('SELECT count(*) FROM out_5_sku_dismessi')
        n_dismessi = c.fetchone()[0]
        c.execute('SELECT count(*) FROM out_2_pacchi_non_als')
        n_pacchi_non_als = c.fetchone()[0]
        c.execute('SELECT count(*) FROM cleaning_log WHERE first_seen = current_date')
        n_casi_nuovi = c.fetchone()[0]

    return {
        'caricati': caricati,
        'riepilogo': riepilogo,
        'righe': righe,
        'n_dismessi': n_dismessi,
        'n_pacchi_non_als': n_pacchi_non_als,
        'n_casi_nuovi': n_casi_nuovi,
    }
