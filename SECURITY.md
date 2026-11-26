# Security

- Report vulnerabilities privately through GitHub Security Advisories, not public issues.
- Never publish the Supabase `service_role` key, a keystore, a GitHub token or real server configs. If one leaked, rotate it.
- The anon key inside the user app is public by design; the SQL restricts it with RLS and security-definer functions.
- Cloud backups are encrypted on the device (AES-GCM, key derived from the recovery code). The server never sees the key.
