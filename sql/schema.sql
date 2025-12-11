------------------------------------------------------------
-- TABLE: locales
------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.locales (
    locale_code text NOT NULL PRIMARY KEY,
    description text
);


------------------------------------------------------------
-- TABLE: names
------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.names (
    id SERIAL PRIMARY KEY,
    locale_code text REFERENCES public.locales(locale_code),
    first_name text,
    last_name text,
    gender text
);


------------------------------------------------------------
-- TABLE: street_names
------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.street_names (
    id SERIAL PRIMARY KEY,
    locale_code text REFERENCES public.locales(locale_code),
    street text
);


------------------------------------------------------------
-- TABLE: cities
------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.cities (
    id SERIAL PRIMARY KEY,
    locale_code text REFERENCES public.locales(locale_code),
    city text,
    region text,
    postcode_pattern text
);


------------------------------------------------------------
-- TABLE: phone_formats
------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.phone_formats (
    id SERIAL PRIMARY KEY,
    locale_code text REFERENCES public.locales(locale_code),
    fmt text
);


------------------------------------------------------------
-- TABLE: email_domains
------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.email_domains (
    id SERIAL PRIMARY KEY,
    locale_code text REFERENCES public.locales(locale_code),
    domain text
);
