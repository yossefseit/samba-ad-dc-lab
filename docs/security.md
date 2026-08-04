# Security and access model

## Trust boundaries

The design assumes one isolated lab LAN, one dedicated DC, one disposable Windows client, approved administrator access, explicitly chosen upstream DNS/NTP, and encrypted offline backup storage. No service is intended to be reachable from the public internet or an employer/customer network.

## Principal ports

Allow only required sources and destinations. Samba can also use dynamic RPC ports; consult the current official port reference before implementing a firewall.

| Service | Protocol/port | Intended source |
| --- | --- | --- |
| DNS | TCP and UDP 53 | Lab domain members |
| Kerberos | TCP and UDP 88 | Lab domain members |
| Signed NTP | UDP 123 | `LAN_CIDR` only |
| RPC endpoint mapper | TCP 135 | Lab domain members / RSAT |
| NetBIOS (when required) | UDP 137–138, TCP 139 | Lab LAN only |
| LDAP | TCP and UDP 389 | Lab domain members / RSAT |
| SMB | TCP 445 | Lab domain members / RSAT |
| Kerberos password change | TCP and UDP 464 | Lab domain members |
| LDAPS / Global Catalog | TCP 636, 3268, 3269 | Lab domain members / RSAT as required |
| Dynamic RPC | TCP 49152–65535 | Lab domain members / RSAT as required |
| SSH administration | TCP 22 | Named administrator sources only |

See [Samba AD DC Port Usage](https://wiki.samba.org/index.php/Samba_AD_DC_Port_Usage) for the current authoritative list. Do not open the full table globally.

## Controls implemented in code

- Allow-listed, non-evaluating configuration parser.
- No secret configuration keys or example passwords.
- Interactive password entry for provisioning, users, and online backup.
- Dedicated-service role: standalone Samba daemons are masked.
- Internal AD DNS with validated non-recursive forwarder selection.
- Transactional Samba configuration and resolver rollback on failed DNS activation.
- Chrony access narrowed to `LAN_CIDR` and the signed socket protected by group permissions.
- Existing-domain match checks before provisioning reruns.
- Report-only integrity verification; no automatic database repair.
- Root-only host state and backup directories.

## Threats and mitigations

| Threat | Mitigation | Remaining risk |
| --- | --- | --- |
| Password committed or exposed in process arguments | Interactive prompts; password keys rejected from config | Terminal/session capture and operator handling remain in scope |
| Rogue DNS path breaks or intercepts AD discovery | Clients use only the DC; upstream is used only for non-AD forwarding | Upstream trust and DNSSEC strategy are not implemented |
| NTP signed-response abuse | `allow` limited to lab CIDR; firewall restriction required | LAN clients can still request signed responses |
| Accidental reprovision or wrong realm | Existing database and config match guard | First provision remains a privileged, stateful operation |
| Destructive cleanup | No automatic database teardown; disposable VM recommended | Manual hypervisor/storage mistakes remain possible |
| Loss of sole DC | Online backup and restore drill documented | No second DC or replication availability |
| Broad administrative privilege | Credentials prompted and no defaults weakened | Lab Administrator remains highly privileged; delegation is future work |

## Production-hardening gaps

This lab is not a production reference architecture. It lacks a second DC, replication monitoring, centralized log collection and alerting, a certificate lifecycle, delegated administration, privileged-access workstations, systematic patching, vulnerability management, tested site/subnet design, automated firewall policy, DHCP secure-update design, hardware-backed secret protection, backup retention automation, and measured recovery objectives.

Do not weaken SMB signing, Kerberos, password complexity, or host firewall controls to make a test pass. Diagnose the dependency instead.
