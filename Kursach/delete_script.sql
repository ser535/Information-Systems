SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'lawfirm_db'
  AND pid <> pg_backend_pid();

DROP DATABASE IF EXISTS lawfirm_db;