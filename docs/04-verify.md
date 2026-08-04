# Verification and evidence

Verification is split into non-interactive health checks, credential-backed service checks, a Windows client path, negative tests, and recovery. A successful script run is not a substitute for the later layers.

## Automated non-interactive checks

```bash
sudo bash scripts/50-verify.sh
```

The verifier returns non-zero if any required check fails. It checks:

- `samba-ad-dc` and `chrony` service state;
- Samba configuration parsing;
- host and Samba DNS A-record resolution;
- LDAP, Kerberos TCP/UDP, and password-change SRV records;
- external DNS forwarding;
- local domain information;
- `samba-tool dbcheck --cross-ncs` in report-only mode;
- SYSVOL ACL consistency through `samba-tool ntacl sysvolcheck`;
- Chrony tracking and the signed-time socket.

It does **not** use `|| true` to convert failures into a successful result. It also does not run `dbcheck --fix`; remediation needs a backup and operator review.

## Credential-backed checks

Run these interactively and keep credentials out of command arguments:

```bash
kinit Administrator@AD.EXAMPLE.TEST
klist
smbclient //dc1.ad.example.test/netlogon -U Administrator -c ls
smbclient //dc1.ad.example.test/sysvol -U Administrator -c ls
kdestroy
```

Passing means a Ticket Granting Ticket was issued and the automatically created domain shares were accessible with an authorized account.

## Windows client checks

Use a disposable Windows client on the same isolated LAN:

1. Set its only DNS server to `DC_IP`.
2. Confirm `Resolve-DnsName` returns the DC A and AD SRV records.
3. Confirm `w32tm /query /source` and `w32tm /query /status` report a healthy domain time path after join.
4. Join the configured DNS domain with a delegated or lab Administrator account.
5. Reboot and sign in as the optional `lab.user` account.
6. Install RSAT, open Active Directory Users and Computers, and confirm the lab OUs.
7. Create a harmless test GPO, link it to `Lab Workstations`, run `gpupdate /force`, and confirm the result with `gpresult /r`.

Do not describe Group Policy as tested until this path succeeds and the result is retained as sanitized evidence.

## Negative tests

Run only in the disposable lab and restore the expected state after each test.

| Test | Expected result |
| --- | --- |
| Point the client at a public DNS resolver | AD SRV discovery and join fail; restore client DNS to `DC_IP` |
| Stop `chrony` temporarily | Time health check fails; restart Chrony before authentication drifts |
| Stop `samba-ad-dc` temporarily | DNS and directory checks fail; restart and re-run the full verifier |
| Supply a self-referential DNS forwarder in a copy of `00-env` | Configuration parser rejects it before host mutation |
| Rerun provisioning against a matching domain | Script reports a safe skip |
| Change the configured realm after provisioning | Script refuses the mismatch |

Do not inject database corruption, alter system time by large amounts, or expose services beyond the isolated subnet merely to create evidence.

## Evidence record

Create a private evidence directory outside Git first. For any sanitized artifact intended for publication, record:

- UTC timestamp;
- repository commit SHA;
- Ubuntu and Samba versions;
- exact test command;
- exit status;
- whether the test was local, client-side, restore-host, or teardown;
- redactions made.

Never publish passwords, Kerberos tickets, keytabs, private backup archives, domain database files, public IP addresses, production names, employer data, or unrelated host details. Do not invent output. The [evidence template](evidence/README.md) lists the minimum artifacts for a defensible status update.

## Remaining gates

A complete runtime claim requires all of the following:

- automated verifier passes;
- Administrator Kerberos and share checks pass;
- Windows DNS, join, login, and GPO path passes;
- an online backup is produced and copied offline;
- an isolated restore is started and retested;
- the disposable environment is safely torn down or rebuilt.

Continue with [Backup and recovery](05-backup-recovery.md).
