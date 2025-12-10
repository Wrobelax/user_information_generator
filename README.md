# Book Sales Analysis

___

## **Project description**
This project implements a Faker-style generator where all randomization and data generation happen entirely inside PostgreSQL stored procedures.
The Python/Streamlit frontend only triggers SQL functions and displays the results.

The generator produces deterministic, reproducible batches of fake users with:

* Full name
* Locale-aware address
* Geolocation (uniformly distributed on the sphere)
* Physical attributes (normal distribution)
* Email address
* Phone number (locale formatting)
* Deterministic output depending only on:
  * locale, seed, batch index, index inside batch
___

## *Project Structure*
```
user_information_generator/
|
├── sql/
│   ├── schema.sql               # tables (names, streets, cities itd.)
│   ├── data/
│   │   ├── names_en.csv
│   │   ├── names_pl.csv
│   │   ├── streets_pl.csv
│   │   ├── streets_en.csv
│   │   ├── cities_pl.csv
│   │   ├── cities_en.csv
│   │   ├── phone_formats.sql
│   │   ├── email_domains.sql
│   │
│   └── functions.sql            # RNG, generate_user, generate_batch
├── app.py                       # Frontend dashboard and main script for app running.
├── benchmark.py                 # Script used for counting benchmark of SQL database.
├── requirements.txt
└── db.py                        # Script used for connecting into database.
```
___

## *Overview*
The system consists of:
1. PostgreSQL stored procedures (core logic):

    All randomness, formatting, data selection, and record generation is done exclusively in SQL.

1. Lookup tables

    Large data tables for names, streets, cities, phone_formats, email_domains, for both locales:

    * pl_PL (Polish)
    * en_US (United States)

1. Python + Streamlit frontend

   * Locale selection
   * Seed input
   * Batch navigation
   * Presentation layer
   * Python performs no randomization.

1. Deterministic RNG

   * Custom 53-bit masked RNG based on:

     * md5(locale | seed | batch | idx) → initial state
     * bitwise mixing
     * masking to 53 bits (matching IEEE754 mantissa size)

___

## *Database schema*
1. locales
```bash
locale_code TEXT PRIMARY KEY
locale_name TEXT
en_US; pl_PL
```
2. names
```bash
id (SERIAL)
locale_code
first_name
last_name
31800 records
```
3. street_names
```bash
id
locale_code
street
226 records

```
4. cities
```bash
id
locale_code
city
region
postcode_pattern (e.g. "##-###" or "#####")
201 records
```
5. phone_formats
```bash
id
locale_code
fmt (e.g. "+1 (###) ###-####")
11 records
```
6. email_domains
```bash
id
locale_code
domain
17 records
```

___

## *Algorithms used*

### 1.Deterministic RNG (53-bit masked PRNG):
Mentioned algorithm was used as the most safe, stable and not causing overflow as i.e. SplitMix64 (tested).

* Initial state derivation:
```bash
md5(locale | seed | batch | idx)
first 14 hex chars -> 56 bits
cast to bigint
mask to 53 bits
```
* Mixing using xorshift-style:
```bash
st = st XOR (st << 21)
st = st XOR (st >> 17)
st = st XOR (st << 13)
mask after each step
```
* Converting to float:
```bash
uniform = st / 2^53
```
This matches the mantissa width of IEEE754 double precision which is stable and reproducible.


### 2.Uniform distribution on the sphere:
* Generating
```bash
u1 = rng_uniform(...)
u2 = rng_uniform(...)
```
* Latitude and longitude:
```bash
lat = degrees(asin(2u1 - 1))
lon = degrees(2π * u2) - 180
```
This yields constant PDF on the sphere, unlike uniform(-90,90).
### 3. Run pipeline:
```bash
python pipeline.py
```

