"""
Lettura dei risultati dell'ultimo giro (tabelle out_* e registro giri)
e preparazione dei dati per la pagina: riepilogo, grafici, tabella
per articolo e per lotto, liste a parte.
"""

from django.db import connection, transaction

from .esecuzione import imposta_schema

TOLLERANZA = 0.01   # come TOL di config.py e 10_confronto.sql

# Categorie: etichetta per l'utente, spiegazione, colore, ordine di urgenza
CATEGORIE = {
    'investigate':          {'etichetta': 'Da verificare',             'ordine': 1, 'colore': '#c0392b',
                             'spiegazione': 'Differenza non spiegata: va capita'},
    'zoho-only':            {'etichetta': 'Solo in Zoho',              'ordine': 2, 'colore': '#d35400',
                             'spiegazione': 'Zoho ha merce che il 3PL non ha'},
    '3pl-only':             {'etichetta': 'Solo al 3PL',               'ordine': 3, 'colore': '#2471a3',
                             'spiegazione': 'Il 3PL ha merce che Zoho non conosce'},
    'timing-open-packages': {'etichetta': 'Spiegati da pacchi aperti', 'ordine': 4, 'colore': '#7d3c98',
                             'spiegazione': 'La differenza e\' pari ai pacchi aperti: probabilmente in transito'},
    'aligned':              {'etichetta': 'Allineati',                 'ordine': 5, 'colore': '#1e8449',
                             'spiegazione': 'Nessuna differenza'},
}


def _righe(cursore, sql, parametri=None):
    cursore.execute(sql, parametri or [])
    colonne = [d[0] for d in cursore.description]
    return [dict(zip(colonne, r)) for r in cursore.fetchall()]


def _numero(x):
    return float(x) if x is not None else 0.0


