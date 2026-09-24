from django import forms


def _file(etichetta, estensione):
    """Campo file: il campo vero e' nascosto dietro un pulsante in italiano (vedi nuovo.html)."""
    return forms.FileField(
        label=etichetta,
        widget=forms.ClearableFileInput(attrs={'accept': estensione, 'class': 'input-file'}),
    )


class ModuloGiro(forms.Form):
    """I 7 file di un giro: 4 export Excel + 3 riferimenti CSV."""

    batch = _file('Batch (Zoho)', '.xlsx')
    sales_order = _file('Sales Order (Zoho)', '.xlsx')
    package = _file('Package (Zoho)', '.xlsx')
    giacenza = _file('Giacenza 3PL', '.xlsx')
    sku_alias = _file('Alias SKU (sku_alias_zoho.csv)', '.csv')
    sku_old = _file('SKU dismessi (sku_old.csv)', '.csv')
    batch_notes = _file('Note sui lotti (batch_notes.csv)', '.csv')
