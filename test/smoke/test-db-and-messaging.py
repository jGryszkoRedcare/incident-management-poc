# tests/smoke/test_services.py  ← append to the file we created earlier
import os
import socket
import pytest
import uuid, time
# PostgreSQL imports
import psycopg2
# Kafka imports
from kafka import KafkaAdminClient
from kafka.admin import KafkaAdminClient, NewTopic
from kafka import KafkaProducer, KafkaConsumer
# ---------------------------------------------------------------------------
# 1. PostgreSQL: does it accept a connection and answer 'SELECT 1'?
# ---------------------------------------------------------------------------
@pytest.mark.smoke
def test_postgresql_alive():
    conn = psycopg2.connect(
        host="postgresql",
        user=os.getenv("POSTGRES_USER", "root"),
        password=os.getenv("POSTGRES_PASSWORD", "otel"),
        dbname=os.getenv("POSTGRES_DB", "otel"),
        connect_timeout=5,
    )
    with conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1;")
            assert cur.fetchone() == (1,)

# ---------------------------------------------------------------------------
# 2. Kafka: can we fetch cluster metadata?
# ---------------------------------------------------------------------------
@pytest.mark.smoke
def test_kafka_roundtrip():
    BOOTSTRAP = ["kafka:9092"]
    admin = KafkaAdminClient(bootstrap_servers=BOOTSTRAP, request_timeout_ms=5000)

    # 1 ── create a throw‑away topic
    topic = f"smoke_{uuid.uuid4().hex[:8]}"
    admin.create_topics([NewTopic(name=topic, num_partitions=1, replication_factor=1)])

    try:
        # 2 ── produce a message
        producer = KafkaProducer(
            bootstrap_servers=BOOTSTRAP, 
            value_serializer=lambda v: v.encode("utf-8"),
        )
            
        payload = "hello‑smoke"
        producer.send(topic, value=payload)
        producer.flush(5)                     # wait ≤5 s for the broker to ack

        # 3 ── consume it back
        
        consumer = KafkaConsumer(
            topic,
            bootstrap_servers=BOOTSTRAP,
            auto_offset_reset="earliest",     # start from offset 0 even for a new group
            value_deserializer=lambda b: b.decode("utf-8"),
            consumer_timeout_ms=3000,         # give up after 3 s if nothing arrives
        )
        msgs = [m.value for m in consumer]

        assert payload in msgs, "Produced message never came back"
        print(f"Kafka round‑trip OK: {msgs[0]!r}")

    finally:
        # 4 ── tidy up (ignore 'unknown topic' errors if the broker auto‑deleted already)
        try:
            admin.delete_topics([topic])
        except Exception:
            pass
