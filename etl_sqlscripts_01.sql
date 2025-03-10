/*******************************************************************************
 * SQL SCRIPT: Company Data Migration & Transformation
 *
 * PURPOSE:
 * This script transforms raw company data from LinkedIn into a structured,
 * normalized data model with dimension tables for better data integrity
 * and analytics capabilities.
 *
 * PROCESS OVERVIEW:
 * 1. Create initial schema and data structures
 * 2. Add necessary columns and constraints
 * 3. Create dimension and junction tables for normalized data model
 * 4. Transform and load data into the normalized structure
 * 5. Remove redundant columns after transformation
 *
 * LAST UPDATED: 2025-03-05
 *******************************************************************************/

/*******************************************************************************
 * PHASE 1: INITIAL SCHEMA CREATION
 *******************************************************************************/

-- -----------------------------------------------------
-- Create the initial staging table for raw company data
-- This table will hold LinkedIn data before transformation
-- -----------------------------------------------------
CREATE TABLE company_raw (
    linkedin_internal_id VARCHAR(255),
    description TEXT,
    website VARCHAR(255),
    industry VARCHAR(255),
    company_size VARCHAR(50),
    company_size_on_linkedin VARCHAR(50),
    hq VARCHAR(255),
    company_type VARCHAR(255),
    founded_year VARCHAR(10),
    specialities TEXT,
    locations TEXT,
    name VARCHAR(255),
    tagline VARCHAR(255),
    universal_name_id VARCHAR(255),
    profile_pic_url VARCHAR(500),
    background_cover_image_url VARCHAR(500),
    search_id VARCHAR(255),
    similar_companies TEXT,
    affiliated_companies TEXT,
    updates TEXT,
    follower_count VARCHAR(50),
    acquisitions TEXT,
    exit_data TEXT,
    extra TEXT,
    funding_data TEXT,
    categories TEXT,
    customer_list TEXT
);

-- -----------------------------------------------------
-- Rename staging table to final table name
-- -----------------------------------------------------
ALTER TABLE company_raw RENAME TO company;

-- -----------------------------------------------------
-- Add primary key and additional columns for data normalization
-- -----------------------------------------------------
ALTER TABLE company
  ADD COLUMN company_id INT AUTO_INCREMENT PRIMARY KEY FIRST;

-- Add columns to store min/max company size values parsed from JSON
ALTER TABLE company
ADD COLUMN company_size_min VARCHAR(50) AFTER company_size,
ADD COLUMN company_size_max VARCHAR(50) AFTER company_size_min;

/*******************************************************************************
 * PHASE 2: CREATE DIMENSION AND JUNCTION TABLES
 * These tables will store normalized data extracted from the main company table
 *******************************************************************************/

-- -----------------------------------------------------
-- Create specialty dimension and junction table
-- Stores company specialties in a normalized form
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS specialty (
    specialty_name_id INT AUTO_INCREMENT PRIMARY KEY,
    specialty_name VARCHAR(255) NOT NULL
) ENGINE=INNODB;

CREATE TABLE IF NOT EXISTS company_specialty (
    unique_id INT AUTO_INCREMENT PRIMARY KEY,
    company_id INT NOT NULL,
    specialty_name_id INT NOT NULL,
    FOREIGN KEY (company_id) REFERENCES company(company_id),
    FOREIGN KEY (specialty_name_id) REFERENCES specialty(specialty_name_id),
    UNIQUE (company_id, specialty_name_id)
) ENGINE=INNODB;

-- -----------------------------------------------------
-- Create company type dimension and junction table
-- Normalizes company type information
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS type (
    company_type_id INT AUTO_INCREMENT PRIMARY KEY,
    company_type_name VARCHAR(255) NOT NULL
) ENGINE=INNODB;

CREATE TABLE IF NOT EXISTS company_type (
    unique_id INT AUTO_INCREMENT PRIMARY KEY,
    company_id INT NOT NULL,
    company_type_id INT NOT NULL,
    FOREIGN KEY (company_id) REFERENCES company(company_id),
    FOREIGN KEY (company_type_id) REFERENCES type(company_type_id),
    UNIQUE (company_id, company_type_id)
) ENGINE=INNODB;

-- -----------------------------------------------------
-- Create industry dimension and junction table
-- Normalizes industry information
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS industry (
    industry_id INT AUTO_INCREMENT PRIMARY KEY,
    industry_name VARCHAR(255) NOT NULL
) ENGINE=INNODB;

