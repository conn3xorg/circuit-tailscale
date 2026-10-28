# Facts give each host's distribution, which picks Tailscale's repository.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }
}

locals {
  # Tailscale publishes one repository per distribution, all signed with the
  # same key. Rocky Linux and AlmaLinux use the RHEL one. apt needs the
  # release's codename.
  repo     = { rocky = "rhel/$releasever", almalinux = "rhel/$releasever", rhel = "rhel/$releasever", centos = "rhel/$releasever", fedora = "fedora", ubuntu = "ubuntu", debian = "debian" }
  codename = { "22.04" = "jammy", "24.04" = "noble", "26.04" = "resolute", "12" = "bookworm", "13" = "trixie" }

  hosts = {
    for name, f in data.conn3x_host.facts : name => {
      url    = f.os_family == "redhat" ? "https://pkgs.tailscale.com/stable/${local.repo[f.os_id]}/$basearch" : "https://pkgs.tailscale.com/stable/${local.repo[f.os_id]}"
      suites = f.os_family == "redhat" ? null : [local.codename[f.os_version]]
    }
  }

  key_file = "/etc/tailscale/authkey"

  # Settings tailscale set can change on a node that has already joined.
  settings = join(" ", compact([
    var.hostname == null ? "" : "--hostname='${var.hostname}'",
    "--advertise-routes='${join(",", var.advertise_routes)}'",
    "--advertise-exit-node=${var.advertise_exit_node}",
    "--accept-routes=${var.accept_routes}",
    "--ssh=${var.ssh}",
  ]))

  # tailscale up also takes the tags and extra_args, which only apply at join.
  up = join(" ", compact([
    "tailscale up --auth-key=file:${local.key_file}",
    local.settings,
    length(var.tags) == 0 ? "" : "--advertise-tags='${join(",", var.tags)}'",
    join(" ", var.extra_args),
  ]))

  forwarding = length(var.advertise_routes) > 0 || var.advertise_exit_node ? toset(["net.ipv4.ip_forward", "net.ipv6.conf.all.forwarding"]) : toset([])
}

circuit "tailscale" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "repo" {
    repository {
      name   = "tailscale-stable"
      url    = local.hosts[each.key].url
      key    = file("${path.module}/files/tailscale.asc")
      suites = local.hosts[each.key].suites
    }
  }

  step "package" {
    package {
      name = "tailscale"
    }
  }

  step "running" {
    service {
      name    = "tailscaled"
      state   = "started"
      enabled = true
    }
  }

  # A subnet router or exit node forwards traffic for the tailnet.
  step "forwarding" {
    for_each = local.forwarding
    sysctl {
      name  = item.value
      value = "1"
    }
  }

  step "key_dir" {
    for_each = var.join ? toset(["key"]) : toset([])
    directory {
      path = "/etc/tailscale"
      mode = "0700"
    }
  }

  step "auth_key" {
    for_each = var.join ? toset(["key"]) : toset([])
    file {
      path       = local.key_file
      content_wo = var.auth_key
    }
  }

  # Joins the tailnet, unless the node is already logged in.
  step "up" {
    for_each = var.join ? toset(["key"]) : toset([])
    command {
      command = local.up
      unless  = "tailscale status --json | grep -Eq '\"BackendState\": *\"Running\"'"
    }
  }

  # Applies changed settings to a node that has already joined.
  step "settings" {
    command {
      command  = "tailscale set ${local.settings}"
      triggers = { settings = local.settings }
    }
  }
}
