variable "port" {
  type    = number
  default = 2222
}

# Leave both unset to install Tailscale without joining. To join, pass
# -var join=true and the key in TF_VAR_auth_key.
variable "join" {
  type    = bool
  default = false
}

variable "auth_key" {
  type      = string
  default   = null
  ephemeral = true
}

# CI points this at its own control server with --login-server.
variable "extra_args" {
  type    = list(string)
  default = []
}

module "tailscale" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  join             = var.join
  auth_key         = var.auth_key
  extra_args       = var.extra_args
  hostname         = "conn3x-example"
  advertise_routes = ["10.88.0.0/16"]
  ssh              = true
}
