------------------------------------------------------------
-- rng_uniform: deterministic 53-bit uniform RNG
------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rng_uniform(
    p_locale text,
    p_seed bigint,
    p_batch bigint,
    p_idx bigint)
RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE PARALLEL UNSAFE
COST 100
AS $BODY$
DECLARE
  raw_md5 text;
  st bigint;
  mask bigint := ((1::bigint << 53) - 1);
BEGIN
  raw_md5 := md5(p_locale || '|' || p_seed::text || '|' || p_batch::text || '|' || p_idx::text);

  st := ('x' || substr(raw_md5,1,14))::bit(56)::bigint & mask;
  IF st = 0 THEN st := 1; END IF;

  st := (st # ((st << 21) & mask)) & mask;
  st := (st # ((st >> 17) & mask)) & mask;
  st := (st # ((st << 13) & mask)) & mask;
  IF st = 0 THEN st := 1; END IF;

  RETURN st::double precision / 9007199254740992.0;
END;
$BODY$;

GRANT EXECUTE ON FUNCTION public.rng_uniform(text, bigint, bigint, bigint) TO PUBLIC;


------------------------------------------------------------
-- rng_int_from: integer in [p_a, p_b]
------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rng_int_from(
    p_locale text,
    p_seed bigint,
    p_batch bigint,
    p_idx bigint,
    p_a integer,
    p_b integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE PARALLEL UNSAFE
COST 100
AS $BODY$
  SELECT p_a + floor(
        rng_uniform(p_locale, p_seed, p_batch, p_idx)
        * (p_b - p_a + 1)
    )::int;
$BODY$;

GRANT EXECUTE ON FUNCTION public.rng_int_from(text, bigint, bigint, bigint, integer, integer) TO PUBLIC;

------------------------------------------------------------
-- rng_normal: Box-Muller normal distribution
------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rng_normal(
    p_locale text,
    p_seed bigint,
    p_batch bigint,
    p_idx bigint,
    p_mean double precision,
    p_std double precision)
RETURNS double precision
LANGUAGE sql
IMMUTABLE PARALLEL UNSAFE
COST 100
AS $BODY$
  SELECT p_mean + p_std *
    ( sqrt(-2.0 * ln(GREATEST(rng_uniform(p_locale,p_seed,p_batch,p_idx),1e-15))) *
      cos(2.0 * pi() * rng_uniform(p_locale,p_seed,p_batch,p_idx+1)) );
$BODY$;

GRANT EXECUTE ON FUNCTION public.rng_normal(text, bigint, bigint, bigint, double precision, double precision) TO PUBLIC;


------------------------------------------------------------
-- translit: remove Polish diacritics
------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.translit(
    p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL UNSAFE
COST 100
AS $BODY$
  SELECT translate(
      p_text,
      'ąćęłńóśźżĄĆĘŁŃÓŚŹŻ',
      'acelnoszzACELNOSZZ'
  );
$BODY$;

GRANT EXECUTE ON FUNCTION public.translit(text) TO PUBLIC;


------------------------------------------------------------
-- generate_user_safe: deterministic user generator
------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.generate_user_safe(
    p_locale text,
    p_seed bigint,
    p_batch bigint,
    p_idx integer)
RETURNS TABLE(
    locale_out text,
    seed_out bigint,
    batch_out bigint,
    idx_out integer,
    full_name text,
    address text,
    lat double precision,
    lon double precision,
    height_cm double precision,
    weight_kg double precision,
    phone text,
    email text
)
LANGUAGE plpgsql
VOLATILE PARALLEL UNSAFE
COST 100
ROWS 1000
AS $BODY$
DECLARE
  base_idx bigint := p_idx::bigint * 100;
  c int;
  pick int;
  fn text; ln text;
  street text; street_num int; city text; region text; postcode text;
  phone_fmt text; domain text;
  u double precision;
BEGIN
  SELECT count(*) INTO c FROM names n WHERE n.locale_code = p_locale;
  IF c = 0 THEN
    fn := 'Sam'; ln := 'User';
  ELSE
    pick := rng_int_from(p_locale, p_seed, p_batch, base_idx + 1, 1, c);
    SELECT n.first_name, n.last_name
      INTO fn, ln
    FROM names n
    WHERE n.locale_code = p_locale
    ORDER BY n.id
    LIMIT 1 OFFSET (pick - 1);
  END IF;

  full_name := fn || ' ' || ln;

  SELECT count(*) INTO c FROM street_names sn WHERE sn.locale_code = p_locale;
  IF c = 0 THEN street := 'Main';
  ELSE
    pick := rng_int_from(p_locale, p_seed, p_batch, base_idx + 2, 1, c);
    SELECT sn.street INTO street
    FROM street_names sn
    WHERE sn.locale_code = p_locale
    ORDER BY sn.id
    LIMIT 1 OFFSET (pick - 1);
  END IF;

  street_num := rng_int_from(p_locale, p_seed, p_batch, base_idx + 3, 1, 9999);

  SELECT count(*) INTO c FROM cities ci WHERE ci.locale_code = p_locale;
  IF c = 0 THEN
    city := 'City'; region := ''; postcode := '';
  ELSE
    pick := rng_int_from(p_locale, p_seed, p_batch, base_idx + 4, 1, c);
    SELECT ci.city, ci.region, ci.postcode_pattern
      INTO city, region, postcode
    FROM cities ci
    WHERE ci.locale_code = p_locale
    ORDER BY ci.id
    LIMIT 1 OFFSET (pick - 1);
  END IF;

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
    address := 'ul. ' || street || ' ' || street_num::text ||
               CASE WHEN postcode <> '' THEN ', ' || postcode ELSE '' END ||
               ' ' || city;
  ELSE
    address := street_num::text || ' ' || street || ' St., ' || city ||
               CASE WHEN region <> '' THEN ', ' || region ELSE '' END;
  END IF;

  u := rng_uniform(p_locale, p_seed, p_batch, base_idx + 20);
  lat := degrees(asin(2.0 * u - 1.0));

  u := rng_uniform(p_locale, p_seed, p_batch, base_idx + 21);
  lon := degrees(u * 2.0 * pi()) - 180.0;

  IF p_locale = 'pl_PL' THEN
    height_cm := round(rng_normal(p_locale, p_seed, p_batch, base_idx + 30, 170.0, 8.0)::numeric, 2);
    weight_kg := round(rng_normal(p_locale, p_seed, p_batch, base_idx + 32, 75.0, 12.0)::numeric, 2);
  ELSE
    height_cm := round(rng_normal(p_locale, p_seed, p_batch, base_idx + 30, 175.0, 10.0)::numeric, 2);
    weight_kg := round(rng_normal(p_locale, p_seed, p_batch, base_idx + 32, 80.0, 14.0)::numeric, 2);
  END IF;

  SELECT count(*) INTO c FROM phone_formats pf WHERE pf.locale_code = p_locale;
  IF c = 0 THEN phone := '';
  ELSE
    pick := rng_int_from(p_locale, p_seed, p_batch, base_idx + 40, 1, c);
    SELECT pf.fmt INTO phone_fmt
    FROM phone_formats pf
    WHERE pf.locale_code = p_locale
    ORDER BY pf.id
    LIMIT 1 OFFSET (pick - 1);

    phone := phone_fmt;

    FOR i IN 1..char_length(phone_fmt) LOOP
      IF substring(phone_fmt,i,1) = '#' THEN
        pick := rng_int_from(p_locale, p_seed, p_batch, base_idx + 41 + i, 0, 9);
        phone := overlay(phone placing pick::text from i for 1);
      END IF;
    END LOOP;
  END IF;

  SELECT count(*) INTO c FROM email_domains ed WHERE ed.locale_code = p_locale;
  IF c = 0 THEN domain := 'example.com';
  ELSE
    pick := rng_int_from(p_locale, p_seed, p_batch, base_idx + 60, 1, c);
    SELECT ed.domain INTO domain
    FROM email_domains ed
    WHERE ed.locale_code = p_locale
    ORDER BY ed.id
    LIMIT 1 OFFSET (pick - 1);
  END IF;

  email :=
      lower(regexp_replace(translit(fn),'[^A-Za-z0-9]','','g'))
      || '.'
      || lower(regexp_replace(translit(ln),'[^A-Za-z0-9]','','g'))
      || floor(rng_uniform(p_locale,p_seed,p_batch,base_idx+70) * 1000)::text
      || '@' || domain;

  locale_out := p_locale;
  seed_out := p_seed;
  batch_out := p_batch;
  idx_out := p_idx;

  RETURN NEXT;
END;
$BODY$;

GRANT EXECUTE ON FUNCTION public.generate_user_safe(text, bigint, bigint, integer) TO PUBLIC;


------------------------------------------------------------
-- generate_batch (uses generate_user_safe)
------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.generate_batch(
    p_locale text,
    p_seed bigint,
    p_batch bigint,
    p_size integer)
RETURNS TABLE(
    locale_out text,
    seed_out bigint,
    batch_out bigint,
    idx_out integer,
    full_name text,
    address text,
    lat double precision,
    lon double precision,
    height_cm double precision,
    weight_kg double precision,
    phone text,
    email text)
LANGUAGE plpgsql
VOLATILE PARALLEL UNSAFE
COST 100
ROWS 1000
AS $BODY$
DECLARE i int;
BEGIN
    IF p_size <= 0 THEN
        RAISE EXCEPTION 'batch size must be > 0';
    END IF;

    FOR i IN 0..(p_size - 1) LOOP
        RETURN QUERY SELECT * FROM generate_user_safe(p_locale, p_seed, p_batch, i);
    END LOOP;

    RETURN;
END;
$BODY$;

GRANT EXECUTE ON FUNCTION public.generate_batch(text, bigint, bigint, integer) TO PUBLIC;
