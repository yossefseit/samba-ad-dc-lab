## Verifying the AD DC

After provisioning and starting services, verify that your domain controller is running correctly and can serve DNS and Kerberos requests.

### Check service status

Run the following command to ensure the Samba AD DC service is active:

```bash
sudo systemctl status samba-ad-dc --no-pager
```

The output should show `active (running)`. If it's not, review logs with:

```bash
sudo journalctl -xeu samba-ad-dc --no-pager | tail -n 80
```

### Confirm DNS is listening

Samba’s internal DNS server must be listening on port 53. Verify this:

```bash
sudo ss -lpun | grep ':53'
```

You should see `samba` or `samba_dnsupdate` listening on `127.0.0.1:53`.

### Test DNS SRV records

LDAP and Kerberos rely on SRV records. Test them locally:

```bash
host -t SRV _ldap._tcp.test.local 127.0.0.1
host -t SRV _kerberos._udp.test.local 127.0.0.1
host -t SRV _kerberos._tcp.test.local 127.0.0.1
```

Each command should return the FQDN of your DC (e.g., `dc1.test.local`) and the correct service port (389 for LDAP, 88 for Kerberos). If not, run:

```bash
sudo samba_dnsupdate --verbose
sudo systemctl restart samba-ad-dc
```

### Verify Kerberos authentication

Attempt to obtain a Kerberos ticket for the `Administrator` account:

```bash
kinit Administrator@TEST.LOCAL
klist
```

You should be prompted for the password and then see a valid Ticket Granting Ticket (TGT) when you run `klist`. If you see “Cannot find KDC for realm” or “Client not found”, check that `/etc/krb5.conf` is copied from `/var/lib/samba/private/krb5.conf`, that your DNS resolver points at `127.0.0.1`, and that the Kerberos SRV records exist.

### List users and OUs

List the existing users and organisational units:

```bash
sudo samba-tool user list
sudo samba-tool ou list
```

You should see built‑in accounts (`Administrator`, `krbtgt`, `Guest`) and any you created (e.g., `yossef`).

### Test network shares

Finally, verify that the SYSVOL and NETLOGON shares are available:

```bash
smbclient -L dc1.test.local -U Administrator
```

This should list `netlogon` and `sysvol`. If share access fails, confirm that SMB port 445 is accessible and that your firewall is not blocking it.

With these checks complete, your Samba AD DC should be ready for Windows computers to join and for you to create Group Policy Objects (GPOs) from a Windows RSAT console.
