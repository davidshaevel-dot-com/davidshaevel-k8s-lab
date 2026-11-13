FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /srv

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY labapp ./labapp

RUN useradd --uid 10001 --no-create-home labapp
USER 10001

EXPOSE 8080
CMD ["gunicorn", "--preload", "--bind", "0.0.0.0:8080", "--workers", "2", "--access-logfile", "-", "labapp.wsgi:app"]
