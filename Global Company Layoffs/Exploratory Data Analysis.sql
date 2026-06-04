-- ============================================================
-- PROJECT: Layoffs Exploratory Data Analysis
-- DATASET: Global tech layoffs
-- AUTHOR:  Ethan (Basichy)
-- GOAL:    Explore trends in layoffs by company, industry,
--          country, date, and stage. Build up to a rolling
--          total and a yearly company ranking.
-- ============================================================

-- View the full cleaned dataset
SELECT *
FROM layoffs_staging2;

-- Find the largest single layoff event and highest percentage laid off
-- This gives us a sense of the scale of the data
SELECT MAX(total_laid_off), MAX(percentage_laid_off)
FROM layoffs_staging2;

-- Find companies that laid off 100% of their workforce (percentage_laid_off = 1)
-- Ordered by total laid off to see which were the largest complete shutdowns
SELECT *
FROM layoffs_staging2
WHERE percentage_laid_off = 1
ORDER BY total_laid_off DESC;

-- Total layoffs per company, ranked highest to lowest
SELECT company, SUM(total_laid_off)
FROM layoffs_staging2
GROUP BY company
ORDER BY 2 DESC;

-- Check the date range of the dataset so we know what time period we're analysing
SELECT MIN(`date`), MAX(`date`)
FROM layoffs_staging2;

-- Total layoffs by industry
-- Helps identify which sectors were most affected
SELECT industry, SUM(total_laid_off)
FROM layoffs_staging2
GROUP BY industry
ORDER BY 2 DESC;

-- Total layoffs by year
-- Gives a high-level view of how layoffs trended over time
SELECT YEAR(`date`), SUM(total_laid_off)
FROM layoffs_staging2
GROUP BY YEAR(`date`)
ORDER BY 1 DESC;

-- Total layoffs by company stage (e.g. Series B, Post-IPO)
SELECT stage, SUM(total_laid_off)
FROM layoffs_staging2
GROUP BY stage
ORDER BY 1 DESC;

-- NOTE: percentage_laid_off is not very useful on its own
-- because we don't have the total headcount to give it context.
-- Without knowing company size, summing percentages is misleading.
SELECT company, SUM(percentage_laid_off)
FROM layoffs_staging2
GROUP BY company
ORDER BY 1 DESC;

SELECT *
FROM layoffs_staging2;

-- FIRST ATTEMPT: extract just the month number (e.g. '03' for March)
-- Problem: this groups all years together, so March 2022 and March 2023
-- are treated as the same month — not an accurate representation
SELECT SUBSTRING(`date`, 6, 2) AS `MONTH`, SUM(total_laid_off)
FROM layoffs_staging2
GROUP BY `MONTH`
;

-- FIX: extract year AND month (e.g. '2023-03')
-- Now each month is unique across years, giving an accurate time series
-- Now it has year and month so present the data accurately
SELECT SUBSTRING(`date`, 1, 7) AS `MONTH`, SUM(total_laid_off)
FROM layoffs_staging2
WHERE SUBSTRING(`date`, 1, 7) IS NOT NULL
GROUP BY `MONTH`
ORDER BY 1 ASC
;

-- Rolling/running total of layoffs month by month
-- CTE calculates monthly totals, then the window function accumulates them over time
WITH Rolling_Total AS
(
SELECT SUBSTRING(`date`, 1, 7) AS `MONTH`, SUM(total_laid_off) AS total_off
FROM layoffs_staging2
WHERE SUBSTRING(`date`, 1, 7) IS NOT NULL
GROUP BY `MONTH`
ORDER BY 1 ASC
)
SELECT `MONTH`, total_off, SUM(total_off) OVER(ORDER BY `MONTH`) AS rolling_total
FROM Rolling_Total;

-- First pass: group by company and year, ordered alphabetically
-- Useful for exploring the data but hard to identify top performers
SELECT company, YEAR(`date`), SUM(total_laid_off)
FROM layoffs_staging2
GROUP BY company, YEAR(`date`)
ORDER BY company ASC;

-- Second pass: order by total laid off descending
-- Now we can see the biggest layoff events, but still no ranking
SELECT company, YEAR(`date`), SUM(total_laid_off)
FROM layoffs_staging2
GROUP BY company, YEAR(`date`)
ORDER BY 3 DESC;

-- Ranking system using two chained CTEs
-- CTE 1 (Company_Year): calculates total layoffs per company per year
-- CTE 2 (Company_Year_Rank): applies DENSE_RANK() partitioned by year
--   so each year gets its own independent ranking (1 = most layoffs that year)
-- Final SELECT filters to only the top 5 companies per year
WITH Company_Year (company, years, total_laid_off) AS
(
SELECT company, YEAR(`date`), SUM(total_laid_off)
FROM layoffs_staging2
GROUP BY company, YEAR(`date`)
), Company_Year_Rank AS
(SELECT * , DENSE_RANK() OVER (PARTITION BY years ORDER BY total_laid_off DESC) AS Ranking
FROM Company_Year
WHERE years IS NOT NULL
)
SELECT *
FROM Company_Year_Rank
WHERE Ranking <= 5
;
