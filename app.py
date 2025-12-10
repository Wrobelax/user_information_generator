"""
Script for generating frontend via Streamlit.
"""

import streamlit as st
from dotenv import load_dotenv
import db
from db import fetch_batch

load_dotenv()

st.set_page_config(page_title="User Generator", layout="wide")

st.title("User Generator")

if "batch_idx" not in st.session_state:
    st.session_state.batch_idx = 0

st.sidebar.header("Generator Settings")

locale = st.sidebar.selectbox("Locale", ["en_US", "pl_PL"])
seed = st.sidebar.number_input("Seed", min_value=0, value=42, step=1)
batch_size = st.sidebar.number_input("Batch size", min_value=1, value=10, step=1)

if st.sidebar.button("Generate"):
    st.session_state.batch_idx = 0

if st.sidebar.button("Next batch"):
    st.session_state.batch_idx += 1

try:
    df = fetch_batch(locale, seed, st.session_state.batch_idx, batch_size)
    df.index = df.index + 1
    st.dataframe(df, width="stretch")
except Exception as e:
    st.error(f"Database error: {e}")


st.markdown("---")
st.header("Benchmark")

locale_bench = st.selectbox("Locale for benchmark", ["en_US", "pl_PL"], key="bench_locale")
seed_bench = st.number_input("Seed", value=42, key="bench_seed")
batch_size_bench = st.number_input("Batch size", value=100, min_value=10, max_value=1000, step=10, key="bench_batch")
total_users_bench = st.number_input("Total users", value=10000, min_value=1000, max_value=500000, step=1000, key="bench_total")

if st.button("Run Benchmark"):
    st.write("Running benchmark... please wait.")
    result = db.run_benchmark(
        locale=locale_bench,
        seed=int(seed_bench),
        batch_size=int(batch_size_bench),
        total_users=int(total_users_bench)
    )

    st.success("Benchmark completed!")

    st.write(f"**Total users generated:** {result['total_users']}")
    st.write(f"**Total time:** {result['total_time']:.4f} seconds")
    st.write(f"**Throughput:** {result['users_per_sec']:.2f} users/sec")
