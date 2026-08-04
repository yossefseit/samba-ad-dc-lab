# Teardown and rollback

Teardown is intentionally not automated. A recursive cleanup script cannot reliably distinguish a disposable sole-DC lab from a joined or data-bearing host, and deleting the wrong Samba state is irreversible.

## Preferred disposable-VM teardown

1. Confirm that all evidence intended for retention is sanitized and stored outside the VM.
2. Create and copy a final encrypted domain backup if recovery evidence is in scope.
3. Verify the copied archive checksum from its destination.
4. Disconnect the Windows client and DC from the lab virtual switch.
5. Power off both VMs.
6. Remove the VMs and lab-only snapshots through the owning hypervisor after confirming their exact identities.
7. Remove lab-only DHCP reservations and DNS entries through their owning systems.
8. Confirm the lab subnet no longer exposes AD ports.

Deleting a VM proves removal of that VM; it does not prove a backup is restorable or that copies were securely erased from every storage layer.

## Host configuration rollback boundary

The scripts save the first observed versions of changed host paths under:

```text
/var/lib/samba-ad-dc-lab/original/
```

Those copies support investigation and deliberate manual recovery. They are not a complete host backup and the repository does not restore them automatically. The tracked paths can include:

- `/etc/hostname`;
- `/etc/hosts`;
- `/etc/samba/smb.conf`;
- `/etc/krb5.conf`;
- `/etc/resolv.conf` (including its original symlink state);
- the lab Chrony drop-in.

For a host that must be reused, reimaging Ubuntu is the safest default. If reimaging is impossible, write an environment-specific rollback change, review exact files and service ownership, stop the AD service, restore only known originals, re-enable the correct resolver and standalone services, and reboot-test. Do not remove Samba databases until a verified backup exists and the host's role is certain.

## Why demotion is not the default teardown

`samba-tool domain demote` is designed for removing a DC from a domain with remaining healthy DCs. This lab creates the only DC in a new forest, so destroying the disposable VM is clearer and safer than pretending a final-DC demotion preserves a usable domain.

## Teardown evidence

Record the repository commit, VM identifiers, backup disposition, UTC start/finish, exact hypervisor or platform actions, and post-removal network check. Keep platform identifiers private. Mark teardown tested only when the documented sequence has actually completed.