### 4. Normal distribution (Box-Muller):
* Used for height and weight:
```bash
z = sqrt(-2 ln(u1)) * cos(2π u2)
return mean + stddev * z
```
Locale-specific:
* pl_PL: mean 170 cm, sd 8; mean 75 kg, sd 12
* en_US: mean 175 cm, sd 10; mean 80 kg, sd 14

### 5. Name generator:
* Randomly select first and last name:
```bash
OFFSET rng_int_from(...)
```

### 5. Address generator:
* For pl_PL:
```bash
ul. {street} {number}, {postcode} {city}
```
* For en_US:
```bash
{number} {street} St., {city}, {region}
```

### 6. Phone number generator:
* Depending on a format, every # replaced by deterministic RNG digit:
```bash
e.g. +1 (###) ###-####
```

### 6. Email generator:
* Special characters transformed using translit(). Formats include:
```bash
firstname.lastname###@domain
firstname.lastname@domain
firstname###@domain
lastname###@domain
```
 
___

c

Used for:
* latitude
* longitude
* random selections
* normal distribution generation
```bash
CREATE OR REPLACE FUNCTION rng_uniform(
  p_locale text,
  p_seed bigint,
  p_batch bigint,
  p_idx bigint
) RETURNS double precision
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  raw_md5 text;
  st bigint;
  mask bigint := ((1::bigint << 53) - 1); -- 53-bit mask
BEGIN
  raw_md5 := md5(p_locale || '|' || p_seed::text || '|' || p_batch::text || '|' || p_idx::text);
  -- take first 14 hex chars -> up to 56 bits, cast, then mask to 53
  st := ('x' || substr(raw_md5,1,14))::bit(56)::bigint & mask;
  IF st = 0 THEN st := 1; END IF;

  -- mix deterministically (masked to 53 bits each step)
  st := (st # ((st << 21) & mask)) & mask;
  st := (st # ((st >> 17) & mask)) & mask;
  st := (st # ((st << 13) & mask)) & mask;
  IF st = 0 THEN st := 1; END IF;

  RETURN st::double precision / 9007199254740992.0; -- 2^53
END;
```

### 2. rng_int_from(locale, seed, batch, idx, a, b):
Returns integer in range [a,b].

```bash
CREATE OR REPLACE FUNCTION rng_int_from(
  p_locale text,
  p_seed bigint,
  p_batch bigint,
  p_idx bigint,
  p_a int,
  p_b int
) RETURNS int
LANGUAGE sql IMMUTABLE AS $$
  SELECT p_a + floor(rng_uniform(p_locale, p_seed, p_batch, p_idx) * (p_b - p_a + 1))::int;
```

### 3. rng_normal(locale, seed, batch, idx, mean, std):
Normal distribution via Box–Muller.

```bash
CREATE OR REPLACE FUNCTION rng_normal(
  p_locale text,
  p_seed bigint,
  p_batch bigint,
  p_idx bigint,
  p_mean double precision,
  p_std double precision
) RETURNS double precision
LANGUAGE sql IMMUTABLE AS $$
  SELECT p_mean + p_std *
    ( sqrt(-2.0 * ln(GREATEST(rng_uniform(p_locale,p_seed,p_batch,p_idx),1e-15)))
      * cos(2.0 * pi() * rng_uniform(p_locale,p_seed,p_batch,p_idx+1)) );
```

### 4. translit(text):
Used to transform Polish letters into ASCII.

```bash
CREATE OR REPLACE FUNCTION translit(p_text text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT translate(p_text,
    'ąćęłńóśźżĄĆĘŁŃÓŚŹŻ',
    'acelnoszzACELNOSZZ');
```

### 5. generate_user(locale,seed,batch,idx):
Generate one user with all data.

