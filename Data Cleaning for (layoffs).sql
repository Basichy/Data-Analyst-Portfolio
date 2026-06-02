-- ============================================================
-- PROJECT: Layoffs Data Cleaning
-- DATASET: Global tech layoffs (company, location, industry,
--          total_laid_off, percentage_laid_off, date, stage,
--          country, funds_raised_millions)
-- AUTHOR:  Ethan Gaylan
-- STEPS:
--   1. Create a staging copy to preserve raw data
--   2. Remove duplicate rows
--   3. Standardize inconsistent values
--   4. Handle NULL and blank values
--   5. Drop helper columns
-- ============================================================

SELECT * 
FROM layoffs;


-- ============================================================
-- STEP 1: CREATE A STAGING COPY
-- Always work on a copy, never the raw table.
-- This ensures the original data is safe if mistakes are made.
-- ============================================================

-- Create an empty table with the same structure as the raw table
CREATE TABLE layoffs_staging
LIKE layoffs;
 
-- Populate the staging table with all raw data
INSERT layoffs_staging
SELECT *
FROM layoffs;


-- ============================================================
-- STEP 2: REMOVE DUPLICATES
-- The dataset has no unique ID column, so we use ROW_NUMBER()
-- with PARTITION BY across all meaningful columns to flag
-- rows that are exact duplicates.
-- ============================================================

-- Preview: assign a row number within each group of duplicates.
-- Any row_num > 1 is a duplicate.
SELECT *, 
ROW_NUMBER() OVER(
PARTITION BY company, industry, total_laid_off, percentage_laid_off, 'date') AS row_num
FROM layoffs_staging;


-- Use a CTE to isolate and inspect the duplicate rows before deleting
WITH duplicate_cte AS
(
SELECT *, 
ROW_NUMBER() OVER(
PARTITION BY company, location, industry, total_laid_off, percentage_laid_off, 'date', 
stage, country, funds_raised_millions) AS row_num
FROM layoffs_staging
)
SELECT *
FROM duplicate_cte
WHERE row_num > 1;

-- Verify a specific company flagged as duplicate (spot-check)
SELECT *
FROM layoffs_staging
WHERE company = 'Casper';

-- FIRST ATTEMPT: tried to delete directly from the CTE
-- This throws an error in MySQL because CTEs are read-only.
-- MySQL does not support DELETE statements targeting a CTE directly.
-- ❌ This does NOT work:
WITH duplicate_cte AS
(
SELECT *, 
ROW_NUMBER() OVER(
PARTITION BY company, location, industry, total_laid_off, percentage_laid_off, 'date', stage, country, funds_raised_millions) AS row_num
FROM layoffs_staging
)
DELETE 
FROM duplicate_cte
WHERE row_num > 1;

