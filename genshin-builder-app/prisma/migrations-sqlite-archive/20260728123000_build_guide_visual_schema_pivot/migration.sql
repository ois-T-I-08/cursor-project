-- No-op placeholder.
-- Visual OCR tables/columns are created by
-- 20260726220000_add_build_guide_recommendations.
-- Legacy local DBs that still lack the visual schema should run:
--   node scripts/repair-guide-visual-schema.js
-- This migration exists so prisma migrate deploy does not fail on an empty directory.

SELECT 1;
