# Troubleshooting runbook

Work from dependencies inward: host identity and time, DNS, Samba configuration, service state, Kerberos, then client behavior. Save sanitized logs before changing state.

## Collect a read-only diagnostic bundle

Run commands individually so a failure in one does not hide the others:

```bash
hostname
hostname -f
ip -brief -4 address
ip route
getent ahostsv4 "$(hostname -f)"
sudo testparm -s
sudo systemctl status samba-ad-dc --no-pager
sudo journalctl -u samba-ad-dc --since '-30 minutes' --no-pager
sudo systemctl status chrony --no-pager
chronyc tracking
cat /etc/resolv.conf
```

Review before sharing. Samba logs and command output can contain domain names, user names, SIDs, addresses, and other environment details.

## Provisioning refuses an existing database

The rerun guard found `/var/lib/samba/private/sam.ldb`. This is intentional. Check:

```bash
sudo testparm -s --parameter-name=realm
sudo testparm -s --parameter-name=workgroup
sudo testparm -s --parameter-name='server role'
sudo samba-tool dbcheck --cross-ncs
```

If values match, the provision script should skip. If they differ or configuration is missing, do not delete the database. Recover from the pre-lab VM checkpoint or investigate the partial state.

## `samba-ad-dc` fails to start

Check for standalone-service conflicts and configuration errors:

```bash
sudo systemctl is-active smbd nmbd winbind
sudo testparm -s
sudo ss -lntup
sudo journalctl -u samba-ad-dc -n 100 --no-pager
```

On this dedicated lab host, the standalone units should be masked and inactive. Port 53 is a common conflict if `systemd-resolved` or another DNS server is still bound. Run `40-dns-forwarder.sh` rather than manually deleting PID files.

## DNS activation failed and resolver was restored

`40-dns-forwarder.sh` rolls `/etc/resolv.conf` and `systemd-resolved` back when service activation or the DC A-record check fails. Confirm current state:

```bash
systemctl is-active systemd-resolved || true
readlink -f /etc/resolv.conf || true
cat /etc/resolv.conf
sudo testparm -s --parameter-name='dns forwarder'
```

Resolve the Samba start error first, then rerun the script. Do not add a public resolver alongside the DC resolver as a workaround.

## External names fail but AD names work

Check the configured forwarder and query it directly from an allowed network:

```bash
sudo testparm -s --parameter-name='dns forwarder'
host -t A example.com 127.0.0.1
```

The forwarder must not be the DC itself, a loopback/stub address, multicast, or link-local. It may also be blocked by the lab firewall or network policy.

## AD SRV records are absent

```bash
zone=ad.example.test
host -t SRV "_ldap._tcp.${zone}" 127.0.0.1
sudo samba_dnsupdate --verbose
sudo journalctl -u samba-ad-dc -n 100 --no-pager
```

Confirm hostname/FQDN resolution and the configured realm before attempting to add records manually.

## Kerberos cannot find the KDC

```bash
cat /etc/krb5.conf
host -t SRV _kerberos._tcp.ad.example.test 127.0.0.1
chronyc tracking
kdestroy 2>/dev/null || true
kinit Administrator@AD.EXAMPLE.TEST
```

The resolver must use Samba DNS, the realm must match exactly, Samba's generated Kerberos configuration must be readable, and clocks must be synchronized.

## Chrony cannot access `ntp_signd`

```bash
sudo stat /var/lib/samba/ntp_signd
sudo stat /var/lib/samba/ntp_signd/socket
sudo chronyd -p -f /etc/chrony/chrony.conf
sudo journalctl -u chrony -n 100 --no-pager
```

The directory should be owned by `root:_chrony` with mode `0750`. Rerun `45-time-sync.sh` only after confirming Samba created the socket.

## A client cannot join

On the client, verify its only DNS server is `DC_IP`, then check the DC A record, LDAP and Kerberos SRV records, clock offset, and required firewall ports. A successful ping is not enough. Do not weaken signing, Kerberos, password, or firewall controls to make the join pass.

## Recovery escalation

Stop making changes and follow [Backup and recovery](05-backup-recovery.md) when database integrity is questionable, a destructive fix is proposed, or more than one DC may contain divergent state. `samba-tool dbcheck --fix`, database deletion, forced demotion, and starting two restored copies of one domain all require an explicit recovery decision and a verified backup.
