# circuit-tailscale

A Conn3x circuit that installs [Tailscale](https://tailscale.com) from Tailscale's own package repository, keeps `tailscaled` running, and joins your hosts to your tailnet. Point it at a NAS, a Proxmox box or a fleet of VPS hosts, and it runs `tailscale up` on each one with the name, routes and Tailscale SSH setting you gave it, so nobody has to do it by hand.

The auth key comes in through an ephemeral variable, so it never lands in state or a plan.

## Usage

```hcl
module "tailscale" {
  source = "github.com/conn3xorg/circuit-tailscale?ref=v0.1.0"

  hosts                = { nas = "192.168.1.20" }
  ssh_private_key_file = "~/.ssh/id_ed25519"

  auth_key         = var.tailscale_auth_key
  advertise_routes = ["192.168.1.0/24"]
  ssh              = true
  tags             = ["tag:server"]
}

variable "tailscale_auth_key" {
  type      = string
  ephemeral = true
}
```

Make an auth key in the Tailscale admin console under **Settings > Keys**, and pass it at run time with `TF_VAR_tailscale_auth_key` or `-var tailscale_auth_key=...`. A reusable key suits several hosts. To use `tags`, the key has to be allowed to apply them.

Then run `conn3x init` and `conn3x apply`. A second `conn3x plan` says `No changes.`

Routes you advertise still need approving in the admin console, unless your tailnet's auto-approvers cover them. The same goes for an exit node.

### Join once, then set join = false

While `join` is true, every plan needs `auth_key`. Auth keys expire after 90 days at most, so a plan you run months later would fail for want of a key, and passing a fresh one shows up as a change to the key file. The intended flow is:

1. Apply once with `join = true` and a key. The hosts join.
2. Set `join = false` and apply again. Conn3x deletes `/etc/tailscale/authkey` from each host and drops the join steps from state. The hosts stay logged in: removing the join step doesn't run anything on them.
3. From then on, plan and apply without a key. Changes to `hostname`, `advertise_routes`, `advertise_exit_node`, `accept_routes` and `ssh` still reach the hosts through `tailscale set`.

To add a host later, set `join = true` with a new key for that apply, then back to false. Hosts that are already in the tailnet skip `tailscale up`.

To install Tailscale and leave the hosts logged out, say for a machine you'll join by hand, set `join = false` from the start and leave out `auth_key`.

For hosts created in the same plan, pass host objects with the host key you generated, so Conn3x checks it without a known_hosts entry:

```hcl
hosts = {
  for name, d in digitalocean_droplet.app : name => {
    address  = d.ipv4_address
    host_key = tls_private_key.host[name].public_key_openssh
  }
}
```

To try it on a throwaway container first, see [examples/local](examples/local).

## What it does

On each host, in order:

1. Adds Tailscale's stable repository and signing key: `pkgs.tailscale.com/stable/rhel` on Rocky Linux, AlmaLinux and RHEL, and the `fedora`, `ubuntu` or `debian` one elsewhere. The key is in [files](files), copied from Tailscale's site. Every one of these repositories is signed with it.
2. Installs `tailscale`, and starts `tailscaled` now and at boot.
3. When `advertise_routes` is set or `advertise_exit_node` is true, sets `net.ipv4.ip_forward` and `net.ipv6.conf.all.forwarding` to `1`, now and across reboots.
4. When `join` is true, writes `auth_key` to `/etc/tailscale/authkey`, mode `0600`, and runs `tailscale up --auth-key=file:/etc/tailscale/authkey` with your settings. It skips this when `tailscale status` already reports the node as running, so a host that has joined isn't logged in again.
5. Runs `tailscale set` with `hostname`, `advertise_routes`, `advertise_exit_node`, `accept_routes` and `ssh`, the first time and again whenever one of them changes. That's how a change reaches a node that has already joined.

Before the circuit runs, the `conn3x_host` data source reads each host's distribution over SSH. On Debian and Ubuntu it picks the apt suite from the release: Ubuntu 22.04, 24.04 and 26.04, and Debian 12 and 13. Another release fails the plan.

### What it doesn't do

- **`tags` and `extra_args` apply only when a host joins.** `tailscale set` can't change them, so changing either on a joined host does nothing. Run `tailscale up` with the new flags on the host, or log it out and apply again.
- **Removing a setting doesn't always undo it.** Set `hostname` back to null and the node keeps the name it had. Turning off forwarding leaves the sysctls at `1`.
- **The key stays on disk while `join` is true.** `/etc/tailscale/authkey` is root-only. Setting `join = false` deletes it; the empty `/etc/tailscale` directory stays.
- **It doesn't log hosts out.** Removing the module, or setting `join = false`, leaves a joined host in the tailnet.
- **`hostname` names every host the same.** Use it with a single host, or leave it null to take each host's own name.
- **It doesn't touch the host firewall**, or approve routes and exit nodes for you.

## Inputs

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `hosts` | any | Required | Hosts to configure, by name. Each value is an address, such as `"203.0.113.10"`, or a host object such as `{ address = "203.0.113.10", host_key = "ssh-ed25519 AAAA..." }`. A host object can also set `user`, `port`, `private_key_file` and `jump_hosts`. The two forms can be mixed. |
| `ssh_user` | string | `"root"` | User to log in as. |
| `ssh_port` | number | `22` | SSH port. |
| `ssh_private_key_file` | string | `null` | Path to a private key. When null, Conn3x uses the SSH agent. |
| `ssh_known_hosts_file` | string | `null` | known_hosts file to check host keys against. When null, `~/.ssh/known_hosts`. Not used for a host object with `host_key`. |
| `ssh_become` | bool | `false` | Run commands as root through sudo. Set it when `ssh_user` isn't root. |
| `join` | bool | `true` | Join the hosts to the tailnet with `auth_key`. When false, install Tailscale only. |
| `auth_key` | string | `null` | Auth key to join with, such as `tskey-auth-...`. Ephemeral and sensitive. Required when `join` is true. |
| `hostname` | string | `null` | Name for the node in the tailnet: letters, digits and `-`. When null, the host's own name. |
| `advertise_routes` | list(string) | `[]` | Subnets to offer the tailnet, such as `["192.168.1.0/24"]`. Each must be a CIDR block. Turns on IP forwarding. |
| `advertise_exit_node` | bool | `false` | Offer the hosts as exit nodes. Turns on IP forwarding. |
| `accept_routes` | bool | `false` | Use subnet routes other nodes advertise. |
| `ssh` | bool | `false` | Run Tailscale SSH on the hosts. |
| `tags` | list(string) | `[]` | ACL tags to advertise when joining, such as `["tag:server"]`. |
| `extra_args` | list(string) | `[]` | More flags for `tailscale up`, such as `["--shields-up"]`. One flag per item, no spaces or quotes. Used only when joining. |

`join` is separate from `auth_key` because OpenTofu won't let a step's count depend on an ephemeral value.

## Outputs

None.

## Requirements

Requires Conn3x v0.6.5 or later and systemd on each host, with outbound HTTPS to pkgs.tailscale.com and to Tailscale's coordination servers. In a container, the host needs `/dev/net/tun`.

## Tested on

Rocky Linux 10, Fedora 45, Ubuntu 24.04 and Debian 13. CI applies [examples/local](examples/local) to each on amd64 with `join = false`, checks that the second plan has no changes, and checks that `tailscaled` is running, `tailscale version` answers and forwarding is on. The CI containers run with SELinux off. The same checks also passed by hand on a Rocky Linux 10 droplet with SELinux enforcing, with no denials in the audit log.

Joining a tailnet isn't covered by CI, because it needs a real auth key. It was tried by hand only as far as Tailscale rejecting a fake key, which shows the key reaches `tailscale up` and stays out of state and the plan, and as far as switching `join` to false afterwards, which deleted the key file and left the next plan empty. A successful join with a real key hasn't been tested.

## License

MPL-2.0. See [LICENSE](LICENSE). Tailscale's client is BSD-3-Clause.
