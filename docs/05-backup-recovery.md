# Backup and recovery

Samba domain backups contain directory data, SYSVOL, password material, and other secrets. They belong in a root-only directory, then encrypted offline storage—not Git, a public artifact store, or an unencrypted shared folder.

## Recovery objectives

Define lab objectives before testing:

- **RPO:** maximum acceptable age of directory data in the chosen backup;
- **RTO:** time allowed to restore a new isolated DC, validate it, and make clients functional;
- **scope:** recovery of the AD domain, not a byte-for-byte repair of one DC;
- **acceptance:** DNS, Kerberos, directory, SYSVOL/NETLOGON, signed time, and a Windows client path all pass.

Do not publish numerical RPO/RTO achievements until a timed restore drill has produced evidence.

## Create an online domain backup

First run the report-only database and SYSVOL checks:

```bash
sudo samba-tool dbcheck --cross-ncs
sudo samba-tool ntacl sysvolcheck
```

Investigate errors rather than using `--fix` automatically. Then create the backup:

```bash
sudo bash scripts/70-backup.sh
```

The script:

- requires the DC service to be active;
- creates `BACKUP_DIR` with root-only permissions;
- prompts for the domain Administrator credential;
- invokes `samba-tool domain backup online`;
- requires a backup archive newer than a secure per-run timestamp marker, proving this invocation created it;
- writes a SHA-256 checksum next to that new backup artifact;
- reminds the operator that creation is not restore evidence.

Copy the archive and checksum to encrypted offline storage. Record retention, owner, timestamp, commit SHA, Samba version, and restore-test status in a private inventory.

## Isolated restore drill

The restore must never share a network with another running copy of the same domain database. Use an isolated virtual switch with no route to the original lab, or keep the restored service stopped for an on-disk inspection.

On a fresh matching Samba host:

1. Verify the archive checksum.
2. Keep all original DCs offline or network-isolated.
3. Choose a **new** DC short name and an empty/non-existent target directory.
4. Restore the domain once:

   ```bash
   sudo samba-tool domain backup restore \
     --backup-file=/secure/path/samba-backup.tar.bz2 \
     --newservername=restore-dc \
     --targetdir=/var/lib/samba-restore-test
   ```

5. Review the restored `etc/smb.conf`, IP assumptions, resolver, time, and firewall configuration.
6. Start Samba against the restored configuration only inside the isolated network, following the official restore procedure.
7. Repeat every check in [Verification and evidence](04-verify.md), including a disposable Windows client.
8. Destroy or securely retain the secret-bearing restore environment according to the lab data policy.

An on-disk restore that is never started can validate archive readability and object presence, but it is not a runtime recovery test. A runtime restore without client authentication is also incomplete.

## Recovery boundaries

- A domain backup restores the domain onto a new DC; it is not the right tool to repair one failed DC while other healthy DCs remain.
- Restore is performed once. Any additional DCs must be freshly joined to the restored DC.
- Never restart old DC databases alongside the restored database; they represent divergent copies.
- A hypervisor snapshot is a useful lab rollback point but not the only directory backup strategy.
- A single DC has no replication-based availability. Production needs multiple DCs and independent, tested backups.

## Evidence required before marking recovery tested

- checksum verification;
- restore command and zero exit status;
- new DC name and isolated-network description;
- `dbcheck` and SYSVOL checks;
- DNS SRV and A-record results;
- Kerberos ticket acquisition;
- SYSVOL and NETLOGON access;
- Windows client join/login or documented equivalent acceptance test;
- elapsed time measured from an explicit start and finish;
- teardown or secure-retention confirmation.

Follow the current [Samba backup and restore guidance](https://wiki.samba.org/index.php/Back_up_and_Restoring_a_Samba_AD_DC) during an actual drill; recovery behavior can change between Samba releases.
