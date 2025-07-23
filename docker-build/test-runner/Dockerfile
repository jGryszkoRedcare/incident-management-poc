FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    LANG=C.UTF-8

# Install base system tools
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      bash \
      git \
      ca-certificates \
      netcat-traditional \
    && rm -rf /var/lib/apt/lists/*

# Install Python requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Default workspace for test mounts / execution
WORKDIR /workspace

# Idle until triggered by docker-compose run
CMD ["sleep", "infinity"]