CREATE TABLE IF NOT EXISTS industry_type (
    unique_id INT AUTO_INCREMENT PRIMARY KEY,
    company_id INT NOT NULL,
    industry_id INT NOT NULL,
    FOREIGN KEY (company_id) REFERENCES company(company_id),
    FOREIGN KEY (industry_id) REFERENCES industry(industry_id),
    UNIQUE (company_id, industry_id)
) ENGINE=INNODB;

-- -----------------------------------------------------
-- Create locations table with one-to-many relationship to companies
-- Stores detailed location information for each company
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS locations (
    locations_id INT AUTO_INCREMENT PRIMARY KEY,
    company_id INT NOT NULL,
    country VARCHAR(255),
    city VARCHAR(255),
    postal_code VARCHAR(50),
    address_line1 VARCHAR(500),
    is_hq BOOLEAN DEFAULT FALSE,
    state VARCHAR(255),
    FOREIGN KEY (company_id) REFERENCES company(company_id)
) ENGINE=INNODB;

-- -----------------------------------------------------
-- Create tables for company updates and related companies
-- Stores social media updates and company relationships
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS company_updates (
    update_id INT AUTO_INCREMENT PRIMARY KEY,
    company_id INT NOT NULL,
    article_link VARCHAR(500) NOT NULL,
    image VARCHAR(500) NOT NULL, 
    posted_on DATE NOT NULL,
    update_text TEXT NOT NULL,
    total_likes INT NOT NULL,
    FOREIGN KEY (company_id) REFERENCES company(company_id),
    UNIQUE (update_id, company_id)
) ENGINE=INNODB;

CREATE TABLE IF NOT EXISTS affiliated_companies (
    affiliated_companies_id INT AUTO_INCREMENT PRIMARY KEY,
    company_id INT NOT NULL,
    name VARCHAR(500) NOT NULL, 
    linkedin_url VARCHAR(500) NOT NULL,
    industry VARCHAR(500) NOT NULL,
    location VARCHAR(500) NOT NULL,
    FOREIGN KEY (company_id) REFERENCES company(company_id),
    UNIQUE (affiliated_companies_id, company_id)
) ENGINE=INNODB;

CREATE TABLE IF NOT EXISTS similar_companies (
    similar_companies_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(500) NOT NULL, 
    linkedin_url VARCHAR(500) NOT NULL,
    industry VARCHAR(500) NOT NULL,
    location VARCHAR(500) NOT NULL
) ENGINE=INNODB;

CREATE TABLE IF NOT EXISTS similar_companies_junction (
    unique_id INT AUTO_INCREMENT PRIMARY KEY,
    similar_companies_id INT NOT NULL,
    company_id INT NOT NULL,
    FOREIGN KEY (company_id) REFERENCES company(company_id),
    FOREIGN KEY (similar_companies_id) REFERENCES similar_companies(similar_companies_id),
    UNIQUE (company_id, similar_companies_id)
) ENGINE=INNODB;

/*******************************************************************************
 * PHASE 3: DATA TRANSFORMATION AND LOADING
 * Extract data from JSON fields and load into normalized tables
 *******************************************************************************/

-- -----------------------------------------------------
-- Parse company size min/max values from JSON
-- -----------------------------------------------------
INSERT INTO company (company_size_min, company_size_max)
SELECT 
    JSON_EXTRACT(company_size, '$[0]') AS min_value,
    JSON_EXTRACT(company_size, '$[1]') AS max_value
FROM company;

-- -----------------------------------------------------
-- Extract and load specialty data
-- -----------------------------------------------------
-- Step 1: Insert unique specialties into dimension table
INSERT INTO specialty (specialty_name)
SELECT DISTINCT TRIM(jt.specialty)
FROM company cr
JOIN JSON_TABLE(
    cr.specialities,
    '$[*]'
    COLUMNS (
       specialty VARCHAR(255) PATH '$'
    )
) AS jt
WHERE cr.specialities IS NOT NULL
  AND TRIM(jt.specialty) <> ''
ON DUPLICATE KEY UPDATE specialty_name = specialty_name;

-- Step 2: Create relationships between companies and specialties
INSERT INTO company_specialty (company_id, specialty_name_id)
SELECT cr.company_id, s.specialty_name_id
FROM company cr
JOIN JSON_TABLE(
    cr.specialities,
    '$[*]'
    COLUMNS (
       specialty VARCHAR(255) PATH '$'
    )
) AS jt
JOIN specialty s ON s.specialty_name = TRIM(jt.specialty)
WHERE cr.specialities IS NOT NULL
  AND TRIM(jt.specialty) <> ''
