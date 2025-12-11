import os
import psycopg2
import pandas as pd


DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL is missing — add it to .env!")

DATA_DIR = os.path.join(os.path.dirname(__file__), "sql", "data")

def load(table, cols, filename, cur, conn):
    print(f"Importing {filename} → {table}")
    path = os.path.join(DATA_DIR, filename)
    df = pd.read_csv(path)

    for col in cols:
        if col not in df.columns:
            raise RuntimeError(f"CSV {filename} is missing column: {col}")

    for _, row in df.iterrows():
        vals = [row[c] for c in cols]
        placeholders = ",".join(["%s"] * len(vals))
        cur.execute(
            f"INSERT INTO {table} ({','.join(cols)}) VALUES ({placeholders});",
            vals
        )

    conn.commit()
    print(f"✔ {len(df)} rows imported.\n")


def main():
    print("Connecting...")
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    print("Connected.\n")

    load("locales", ["locale_code", "description"], "locales.csv", cur, conn)
    load("names", ["locale_code", "first_name", "last_name", "gender"], "names.csv", cur, conn)
    load("street_names", ["locale_code", "street"], "street_names.csv", cur, conn)
    load("cities", ["locale_code", "city", "region", "postcode_pattern"], "cities.csv", cur, conn)
    load("phone_formats", ["locale_code", "fmt"], "phone_formats.csv", cur, conn)
    load("email_domains", ["locale_code", "domain"], "email_domains.csv", cur, conn)

    cur.close()
    conn.close()
    print("DONE.")

if __name__ == "__main__":
    main()
