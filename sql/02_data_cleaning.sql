USE olist_db;

-- 1) category clean 컬럼 추가
ALTER TABLE category_names_english
ADD COLUMN clean_category VARCHAR(100);

UPDATE category_names_english
SET clean_category = LOWER(
    TRIM(
        REPLACE(
            REPLACE(product_category_eng, '\r', ''),
            '\n', ''
        )
    )
);

-- 2) category_group 컬럼 추가
ALTER TABLE category_names_english
ADD COLUMN category_group VARCHAR(50);

UPDATE category_names_english
SET category_group = CASE
    WHEN clean_category IN ('food', 'drinks', 'food_drink')
        THEN 'Food & Beverage'

    WHEN clean_category IN (
        'computers',
        'computers_accessories',
        'tablets_printing_image',
        'telephony',
        'fixed_telephony',
        'audio',
        'electronics',
        'home_appliances',
        'home_appliances_2',
        'small_appliances',
        'small_appliances_home_oven_and_coffee',
        'air_conditioning',
        'consoles_games',
        'cine_photo'
    )
        THEN 'Electronics & Digital'

    WHEN clean_category IN (
        'fashion_shoes',
        'fashion_bags_accessories',
        'fashion_male_clothing',
        'fashio_female_clothing',
        'fashion_underwear_beach',
        'fashion_sport',
        'fashion_childrens_clothes',
        'luggage_accessories',
        'watches_gifts'
    )
        THEN 'Fashion & Accessories'

    WHEN clean_category IN (
        'furniture_bedroom',
        'furniture_living_room',
        'furniture_decor',
        'furniture_mattress_and_upholstery',
        'home_confort',
        'home_comfort_2',
        'home_construction',
        'housewares',
        'kitchen_dining_laundry_garden_furniture',
        'bed_bath_table',
        'garden_tools',
        'office_furniture',
        'la_cuisine'
    )
        THEN 'Home & Living'

    WHEN clean_category IN (
        'health_beauty',
        'perfumery',
        'diapers_and_hygiene'
    )
        THEN 'Beauty & Health'

    WHEN clean_category IN (
        'sports_leisure',
        'toys',
        'cool_stuff'
    )
        THEN 'Sports & Leisure'

    WHEN clean_category IN (
        'books_general_interest',
        'books_technical',
        'books_imported',
        'cds_dvds_musicals',
        'dvds_blu_ray',
        'music',
        'musical_instruments',
        'art',
        'arts_and_craftmanship',
        'stationery'
    )
        THEN 'Books & Media'

    WHEN clean_category IN ('baby')
        THEN 'Baby & Kids'

    WHEN clean_category IN (
        'auto',
        'agro_industry_and_commerce',
        'industry_commerce_and_business',
        'construction_tools_construction',
        'construction_tools_lights',
        'construction_tools_safety',
        'costruction_tools_garden',
        'costruction_tools_tools',
        'signaling_and_security',
        'security_and_services'
    )
        THEN 'Auto & Industrial'

    WHEN clean_category IN (
        'pet_shop',
        'flowers',
        'christmas_supplies',
        'party_supplies',
        'market_place'
    )
        THEN 'Others'

    ELSE 'Others'
END;

-- 3) customers city 정제 컬럼 추가
ALTER TABLE customers
ADD COLUMN clean_city VARCHAR(100);

UPDATE customers
SET clean_city = LOWER(TRIM(REPLACE(city, '''', ' ')));

-- 4) 최소 검증
SELECT
    zip_code_prefix,
    COUNT(DISTINCT city) AS raw_city_cnt,
    COUNT(DISTINCT clean_city) AS clean_city_cnt,
    COUNT(DISTINCT state) AS state_cnt,
    COUNT(*) AS row_cnt
FROM customers
GROUP BY zip_code_prefix
HAVING COUNT(DISTINCT city) > 1
ORDER BY raw_city_cnt DESC
LIMIT 10;

SELECT DISTINCT city, state
FROM customers
WHERE zip_code_prefix = '45816';

SELECT DISTINCT clean_city
FROM customers
WHERE zip_code_prefix = '45816';