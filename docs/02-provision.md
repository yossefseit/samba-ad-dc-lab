# Provision the first domain controller

Provisioning creates a **new AD forest** and its first domain controller. It is not how an additional DC is added to an existing domain; additional DCs must join the domain instead.

## Irreversible choices

Confirm these values in `scripts/00-env` before continuing:

- `REALM`: uppercase AD DNS name and Kerberos realm;
- `DOMAIN`: NetBIOS domain, one word and at most 15 characters;
- `DC_HOST`: short host name, distinct from `DOMAIN`;
- `DC_FQDN`: host plus the lowercase realm suffix;
- `DC_IP`: persistent LAN address already assigned to the VM.

Samba does not support casually renaming an established AD DNS zone and Kerberos realm. If a disposable lab was provisioned with the wrong identity, destroy and rebuild the isolated VM rather than editing databases in place.

## Secret handling

The Administrator password is entered only in Samba's interactive provisioning prompt. It is not accepted through `scripts/00-env`, placed in process arguments, written to shell history, or committed as an example. Store it in an appropriate password manager.

## Run provisioning

```bash
sudo bash scripts/30-provision.sh
```

The script passes the reviewed realm, domain, role, DNS backend, and host IP into interactive mode. Confirm the displayed defaults and enter a unique lab Administrator password twice.

Under the hood, the material operation is equivalent to:

```bash
sudo samba-tool domain provision \
  --interactive \
  --use-rfc2307 \
  --realm=AD.EXAMPLE.TEST \
  --domain=LAB \
  --server-role=dc \
  --dns-backend=SAMBA_INTERNAL \
  --host-ip=10.20.30.10
```

The script also copies Samba's generated Kerberos configuration to `/etc/krb5.conf`, as required on a dedicated DC. If other Kerberos realms share the host, stop: replacing that file is not a safe design for the environment.

## Rerun behavior

Provisioning is not a normal convergent configuration operation. The script uses the following guard:

```text
No sam.ldb -> back up host configuration -> provision once
Existing sam.ldb + matching realm/domain/role -> skip successfully
Existing sam.ldb + mismatch -> stop for investigation
```

It never deletes Samba databases or attempts a second provision over them. A failed partial provision needs investigation; do not remove `/var/lib/samba` merely to make the script pass.

## Post-provision gate

The AD service remains stopped until its DNS forwarder and host resolver are made consistent in the next stage.

```bash
sudo testparm -s
sudo testparm -s --parameter-name=realm
sudo testparm -s --parameter-name=workgroup
sudo testparm -s --parameter-name='server role'
sudo systemctl is-active samba-ad-dc || true
```

Expected values are the configured realm, NetBIOS domain, and `active directory domain controller`. Continue with [DNS, Kerberos, and signed time](03-dns-kerberos.md).

## Failure boundary

If provisioning fails:

1. Save the command output in private troubleshooting notes without passwords.
2. Do not rerun until checking `/etc/samba/smb.conf`, `/var/lib/samba/private/sam.ldb`, hostname resolution, free disk space, and logs.
3. For a disposable first-build lab, rebuilding from the pre-lab VM checkpoint is safer than hand-deleting an unknown partial directory state.
4. Use [Troubleshooting](troubleshooting.md) to diagnose the failure before deciding.
