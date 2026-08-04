# Host preparation and installation

This stage prepares a **dedicated, disposable Ubuntu 24.04 Server VM**. It does not configure a static address or firewall because those controls depend on the hypervisor and lab network. Complete them before allowing the script to mutate host identity.

## Preflight checklist

- The VM is fresh and contains no existing Samba domain, file-server configuration, or business data.
- The VM has a hypervisor snapshot or another recoverable pre-lab checkpoint.
- `DC_IP` is persistently assigned to the VM and reserved outside the dynamic DHCP pool.
- The short hostname is at most 15 characters and matches the first label of `DC_FQDN`.
- Forward and reverse DNS choices have been documented.
- The AD realm has been chosen permanently. Use a subdomain of a name you control for a durable environment; use a reserved name such as `ad.example.test` only in an isolated lab.
- The host can reach approved upstream DNS and NTP sources.
- The lab LAN is not bridged directly to an untrusted network.

Do not use `.local`; multicast DNS implementations reserve it and name resolution becomes unreliable. Do not use an employer, customer, or public production namespace for this lab.

## Configure a persistent address

Ubuntu networking can be managed by Netplan, NetworkManager, cloud-init, or the hypervisor. This repository does not guess which system owns the configuration. After setting the address through the appropriate owner, verify it:

```bash
ip -brief -4 address
ip route
resolvectl status
```

`10-prereqs.sh` refuses to continue unless `DC_IP` is already assigned to a global interface. That check proves current assignment, not persistence across reboot. Reboot once and repeat the commands if persistence is uncertain.

## Prepare repository configuration

```bash
cp scripts/00-env.example scripts/00-env
nano scripts/00-env
bash tests/static.sh
```

`scripts/00-env` is ignored by Git and must contain configuration only—never passwords, keys, tokens, tenant information, or other secrets. The allow-listed parser rejects duplicate or unknown keys and does not execute shell expressions.

## Apply host identity

Review the script, then run:

```bash
sudo bash scripts/10-prereqs.sh
```

The script:

1. Requires Ubuntu 24.04 and root privileges.
2. Validates the realm, NetBIOS name, FQDN, addresses, CIDR, and DNS forwarder.
3. Confirms the DC address is assigned.
4. Refuses conflicting `/etc/hosts` mappings.
5. Backs up `/etc/hostname` and `/etc/hosts` once under `/var/lib/samba-ad-dc-lab/original`.
6. Sets the **short** static hostname and adds the FQDN/LAN-address mapping when missing.
7. Confirms that the FQDN resolves to the configured address.

The script never removes an ambiguous host mapping. Resolve conflicts manually so aliases belonging to other services are not lost.

## Install packages and service roles

```bash
sudo bash scripts/20-install.sh
```

The package stage installs:

- `samba-ad-dc` for the unified AD DC service and `samba-tool`;
- `krb5-user` for Kerberos client tests;
- `bind9-dnsutils` for `host` and `dig`;
- `smbclient` for authenticated SYSVOL and NETLOGON tests;
- `chrony` for host synchronization and signed time to domain clients.

It stops and masks the standalone `smbd`, `nmbd`, and `winbind` units, then enables `samba-ad-dc` without starting it. It deliberately leaves the working DNS resolver intact until the domain has been provisioned and Samba DNS is ready.

## Network allow-list

Before a client joins, allow only the lab LAN and approved administrator sources. The principal AD ports are summarized in [Security and access model](security.md). Never expose LDAP, SMB, Kerberos, DNS, NTP, or dynamic RPC directly to the internet.

## Gate before provisioning

```bash
hostname
hostname -f
getent ahostsv4 "$(hostname -f)"
systemctl is-enabled samba-ad-dc
systemctl is-active samba-ad-dc || true
```

Expected state: the short and fully qualified names are correct, the FQDN resolves to `DC_IP`, `samba-ad-dc` is enabled but inactive, and the existing upstream resolver still works.
