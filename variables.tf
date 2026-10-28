variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}


variable "join" {
  type        = bool
  default     = true
  description = "Join the hosts to the tailnet with auth_key. When false, the circuit installs Tailscale and leaves the hosts logged out."
}

variable "auth_key" {
  type        = string
  default     = null
  ephemeral   = true
  sensitive   = true
  description = "Tailscale auth key the hosts join the tailnet with, such as tskey-auth-.... Required when join is true."

  validation {
    condition     = !var.join || (var.auth_key != null && var.auth_key != "")
    error_message = "Set auth_key, or set join = false to install Tailscale without joining."
  }
}

variable "hostname" {
  type        = string
  default     = null
  description = "Name for the node in the tailnet. When null, Tailscale uses the host's name. Meant for a single host: every host gets the same name."

  validation {
    condition     = var.hostname == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$", coalesce(var.hostname, "-")))
    error_message = "hostname must be letters, digits and -, such as \"nas\", up to 63 characters."
  }
}

variable "advertise_routes" {
  type        = list(string)
  default     = []
  description = "Subnets to offer the tailnet as a subnet router, such as [\"192.168.1.0/24\"]. Turns on IP forwarding."

  validation {
    condition     = alltrue([for r in var.advertise_routes : can(cidrhost(r, 0))])
    error_message = "Each of advertise_routes must be a CIDR block such as \"192.168.1.0/24\"."
  }
}

variable "advertise_exit_node" {
  type        = bool
  default     = false
  description = "Offer the hosts as exit nodes. Turns on IP forwarding."
}

variable "accept_routes" {
  type        = bool
  default     = false
  description = "Use subnet routes other nodes advertise."
}

variable "ssh" {
  type        = bool
  default     = false
  description = "Run Tailscale SSH, so the tailnet's access rules decide who can log in over SSH from the tailnet."
}

variable "tags" {
  type        = list(string)
  default     = []
  description = "ACL tags to advertise when joining, such as [\"tag:server\"]. The auth key must be allowed to apply them."

  validation {
    condition     = alltrue([for t in var.tags : can(regex("^tag:[a-zA-Z0-9][a-zA-Z0-9-]*$", t))])
    error_message = "Each of tags must look like \"tag:server\"."
  }
}

variable "extra_args" {
  type        = list(string)
  default     = []
  description = "More flags for tailscale up, such as [\"--shields-up\"]. Used only when joining."

  validation {
    condition     = alltrue([for a in var.extra_args : can(regex("^--[a-z0-9-]+(=[A-Za-z0-9_.,:/@+=-]*)?$", a))])
    error_message = "Each of extra_args must be one flag such as \"--shields-up\" or \"--exit-node=100.64.0.1\", without spaces or quotes."
  }
}
