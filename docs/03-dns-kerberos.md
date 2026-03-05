# DNS and Kerberos Configuration

After provisioning the domain controller, you need to ensure that DNS and Kerberos are correctly configured.  Samba’s internal DNS is responsible for registering service (SRV) records used by clients to locate LDAP and Kerberos services.  Kerberos must reference the correct realm and key distribution centre (KDC).

## 1. Verify DNS service

First, confirm that Samba’s DNS server is listening on port 53:

```bash
sudo ss -lpun | grep ':53'
```

You should see `samba` bound to both `0.0.0.0:53` and `:::53`.  If nothing is listening, check that `samba-ad-dc` is running.

### Test LDAP SRV record

Use `host` to query the `_ldap._tcp` service record for your domain (replace `test.local` with your DNS domain):

```bash
host -t SRV _ldap._tcp.test.local 127.0.0.1
```

The result should point to your domain controller, for example:

```
_ldap._tcp.test.local has SRV record 0 100 389 dc1.test.local.
```

### Test Kerberos SRV records

Kerberos clients locate the KDC using `_kerberos._udp` and `_kerberos._tcp` records.  Query them similarly:

```bash
host -t SRV _kerberos._udp.test.local 127.0.0.1
host -t SRV _kerberos._tcp.test.local 127.0.0.1
```

If the SRV records are missing or point to the wrong host, run the DNS update tool:

```bash
sudo samba_dnsupdate --verbose
sudo systemctl restart samba-ad-dc
```

This command registers service records in the Samba DNS zone.

## 2. Kerberos authentication

Once DNS is working and `/etc/krb5.conf` has been replaced by Samba’s version, test Kerberos authentication using the domain administrator account.  Never prepend `sudo` when obtaining Kerberos tickets:

```bash
kinit Administrator@TEST.LOCAL
klist
```

`kinit` will prompt for the administrator password and, upon success, `klist` will display your Kerberos ticket and validity period.  If you see “client not found in Kerberos database” or “Cannot find KDC”, double‑check your realm name, DNS SRV records and system clock.

## 3. Managing resolv.conf

During provisioning and initial package installation you may temporarily use public resolvers (e.g. `1.1.1.1` or `8.8.8.8`) in `/etc/resolv.conf` to ensure `apt update` works.  After the AD DC is running, revert `/etc/resolv.conf` to local DNS and set a search domain.  Example contents:

```conf
nameserver 127.0.0.1
search test.local
```

Combine this with a `dns forwarder` in `smb.conf` so that external names resolve via your upstream resolver.

## 4. Adjusting the DNS forwarder

To change the upstream DNS server, edit `/etc/samba/smb.conf` and ensure there is only one `dns forwarder` line.  For example, to forward to Quad9 (9.9.9.9):

```ini
[global]
    dns forwarder = 9.9.9.9
```

Remove any accidental duplicate entries (e.g. `dns forwarder = 127.0.0.1`).  Restart `samba-ad-dc` after editing:

```bash
sudo systemctl restart samba-ad-dc
```

These steps guarantee that DNS and Kerberos operate correctly for both domain clients and the host itself.