ON DUPLICATE KEY UPDATE specialty_name_id = s.specialty_name_id;

-- -----------------------------------------------------
-- Extract and load company type data
-- -----------------------------------------------------
-- Step 1: Insert unique company types into dimension table
INSERT INTO type (company_type_name)
SELECT DISTINCT TRIM(company_type) AS company_type_name
FROM company
WHERE company_type IS NOT NULL
  AND TRIM(company_type) <> ''
ON DUPLICATE KEY UPDATE company_type_name = company_type_name;

-- Step 2: Create relationships between companies and types
INSERT INTO company_type (company_id, company_type_id)
SELECT cr.company_id, t.company_type_id
FROM company cr
JOIN type t ON t.company_type_name = TRIM(cr.company_type)
WHERE cr.company_type IS NOT NULL
  AND TRIM(cr.company_type) <> ''
ON DUPLICATE KEY UPDATE company_type_id = t.company_type_id;

-- -----------------------------------------------------
-- Extract and load industry data
-- -----------------------------------------------------
-- Step 1: Insert unique industries into dimension table
INSERT INTO industry (industry_name)
SELECT DISTINCT TRIM(industry) AS industry_name
FROM company
WHERE industry IS NOT NULL
  AND TRIM(industry) <> ''
ON DUPLICATE KEY UPDATE industry_name = industry_name;

-- Step 2: Create relationships between companies and industries
INSERT INTO industry_type (company_id, industry_id)
SELECT cr.company_id, i.industry_id
FROM company cr
JOIN industry i ON i.industry_name = TRIM(cr.industry)
WHERE cr.industry IS NOT NULL
  AND TRIM(cr.industry) <> ''
ON DUPLICATE KEY UPDATE industry_id = i.industry_id;

-- -----------------------------------------------------
-- Extract and load location data
-- -----------------------------------------------------
INSERT INTO locations (company_id, country, city, postal_code, address_line1, is_hq, state)
SELECT 
    cr.company_id,
    TRIM(jt.country) AS country,
    TRIM(jt.city) AS city,
    TRIM(jt.postal_code) AS postal_code,
    TRIM(jt.line_1) AS address_line1,
    CASE 
        WHEN TRIM(jt.is_hq) IN ('true', '1') THEN TRUE 
        ELSE FALSE 
    END AS is_hq,
    TRIM(jt.state) AS state
FROM company cr
JOIN JSON_TABLE(
    cr.locations,
    '$[*]' 
    COLUMNS (
       country     VARCHAR(255) PATH '$.country',
       city        VARCHAR(255) PATH '$.city',
       postal_code VARCHAR(50)  PATH '$.postal_code',
       line_1      VARCHAR(500) PATH '$.line_1',
       is_hq       VARCHAR(10)  PATH '$.is_hq',
       state       VARCHAR(255) PATH '$.state'
    )
) AS jt
WHERE cr.locations IS NOT NULL
  AND TRIM(jt.country) <> '';

-- -----------------------------------------------------
-- Extract and load company update data
-- -----------------------------------------------------
INSERT INTO company_updates (company_id, article_link, image, posted_on, update_text, total_likes)
SELECT 
    cr.company_id,
    COALESCE(jt.article_link, 'No Link Provided') AS article_link,
    COALESCE(jt.image, '') AS image,
    STR_TO_DATE(
      CONCAT(
          COALESCE(jt.year, 1900), '-', 
          LPAD(COALESCE(jt.month, 1), 2, '0'), '-', 
          LPAD(COALESCE(jt.day, 1), 2, '0')
      ), '%Y-%m-%d'
    ) AS posted_on,
    COALESCE(jt.text, '') AS update_text,
    COALESCE(jt.total_likes, 0) AS total_likes
FROM company cr
JOIN JSON_TABLE(
    cr.updates,
    '$[*]'
    COLUMNS (
      article_link VARCHAR(500) PATH '$.article_link',
      image        VARCHAR(500) PATH '$.image',
      day          INT PATH '$.posted_on.day',
      month        INT PATH '$.posted_on.month',
      year         INT PATH '$.posted_on.year',
      text         TEXT PATH '$.text',
      total_likes  INT PATH '$.total_likes'
    )
) AS jt
WHERE cr.updates IS NOT NULL;

