-- data.sql — load lookup data from GitHub CSV files

-- 1. optional: clear existing data
TRUNCATE TABLE
    public.email_domains,
    public.phone_formats,
    public.cities,
    public.street_names,
    public.names,
    public.locales
CASCADE;

-- 2. load locales
COPY public.locales(locale_code, description)
FROM 'https://raw.githubusercontent.com/Wrobelax/user_information_generator/main/data/locales.csv'
WITH (FORMAT csv, HEADER true);

-- 3. load names
COPY public.names(locale_code, first_name, last_name, gender)
FROM 'https://raw.githubusercontent.com/Wrobelax/user_information_generator/main/data/names.csv'
WITH (FORMAT csv, HEADER true);

-- 4. load street names
COPY public.street_names(locale_code, street)
FROM 'https://raw.githubusercontent.com/Wrobelax/user_information_generator/main/data/street_names.csv'
WITH (FORMAT csv, HEADER true);

-- 5. load cities
COPY public.cities(locale_code, city, region, postcode_pattern)
FROM 'https://raw.githubusercontent.com/Wrobelax/user_information_generator/main/data/cities.csv'
WITH (FORMAT csv, HEADER true);

-- 6. load phone formats
COPY public.phone_formats(locale_code, fmt)
FROM 'https://raw.githubusercontent.com/Wrobelax/user_information_generator/main/data/phone_formats.csv'
WITH (FORMAT csv, HEADER true);

-- 7. load email domains
COPY public.email_domains(locale_code, domain)
FROM 'https://raw.githubusercontent.com/Wrobelax/user_information_generator/main/data/email_domains.csv'
WITH (FORMAT csv, HEADER true);
