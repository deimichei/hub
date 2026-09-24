from django.urls import path

from . import views

app_name = 'confronto'

urlpatterns = [
    path('', views.pagina, name='pagina'),
]
