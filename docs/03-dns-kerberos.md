# DNS, Kerberos, and signed time

Active Directory clients discover LDAP, Kerberos, password-change, and domain-controller services through DNS SRV records. Kerberos also depends on closely synchronized clocks. These are foundational dependencies, not optional polish.

## Activate Samba internal DNS

```bash
sudo bash scripts/40-dns-forwarder.sh
```

The script:

1. Confirms that the existing AD database matches the reviewed realm and NetBIOS domain.
2. Replaces duplicate `dns forwarder` entries with one validated unicast IPv4 target under `[global]`.
3. validates the candidate configuration with `testparm` before replacing `smb.conf`;
4. records whether `systemd-resolved` was enabled and active;
5. disables the stub resolver, writes a static resolver that uses Samba at `127.0.0.1`, and starts `samba-ad-dc`;
6. gives Samba DNS up to 30 seconds to become ready, then requires the service and DC A-record lookup to succeed;
7. restores the pre-run Samba configuration, resolver, and service state if activation fails.

The resulting dedicated-DC resolver is:

```text
nameserver 127.0.0.1
search ad.example.test
```

Do not add a public resolver as a second `nameserver`. Domain queries sent to a server that does not host the AD zone fail unpredictably rather than falling back cleanly. Samba forwards non-AD queries through `DNS_FORWARDER`.

Domain-joined clients must use the DC's **LAN address** as DNS, not `127.0.0.1` and not a public resolver. DHCP configuration is outside this repository.

## Verify service-discovery records

```bash
zone=ad.example.test
host -t A dc1.ad.example.test 127.0.0.1
host -t SRV "_ldap._tcp.${zone}" 127.0.0.1
host -t SRV "_kerberos._tcp.${zone}" 127.0.0.1
host -t SRV "_kerberos._udp.${zone}" 127.0.0.1
host -t SRV "_kpasswd._udp.${zone}" 127.0.0.1
host -t A example.com 127.0.0.1
```

The SRV responses must name the configured DC and return ports 389, 88, 88, and 464 respectively. If records are absent, use `sudo samba_dnsupdate --verbose` for diagnosis; do not fabricate DNS records until the cause is understood.

Samba does not create a reverse zone automatically. Add the subnet-specific reverse zone and DC PTR record only after confirming ownership and prefix boundaries, following the official [Samba DNS administration guidance](https://wiki.samba.org/index.php/DNS_Administration). Reverse-zone automation is intentionally out of scope because the repository cannot safely infer the network's delegation model.

## Kerberos authentication

Obtain a ticket as a normal interactive user, not through an automation secret:

```bash
kinit Administrator@AD.EXAMPLE.TEST
klist
```

Destroy the ticket cache after testing:

```bash
kdestroy
```

Common causes of `Cannot find KDC`, `Clock skew too great`, and client-not-found errors are wrong DNS, a mismatched realm, an unreadable `/etc/krb5.conf`, and unsynchronized time.

## Configure signed domain time

Windows domain members normally use the AD time hierarchy. Samba provides Microsoft signed NTP responses through its `ntp_signd` socket; Chrony serves them only to explicitly allowed clients.

```bash
sudo bash scripts/45-time-sync.sh
```

The script creates `/etc/chrony/conf.d/samba-ad-dc-lab.conf` with:

```text
allow 10.20.30.0/24
ntpsigndsocket /var/lib/samba/ntp_signd
```

It also restricts the socket directory to `root:_chrony`, validates the expanded Chrony configuration, starts the service, and displays tracking data. `LAN_CIDR` must be the narrowest subnet containing lab clients. Apply the same restriction to UDP/123 in the host and network firewalls.

Signed-time requests are not themselves authenticated before a signed response is returned, so exposing the service broadly increases password-cracking risk. Never use `allow all` for this lab.

Verify:

```bash
chronyc tracking
chronyc sources -v
sudo ss -lunp | grep ':123'
sudo stat /var/lib/samba/ntp_signd/socket
```

Move next to [Verification and evidence](04-verify.md).
