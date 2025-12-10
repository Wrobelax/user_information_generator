"""
Script for benchmarking SQL database latency.
"""

import psycopg2
import time
import os
from dotenv import load_dotenv

load_dotenv()

# CONFIGURATION
LOCALE = "en_US"
SEED = 42
BATCH_SIZE = 100        # users per batch
TOTAL_USERS = 10000     # target users
CONNECTION_STRING = os.getenv("DATABASE_URL")

def benchmark():
    conn = psycopg2.connect(CONNECTION_STRING)
    cur = conn.cursor()

    batches = TOTAL_USERS // BATCH_SIZE

    print(f"Benchmark start:")
    print(f"- locale: {LOCALE}")
    print(f"- seed: {SEED}")
    print(f"- batch size: {BATCH_SIZE}")
    print(f"- total users: {TOTAL_USERS}")
    print(f"- batches: {batches}\n")

    start = time.time()

    total_generated = 0

    for batch_idx in range(batches):
        cur.execute(
            "SELECT * FROM generate_batch(%s, %s, %s, %s);",
            (LOCALE, SEED, batch_idx, BATCH_SIZE)
        )
        rows = cur.fetchall()
        total_generated += len(rows)

        # optional: print progress every 10 batches
        if batch_idx % 10 == 0:
            print(f"Batch {batch_idx}/{batches} done")

    end = time.time()
    elapsed = end - start

    users_per_sec = total_generated / elapsed

    print("\nBenchmark complete:")
    print(f"Total users generated: {total_generated}")
    print(f"Total time: {elapsed:.4f} sec")
    print(f"Throughput: {users_per_sec:.2f} users/sec")

    cur.close()
    conn.close()


if __name__ == "__main__":
    benchmark()