```bash
CREATE OR REPLACE FUNCTION generate_user(
  p_locale text,
  p_seed bigint,
  p_batch bigint,
  p_idx int
)
RETURNS TABLE (
  locale_out text,
  seed_out bigint,
  batch_out bigint,
  idx_out int,
  full_name text,
  address text,
  lat double precision,
  lon double precision,
  height_cm double precision,
  weight_kg double precision,
  phone text,
  email text
) LANGUAGE plpgsql AS $$
DECLARE
  base_idx bigint := p_idx::bigint * 100;
  c int;
  pick int;
  fn text; ln text;
  street text; street_num int; city text; region text; postcode text;
  phone_fmt text; domain text;
  u double precision;
  normv double precision;
BEGIN
  -- FULL NAME (choose by offset)
  SELECT count(*) INTO c FROM names n WHERE n.locale_code = p_locale;
  IF c = 0 THEN
    fn := 'Sam'; ln := 'User';
  ELSE
    pick := rng_int_from(p_locale, p_seed, p_batch, base_idx + 1, 1, c);
    SELECT n.first_name, n.last_name INTO fn, ln
    FROM names n
    WHERE n.locale_code = p_locale
    ORDER BY n.id
    LIMIT 1 OFFSET (pick - 1);
  END IF;
  full_name := fn || ' ' || ln;

  -- STREET
  SELECT count(*) INTO c FROM street_names sn WHERE sn.locale_code = p_locale;
  IF c = 0 THEN street := 'Main'; ELSE
    pick := rng_int_from(p_locale, p_seed, p_batch, base_idx + 2, 1, c);
    SELECT sn.street INTO street FROM street_names sn WHERE sn.locale_code = p_locale ORDER BY sn.id LIMIT 1 OFFSET (pick - 1);
  END IF;
  street_num := rng_int_from(p_locale, p_seed, p_batch, base_idx + 3, 1, 9999);

  -- CITY
  SELECT count(*) INTO c FROM cities ci WHERE ci.locale_code = p_locale;
  IF c = 0 THEN city := 'City'; region := ''; postcode := ''; ELSE
    pick := rng_int_from(p_locale, p_seed, p_batch, base_idx + 4, 1, c);
    SELECT ci.city, ci.region, ci.postcode_pattern INTO city, region, postcode FROM cities ci WHERE ci.locale_code = p_locale ORDER BY ci.id LIMIT 1 OFFSET (pick - 1);
  END IF;

  -- postcode: replace '#' with digits
  IF postcode IS NULL THEN postcode := ''; END IF;
  IF postcode <> '' THEN
    FOR i IN 1..char_length(postcode) LOOP
      IF substring(postcode,i,1) = '#' THEN
        pick := rng_int_from(p_locale, p_seed, p_batch, base_idx + 5 + i, 0, 9);
        postcode := overlay(postcode placing pick::text from i for 1);
      END IF;
    END LOOP;
  END IF;

  IF p_locale = 'pl_PL' THEN
    address := 'ul. ' || street || ' ' || street_num::text || CASE WHEN postcode <> '' THEN ', ' || postcode ELSE '' END || ' ' || city;
  ELSE
    address := street_num::text || ' ' || street || ' St., ' || city || CASE WHEN region <> '' THEN ', ' || region ELSE '' END;
  END IF;

  -- GEOLOCATION (uniform on sphere)
  u := rng_uniform(p_locale, p_seed, p_batch, base_idx + 20);
  lat := degrees(asin(2.0 * u - 1.0));
  u := rng_uniform(p_locale, p_seed, p_batch, base_idx + 21);
  lon := degrees(u * 2.0 * pi()) - 180.0;

  -- PHYSICAL ATTRIBUTES (normal distribution)
  IF p_locale = 'pl_PL' THEN
    height_cm := round(rng_normal(p_locale, p_seed, p_batch, base_idx + 30, 170.0, 8.0)::numeric, 2);
    weight_kg := round(rng_normal(p_locale, p_seed, p_batch, base_idx + 32, 75.0, 12.0)::numeric, 2);
  ELSE
    height_cm := round(rng_normal(p_locale, p_seed, p_batch, base_idx + 30, 175.0, 10.0)::numeric, 2);
    weight_kg := round(rng_normal(p_locale, p_seed, p_batch, base_idx + 32, 80.0, 14.0)::numeric, 2);
  END IF;

  -- PHONE
  SELECT count(*) INTO c FROM phone_formats pf WHERE pf.locale_code = p_locale;
  IF c = 0 THEN phone := ''; ELSE
    pick := rng_int_from(p_locale, p_seed, p_batch, base_idx + 40, 1, c);
    SELECT pf.fmt INTO phone_fmt FROM phone_formats pf WHERE pf.locale_code = p_locale ORDER BY pf.id LIMIT 1 OFFSET (pick - 1);
    phone := phone_fmt;
    FOR i IN 1..char_length(phone_fmt) LOOP
      IF substring(phone_fmt,i,1) = '#' THEN
        pick := rng_int_from(p_locale, p_seed, p_batch, base_idx + 41 + i, 0, 9);
        phone := overlay(phone placing pick::text from i for 1);
      END IF;
    END LOOP;
  END IF;

  -- EMAIL
  SELECT count(*) INTO c FROM email_domains ed WHERE ed.locale_code = p_locale;
  IF c = 0 THEN domain := 'example.com'; ELSE
    pick := rng_int_from(p_locale, p_seed, p_batch, base_idx + 60, 1, c);
    SELECT ed.domain INTO domain FROM email_domains ed WHERE ed.locale_code = p_locale ORDER BY ed.id LIMIT 1 OFFSET (pick - 1);
  END IF;

  email := lower(regexp_replace(translit(fn),'[^A-Za-z0-9]','','g') || '.' ||
                 regexp_replace(translit(ln),'[^A-Za-z0-9]','','g') ||
                 floor(rng_uniform(p_locale, p_seed, p_batch, base_idx + 70) * 1000)::text ||
                 '@' || domain);

  -- output
  locale_out := p_locale;
  seed_out := p_seed;
  batch_out := p_batch;
  idx_out := p_idx;
  RETURN NEXT;
END;
```

