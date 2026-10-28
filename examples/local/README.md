# Local example

Applies circuit-tailscale to a throwaway Rocky Linux 10 container with systemd. You need Conn3x and Podman.

`tailscaled` needs `/dev/net/tun`, so the host container runs privileged, which is simplest with rootful Podman. On a Mac, use the Podman machine's root connection. On Linux, use `sudo podman`:

```sh
export CONTAINER_CONNECTION=podman-machine-default-root   # macOS
export PODMAN="sudo podman"                               # Linux
./up.sh
conn3x init
conn3x apply
conn3x plan
```

By default the example installs Tailscale without joining a tailnet. The second plan says `No changes.` To look at the result:

```sh
ssh -p 2222 -i id_ed25519 -o UserKnownHostsFile=known_hosts root@127.0.0.1 tailscale status
```

To join the container to your tailnet, pass an auth key:

```sh
export TF_VAR_auth_key=tskey-auth-...
conn3x apply -var join=true
```

The node is named `conn3x-example` and advertises `10.88.0.0/16`. Joining with a real key hasn't been tested; see [Tested on](../../README.md#tested-on).

`up.sh` listens on `127.0.0.1:2222`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` removes the container, its volumes, the key and the state.
