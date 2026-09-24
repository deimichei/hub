from django.urls import path

from . import views

app_name = 'confronto'

urlpatterns = [
    path('', views.risultati, name='risultati'),
    path('nuovo/', views.nuovo, name='nuovo'),
]
