-- ============================================================================
-- Ghost Peer Cleanup - Supabase pg_cron Job (FIX C4)
-- ============================================================================
-- Server-side authority for removing stale active_servers rows left behind
-- by clients that crash, force-close (Alt+F4), or lose network connectivity.
-- The client-side _fire_and_forget_cleanup() is best-effort; this cron job
-- is the ultimate guarantee that ghost rows are purged.
-- ============================================================================

-- 1. Enable pg_cron (run once, requires superuser/dashboard)
-- CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 2. Remove active_servers rows where last_seen is older than 15 seconds.
--    The heartbeat interval is 5 seconds, so 15s allows for ~2 missed beats
--    plus network jitter before declaring a server dead.
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'cleanup-ghost-peers';

SELECT cron.schedule(
  'cleanup-ghost-peers',
  '10 seconds',
  $$
    DELETE FROM public.active_servers
    WHERE status = 'active'
      AND last_seen < (EXTRACT(EPOCH FROM now()) - 15)::bigint;
  $$
);

-- 3. Any old legacy transport cleanup job can stay removed.
--    The project now uses Dedicated WebSocket (WSS) exclusively.

-- ============================================================================
-- Verification:
--   SELECT * FROM cron.job;
--
-- To remove a job:
--   SELECT cron.unschedule('cleanup-ghost-peers');
-- ============================================================================