-- -----------------------------------------------------
-- Extract and load affiliated companies data
-- -----------------------------------------------------
INSERT INTO affiliated_companies (company_id, name, linkedin_url, industry, location)
SELECT 
    cr.company_id,
    COALESCE(jt.name, 'No Name Provided') AS name,
    COALESCE(jt.link, 'No Link Provided') AS linkedin_url,
    COALESCE(jt.industry, 'No Industry Provided') AS industry,
    COALESCE(jt.location, 'No Location Provided') AS location
FROM company cr
JOIN JSON_TABLE(
    cr.affiliated_companies,
    '$[*]'
    COLUMNS (
        name VARCHAR(500) PATH '$.name',
        link VARCHAR(500) PATH '$.link',
        industry VARCHAR(500) PATH '$.industry',
        location VARCHAR(500) PATH '$.location'
    )
) AS jt
WHERE cr.affiliated_companies IS NOT NULL;

-- -----------------------------------------------------
-- Extract and load similar companies data
-- -----------------------------------------------------
-- Step 1: Insert unique similar companies into dimension table
INSERT INTO similar_companies (name, linkedin_url, industry, location)
SELECT DISTINCT
    COALESCE(TRIM(jt.name), 'No Name Provided') AS name,
    COALESCE(TRIM(jt.link), 'No Link Provided') AS linkedin_url,
    COALESCE(TRIM(jt.industry), 'No Industry Provided') AS industry,
    COALESCE(TRIM(jt.location), 'No Location Provided') AS location
FROM company cr
JOIN JSON_TABLE(
    cr.similar_companies,
    '$[*]'
    COLUMNS (
       name VARCHAR(500) PATH '$.name',
       link VARCHAR(500) PATH '$.link',
       industry VARCHAR(500) PATH '$.industry',
       location VARCHAR(500) PATH '$.location'
    )
) AS jt
WHERE cr.similar_companies IS NOT NULL
  AND TRIM(jt.name) <> '';

-- Step 2: Create relationships between companies and similar companies
INSERT INTO similar_companies_junction (company_id, similar_companies_id)
SELECT DISTINCT
    cr.company_id,
    sc.similar_companies_id
FROM company cr
JOIN JSON_TABLE(
    cr.similar_companies,
    '$[*]'
    COLUMNS (
       name VARCHAR(500) PATH '$.name',
       link VARCHAR(500) PATH '$.link',
       industry VARCHAR(500) PATH '$.industry',
       location VARCHAR(500) PATH '$.location'
    )
) AS jt
JOIN similar_companies sc 
    ON sc.name         = COALESCE(TRIM(jt.name), 'No Name Provided')
   AND sc.linkedin_url = COALESCE(TRIM(jt.link), 'No Link Provided')
   AND sc.industry     = COALESCE(TRIM(jt.industry), 'No Industry Provided')
   AND sc.location     = COALESCE(TRIM(jt.location), 'No Location Provided')
WHERE cr.similar_companies IS NOT NULL
  AND TRIM(jt.name) <> '';

/*******************************************************************************
 * PHASE 4: CLEANUP
 * Remove redundant columns from the main company table after extraction
 *******************************************************************************/

-- -----------------------------------------------------
-- Drop columns that have been normalized into separate tables
-- -----------------------------------------------------
ALTER TABLE company DROP COLUMN industry;
ALTER TABLE company DROP COLUMN hq;
ALTER TABLE company DROP COLUMN company_type;
ALTER TABLE company DROP COLUMN specialities;
ALTER TABLE company DROP COLUMN locations;
ALTER TABLE company DROP COLUMN similar_companies;
ALTER TABLE company DROP COLUMN affiliated_companies;
ALTER TABLE company DROP COLUMN updates;
ALTER TABLE company DROP COLUMN company_size;
ALTER TABLE company DROP COLUMN exit_data;
ALTER TABLE company DROP COLUMN acquisitions;
ALTER TABLE company DROP COLUMN extra;
ALTER TABLE company DROP COLUMN funding_data;
ALTER TABLE company DROP COLUMN categories;
ALTER TABLE company DROP COLUMN customer_list;

-- Remove redundant location fields from related companies tables
ALTER TABLE affiliated_companies DROP COLUMN location;
ALTER TABLE similar_companies DROP COLUMN location;

/*******************************************************************************
 * END OF SCRIPT
 *******************************************************************************/