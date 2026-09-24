from django.contrib.auth.decorators import login_required
from django.shortcuts import render

from .caricamento import ErroreFile
from .esecuzione import esegui_giro
from .forms import ModuloGiro


@login_required
def pagina(request):
    """GET: modulo di upload. POST: esegue il giro e mostra i risultati."""
    risultato, errore = None, None

    if request.method == 'POST':
        modulo = ModuloGiro(request.POST, request.FILES)
        if modulo.is_valid():
            f = modulo.cleaned_data
            try:
                risultato = esegui_giro(
                    {k: f[k] for k in ('sku_alias', 'sku_old', 'batch_notes')},
                    {k: f[k] for k in ('batch', 'sales_order', 'package', 'giacenza')},
                )
            except ErroreFile as e:
                errore = str(e)       # messaggio chiaro per l'utente
    else:
        modulo = ModuloGiro()

    return render(request, 'confronto/pagina.html', {
        'modulo': modulo,
        'risultato': risultato,
        'errore': errore,
    })
