FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    LANG=C.UTF-8

# system tools for docker socket and networking
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates iproute2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# copy source
COPY src/ ./src/

CMD ["python", "-m", "src.app"]