def leggi_ultimo_giro():
    """Restituisce None se non c'e' ancora nessun giro, altrimenti tutti i dati della pagina."""
    with transaction.atomic(), connection.cursor() as c:
        imposta_schema(c)

        # schema non ancora creato o nessun giro eseguito
        c.execute("SELECT to_regclass('giacenza.giri') IS NOT NULL")
        if not c.fetchone()[0]:
            return None
        giri = _righe(c, 'SELECT * FROM giri ORDER BY id DESC LIMIT 1')
        if not giri:
            return None
        giro = giri[0]

        # nome dell'articolo: da Zoho (Batch o Package), altrimenti dalla descrizione del 3PL.
        # Lo SKU del file va normalizzato come negli import (maiuscolo + alias).
        lotti = _righe(c, """
            WITH nomi_zoho AS (
                SELECT COALESCE(a.sku_canonico, upper(trim(f.sku))) AS sku, min(f.item_name) AS nome
                FROM (SELECT sku, item_name FROM import_batch_full
                      UNION ALL
                      SELECT sku, item_name FROM import_package_full) f
                LEFT JOIN ref_sku_alias a ON a.zoho_sku = upper(trim(f.sku))
                WHERE f.sku IS NOT NULL
                GROUP BY 1
            ),
            nomi_3pl AS (
                SELECT sku, min(descr_orig) AS nome FROM import_giacenza_clean GROUP BY sku
            )
            SELECT c.sku, c.lot,
                   COALESCE(nz.nome, n3.nome, '') AS nome,
                   c.qty_zoho_onhand, c.qty_open_packages, c.qty_comparabile,
                   c.qty_3pl, c.qty_bloccata, c.delta, c.categoria,
                   n.note AS nota
            FROM out_4_confronto c
            LEFT JOIN nomi_zoho nz ON nz.sku = c.sku
            LEFT JOIN nomi_3pl  n3 ON n3.sku = c.sku
            LEFT JOIN ref_batch_notes n ON n.sku = c.sku AND n.batch = c.lot
        """)

        dismessi = _righe(c, """
            SELECT sku, lot, qty_comparabile, qty_3pl, delta, categoria, motivo
            FROM out_5_sku_dismessi ORDER BY abs(delta) DESC, sku, lot
        """)
        pacchi_non_als = _righe(c, """
            SELECT so_number, sku, lot, qty_open
            FROM out_2_pacchi_non_als ORDER BY so_number, sku, lot
        """)
        casi_nuovi = _righe(c, """
            SELECT source AS documento, field AS campo, sku,
                   value_orig AS valore_nel_file, value_clean AS valore_pulito
            FROM cleaning_log
            -- stesso fuso della sessione usato da current_date negli script
            WHERE first_seen = (%s)::date
            ORDER BY source, field, sku, value_orig
        """, [giro['eseguito_il']])

    # --- lotti: arricchiti per la pagina ---
    for r in lotti:
        for k in ('qty_zoho_onhand', 'qty_open_packages', 'qty_comparabile', 'qty_3pl', 'qty_bloccata', 'delta'):
            r[k] = _numero(r[k])
        r['delta_abs'] = abs(r['delta'])
        r['con_differenza'] = r['delta_abs'] > TOLLERANZA
        r['cat'] = CATEGORIE[r['categoria']]
    lotti.sort(key=lambda r: (-r['delta_abs'], r['cat']['ordine'], r['sku'], r['lot']))

    # --- articoli: raggruppati per SKU, ordinati per il delta piu' grande tra i loro lotti ---
    articoli = {}
    for r in lotti:                              # lotti gia' in ordine di |delta|
        a = articoli.setdefault(r['sku'], {'sku': r['sku'], 'nome': r['nome'], 'lotti': []})
        a['lotti'].append(r)
    for a in articoli.values():
        a['delta_max'] = a['lotti'][0]['delta']                 # con segno
        a['delta_max_abs'] = a['lotti'][0]['delta_abs']
        a['netto'] = sum(r['delta'] for r in a['lotti'])
        a['netto_abs'] = abs(a['netto'])
        a['somma_abs'] = sum(r['delta_abs'] for r in a['lotti'])
        a['n_con_differenza'] = sum(1 for r in a['lotti'] if r['con_differenza'])
        a['tutto_allineato'] = a['n_con_differenza'] == 0
        # netto ~0 ma differenze sui lotti: quantita' giusta, lotti sbagliati?
        a['lotti_scambiati'] = abs(a['netto']) <= TOLLERANZA and a['somma_abs'] > TOLLERANZA
    articoli = sorted(articoli.values(), key=lambda a: (-a['delta_max_abs'], a['sku']))

    # --- riepilogo per categoria ---
    riepilogo = []
    for chiave, cat in sorted(CATEGORIE.items(), key=lambda kv: kv[1]['ordine']):
        sel = [r for r in lotti if r['categoria'] == chiave]
        riepilogo.append({
            'chiave': chiave, 'cat': cat, 'righe': len(sel),
            'zoho_in_piu': sum(r['delta'] for r in sel if r['delta'] > 0),
            'tpl_in_piu': -sum(r['delta'] for r in sel if r['delta'] < 0),
        })

    # --- dati per i grafici (Chart.js) ---
    grafici = {
        'categorie': {
            'etichette': [x['cat']['etichetta'] for x in riepilogo],
            'righe': [x['righe'] for x in riepilogo],
            'colori': [x['cat']['colore'] for x in riepilogo],
        },
        'top_lotti': [
            {'etichetta': f"{r['sku']} · {r['lot']}", 'delta': r['delta']}
            for r in lotti[:10] if r['con_differenza']
        ],
    }

    return {
        'giro': giro,
        'lotti': lotti,
        'articoli': articoli,
        'riepilogo': riepilogo,
        'grafici': grafici,
        'totali': {
            'lotti': len(lotti),
            'con_differenza': sum(1 for r in lotti if r['con_differenza']),
            'articoli_con_differenza': sum(1 for a in articoli if not a['tutto_allineato']),
            'zoho_in_piu': sum(r['delta'] for r in lotti if r['delta'] > 0),
            'tpl_in_piu': -sum(r['delta'] for r in lotti if r['delta'] < 0),
        },
        'dismessi': dismessi,
        'pacchi_non_als': pacchi_non_als,
        'casi_nuovi': casi_nuovi,
    }
