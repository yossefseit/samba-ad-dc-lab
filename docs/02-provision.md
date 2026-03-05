# Domain Provisioning

With the server prepared and required packages installed, you can create a new Active Directory domain.  This step initialises Samba’s internal database, generates Kerberos keytabs and DNS zone files, and writes a new smb.conf.

## 1. Back up any existing configuration

If `/etc/samba/smb.conf` exists (for example, from a previous file‑server setup), back it up before provisioning:

```bash
sudo mv /etc/samba/smb.conf "/etc/samba/smb.conf.bak.$(date +%F_%H%M%S)"
```

## 2. Provision the domain

Run `samba‑tool domain provision` as root.  The example below uses variables defined in `scripts/00-env` and enables RFC 2307 attributes for UNIX ID mapping.

```bash
sudo samba-tool domain provision \
  --use-rfc2307 \
  --realm="${REALM}" \
  --domain="${DOMAIN}" \
  --server-role=dc \
  --dns-backend=SAMBA_INTERNAL
```

During provisioning you will be prompted for the **Administrator** password.  Choose a strong password; it will also be used as the default domain admin account.  Samba may display a randomly generated password if you leave the prompt blank.

After completion you should see messages similar to:

```
Server Role:           active directory domain controller
Hostname:              dc1
NetBIOS Domain:        TEST
DNS Domain:            test.local
DOMAIN SID:            S-1-5-21-... (unique to your domain)
```

## 3. Copy the Kerberos configuration

Samba generates a Kerberos config at `/var/lib/samba/private/krb5.conf` tailored to your realm.  Overwrite the system’s `/etc/krb5.conf` with this file:

```bash
sudo cp -f /var/lib/samba/private/krb5.conf /etc/krb5.conf
```

## 4. Enable the AD DC service

Start and enable the unified `samba-ad-dc` service.  This single daemon handles SMB, LDAP, Kerberos, DNS and more.

```bash
sudo systemctl enable --now samba-ad-dc
```

Use `systemctl status samba-ad-dc --no-pager` to confirm it is running.  If it fails to start, consult the [Troubleshooting](troubleshooting.md) guide.

## 5. Configure DNS resolution

After provisioning, edit `/etc/resolv.conf` to point to the local Samba DNS and set a search domain.  For example:

```bash
sudo tee /etc/resolv.conf > /dev/null <<'EOF'
nameserver 127.0.0.1
search test.local
EOF
```

The DNS server built into Samba can forward queries it cannot answer.  Configure a forwarder in `smb.conf` by adding the following under the `[global]` section:

```ini
[global]
    # existing settings ...
    dns forwarder = ${DNS_FORWARDER}
```

Restart the daemon to apply changes:

```bash
sudo systemctl restart samba-ad-dc
```

At this point the domain is provisioned and the AD DC is running.  Next, configure DNS/Kerberos verification and test your deployment.
