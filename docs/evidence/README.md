# Sanitized evidence checklist

No runtime evidence is committed yet. This directory defines what may be added after a real isolated-lab run; it is not proof that the run occurred.

For each evidence set, include a short Markdown index with:

- UTC timestamp and repository commit SHA;
- Ubuntu and Samba versions;
- test purpose, exact command, and exit status;
- sanitized output or screenshot;
- redaction statement;
- result and any limitation;
- whether cleanup completed.

Recommended evidence sequence:

1. repository CI run link;
2. non-interactive verifier summary;
3. Kerberos TGT result with ticket identifiers and user-specific paths redacted;
4. SYSVOL and NETLOGON listing;
5. Windows DNS, domain join, login, and GPO result;
6. backup checksum (never the archive);
7. isolated restore verifier and client result;
8. teardown confirmation.

Never add passwords, hashes, keytabs, ticket caches, backup archives, Samba databases, private keys, public IPs, production names, employer/customer data, or raw diagnostic bundles.
