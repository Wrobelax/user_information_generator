import os
import psycopg2
import pandas as pd


def get_connection():
    db_url = os.getenv("DATABASE_URL")
    if not db_url:
        raise RuntimeError("Missing DATABASE_URL")
    return psycopg2.connect(db_url)


def fetch_batch(locale, seed, batch_idx, batch_size):
    conn = get_connection()
    query = """
        SELECT *
        FROM generate_batch(%s, %s, %s, %s);
    """
    cur = conn.cursor()
    cur.execute(query, (locale, int(seed), int(batch_idx), int(batch_size)))
    rows = cur.fetchall()
    cols = [desc[0] for desc in cur.description]
    cur.close()
    conn.close()
    return pd.DataFrame(rows, columns=cols)


def run_benchmark(locale="en_US", seed=42, batch_size=100, total_users=10000):
    import time
    conn = get_connection()
    cur = conn.cursor()

    batches = total_users // batch_size

    start = time.time()
    total_generated = 0

    for batch_idx in range(batches):
        cur.execute(
            "SELECT * FROM generate_batch(%s, %s, %s, %s);",
            (locale, seed, batch_idx, batch_size)
        )
        rows = cur.fetchall()
        total_generated += len(rows)

    end = time.time()

    cur.close()
    conn.close()

    return {
        "total_users": total_generated,
        "total_time": end - start,
        "users_per_sec": total_generated / (end - start)
    }
