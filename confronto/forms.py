from django import forms


class ModuloGiro(forms.Form):
    """I 7 file di un giro: 4 export Excel + 3 riferimenti CSV."""

    batch = forms.FileField(label='Batch (Zoho) .xlsx')
    sales_order = forms.FileField(label='Sales Order (Zoho) .xlsx')
    package = forms.FileField(label='Package (Zoho) .xlsx')
    giacenza = forms.FileField(label='Giacenza 3PL .xlsx')
    sku_alias = forms.FileField(label='Alias SKU (sku_alias_zoho.csv)')
    sku_old = forms.FileField(label='SKU dismessi (sku_old.csv)')
    batch_notes = forms.FileField(label='Note sui lotti (batch_notes.csv)')
