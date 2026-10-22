# Kitatool Save: download server for kitatool.com/save
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -U -r requirements.txt
COPY server.py .
ENV PYTHONUNBUFFERED=1
EXPOSE 8080
CMD ["python", "server.py"]