-- FIX: Since we can't delete from a CTE, we create a second staging table
-- (layoffs_staging2) that includes row_num as a real physical column.
CREATE TABLE `layoffs_staging2` (
  `company` text,
  `location` text,
  `industry` text,
  `total_laid_off` text DEFAULT NULL,
  `percentage_laid_off` text,
  `date` text,
  `stage` text,
  `country` text,
  `funds_raised_millions` text DEFAULT NULL,
  `row_num` INT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Insert all rows into the new table, with row numbers assigned
INSERT INTO layoffs_staging2
SELECT *, 
ROW_NUMBER() OVER(
PARTITION BY company, location, industry, total_laid_off, percentage_laid_off, 'date', stage, country, funds_raised_millions) AS row_num
FROM layoffs_staging;

-- Confirm which rows are duplicates (row_num > 1)
SELECT * 
FROM layoffs_staging2
WHERE row_num > 1;

-- Delete all duplicate rows, keeping only the first occurrence (row_num = 1)
DELETE
FROM layoffs_staging2
WHERE row_num > 1;


-- ============================================================
-- STEP 3: STANDARDIZE THE DATA
-- Fix inconsistent formatting, spelling variations, and
-- date formats so data is uniform and query-ready.
-- ============================================================

-- Preview the current state of the table
SELECT * 
FROM layoffs_staging2;

-- 3a. Trim whitespace from company names
-- Some entries have leading/trailing spaces that cause mismatches
SELECT company, TRIM(company)
FROM layoffs_staging2;

UPDATE layoffs_staging2
SET company = TRIM(company);

-- 3b. Standardize industry names
-- 'Crypto', 'Crypto Currency' and 'CryptoCurrency' all refer to the same industry
-- Consolidate all variations under 'Crypto'
SELECT DISTINCT industry
FROM layoffs_staging2
WHERE industry LIKE 'Crypto%';

UPDATE layoffs_staging2
SET industry = 'Crypto'
WHERE industry LIKE 'Crypto%';

-- 3c. Standardize country names
-- 'United States' and 'United States.' (with trailing period) are the same country
SELECT DISTINCT country
FROM layoffs_staging2
WHERE country LIKE 'United States%';

UPDATE layoffs_staging2
SET country = 'United States'
WHERE country LIKE 'United States%';

-- 3d. Convert the date column from text to proper DATE format
-- The raw data stores dates as strings (e.g., '3/11/2023'),
-- so we convert them using STR_TO_DATE before changing the column type

-- Preview the conversion
SELECT `date`,
STR_TO_DATE(`date`, '%m/%d/%Y')
FROM layoffs_staging2;

-- Replace string 'NULL' with actual NULL before converting
UPDATE layoffs_staging2
SET `date` = NULL
WHERE `date` = 'NULL';

-- Apply the date format conversion
UPDATE layoffs_staging2
SET `date` = STR_TO_DATE(`date`, '%m/%d/%Y');

-- Change the column type from TEXT to DATE
ALTER TABLE layoffs_staging2
MODIFY COLUMN `date` DATE;


-- ============================================================
-- STEP 4: HANDLE NULL AND BLANK VALUES
-- Replace string 'NULL' placeholders with real NULLs,
-- and use self-joins to fill in missing industry values
-- where the same company appears with a known industry elsewhere.
-- ============================================================

-- 4a. Convert string 'NULL' to actual NULL for numeric/text columns
UPDATE layoffs_staging2
SET `total_laid_off` = NULL
WHERE `total_laid_off` = 'NULL';

UPDATE layoffs_staging2
SET `percentage_laid_off` = NULL
WHERE `percentage_laid_off` = 'NULL';

UPDATE layoffs_staging2
SET `industry` = NULL
WHERE `industry` = 'NULL';

UPDATE layoffs_staging2
SET `industry` = NULL
WHERE `industry` = '';

-- 4b. Identify rows where both key metrics are missing
-- These rows have no useful data and will be removed later
SELECT * 
FROM layoffs_staging2
WHERE total_laid_off IS NULL
AND percentage_laid_off IS NULL;

-- 4c. Check which rows are missing an industry value
SELECT *
FROM layoffs_staging2
WHERE industry IS NULL
OR industry = '';

-- 4c. Check which rows are missing an industry value
SELECT *
FROM layoffs_staging2
WHERE company LIKE 'Bally%';

-- 4d. Fill in missing industry values using a self-join
-- If the same company has another row with a known industry,
-- we can use that to populate the NULL
SELECT t1.company, t2.company, t1.industry, t2.industry
FROM layoffs_staging2 t1
JOIN layoffs_staging2 t2
	ON t1.company = t2.company
    AND t1.location = t2.location
WHERE (t1.industry IS NULL OR t1.industry = '')
AND t2.industry IS NOT NULL;

-- Apply the fix: update NULL industry rows with the known value
UPDATE layoffs_staging2 t1
JOIN layoffs_staging2 t2
	ON t1.company = t2.company
SET t1.industry = t2.industry
WHERE (t1.industry IS NULL OR t1.industry = '')
AND t2.industry IS NOT NULL;

-- 4e. Remove rows where both total_laid_off and percentage_laid_off are NULL
-- These rows provide no analytical value
SELECT *
FROM layoffs_staging2
WHERE total_laid_off IS NULL
AND percentage_laid_off IS NULL;

DELETE 
FROM layoffs_staging2
WHERE total_laid_off IS NULL
AND percentage_laid_off IS NULL;


-- ============================================================
-- STEP 5: DROP HELPER COLUMNS
-- The row_num column was only needed for duplicate removal.
-- Now that cleaning is complete, we remove it.
-- ============================================================

ALTER TABLE layoffs_staging2
DROP COLUMN row_num;

-- Final check: view the fully cleaned dataset
SELECT *
FROM layoffs_staging2;

