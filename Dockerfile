# CIAR-Mali — image de production (FastAPI + interface Flutter Web déjà compilée)
#
# L'interface est compilée en local (flutter build web --release --base-href /app/)
# puis versionnée dans frontend/build/web : l'image reste légère et le déploiement
# ne dépend pas du SDK Flutter côté hébergeur.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Dépendances Python (couche mise en cache par Docker)
COPY backend/requirements.txt backend/requirements.txt
RUN pip install --no-cache-dir -r backend/requirements.txt

# Code de l'API et interface compilée
COPY backend backend
COPY frontend/build/web frontend/build/web

# La base de démonstration locale ne doit jamais partir en production.
RUN rm -f backend/edt.db backend/.env

ENV PORT=8000
EXPOSE 8000

CMD ["sh", "-c", "uvicorn app.main:app --app-dir backend --host 0.0.0.0 --port ${PORT}"]
