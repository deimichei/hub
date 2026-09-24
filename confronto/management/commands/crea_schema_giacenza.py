"""
Comando di installazione (una volta sola, o quando cambia 00_schema.sql):

    uv run manage.py crea_schema_giacenza

Crea lo schema "giacenza" nel database hub con tutte le tabelle.
Rilanciabile senza danni (CREATE ... IF NOT EXISTS).
"""

from django.core.management.base import BaseCommand

from confronto.esecuzione import crea_schema


class Command(BaseCommand):
    help = 'Crea lo schema "giacenza" e le tabelle del confronto giacenze'

    def handle(self, *args, **options):
        crea_schema()
        self.stdout.write(self.style.SUCCESS('Schema "giacenza" pronto.'))