### 6. generate_batch(locale, seed, batch, size):
Generate size users

```bash
REATE OR REPLACE FUNCTION generate_batch(
    p_locale text,
    p_seed bigint,
    p_batch bigint,
    p_size int
)
RETURNS TABLE (
    locale_out text,
    seed_out bigint,
    batch_out bigint,
    idx_out int,
    full_name text,
    address text,
    lat double precision,
    lon double precision,
    height_cm double precision,
    weight_kg double precision,
    phone text,
    email text
)
LANGUAGE plpgsql AS $$
DECLARE
    i int;
BEGIN
    IF p_size <= 0 THEN
        RAISE EXCEPTION 'batch size must be > 0';
    END IF;

    FOR i IN 0..(p_size - 1) LOOP
        RETURN QUERY SELECT * FROM generate_user_safe(p_locale, p_seed, p_batch, i);
    END LOOP;

    RETURN;
END;
```

## *Determinism and reproducibility*

The output is deterministic besing exclusively on: locale, seed, batch, index. Changing any of them changes the output and setting the same combination always yiel;ds identical values.
RNG is custom, deterministic and masked, no SQL non-deterministic functions are used and functions are declared immutable if possible.

___

## *Benchmark*
Included tool in benchmark.py that measures throughput by generating 10,000 users via SQL.
Example result:
```bash
Benchmark start:
- locale: en_US
- seed: 42
- batch size: 100
- total users: 10000
- batches: 100

Batch 0/100 done
Batch 10/100 done
Batch 20/100 done
Batch 30/100 done
Batch 40/100 done
Batch 50/100 done
Batch 60/100 done
Batch 70/100 done
Batch 80/100 done
Batch 90/100 done

Benchmark complete:
Total users generated: 10000
Total time: 56.6001 sec
Throughput: 176.68 users/sec

```
___