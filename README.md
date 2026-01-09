# RsshD

This provides a minimal Docker container for keeping the connections to remote servers that are placed behind (several layers) of NATed networks.
I use this to keep track of Raspberry Pis, "in the wild" and behind mobile connections.
It can be used as an open replacement for Raspberry Pi [Connect][connect].
The image sacrifices a little bit of security for ease of use, but this can be turned off.

The idea is to provide a dockerised sshd on top of [Alpine].
Remote ssh clients will open reverse tunnels to the exposed host (running the docker container).
You will then be able to log into the remote servers via the reverse tunnels, i.e. via the exposed host.
Inside the container, a user called `autossh` is used.

As long as you carefully mount host directories (or volumes) through the `-v` option,
you will be able to keep your settings between restarts.
Let's take a real life example to kickstart the description:

```bash
  docker run \
    -it \
    --rm \
    -p 2222:22 \
    --name rsshd \
    -p 10000-10100:10000-10100 \
    -v /opt/keys/host:/etc/ssh/keys \
    -v /opt/keys/clients:/home/autossh/.ssh \
      efrecon/rsshd
```

This example would:

* Start a container listening for incoming ssh connections on port `2222`.
* Be able to accept 101 clients, through exposing ports `10000` to `10100`.
  These will be the ports to which you will direct ssh connection on the host once everything is setup.
* Mount the host keys onto the `/opt/keys/host` on the host computer.
  This enables to keep the same keys at every restart of the container.
  The keys are generated if they do not exist whenever the container is started.
* Mount the list of authorised clients (your servers!) in the host directory at `/opt/keys/clients`,
  to pertain on restarts.
* The command runs in interactive mode,
  but you will probably want to replace the options `-it --rm` with,
  at least `-d` and even perhaps `-d --restart=always` to make sure your remote servers can always connect.

  [connect]: https://www.raspberrypi.com/software/connect/
  [Alpine]: http://www.alpinelinux.org/

## Connecting from remote servers

To test things out, from a remote server, you could issue a command such as the following.
The command supposes that you can access your server on `domain.tld`
and that its firewall permits connections on port `2222`.

```bash
  ssh -p 2222 autossh@domain.tld
```

If you have not created a `/opt/keys/clients/authorized_keys` file,
you will be asked for (an inexisting) password three times and the connection will then be closed.

If you append the content of your public key to the end of `/opt/keys/clients/authorized_keys`,
the command should show the Alpine default message of the day.
Then it will close the connection with the following message:

```output
This account is not available.
```

This is because, by default, the `autossh` account has no login shell.

However, to open a permanent tunnel, you would rather enter a command such as:

```bash
  ssh -fN -R 10000:localhost:22 -p 2222 autossh@domain.tld
```

This would create a reverse tunnel on port `10000`.
`10000` is the first port of the block of ports exposed by the container in the example.
You can then connect to your server from the host running the docker container using a command as below.
(`user` being a user on the remote server).

```bash
  ssh -p 10000 user@localhost
```

## Keeping the Connection at all times

Using [`autossh`][autossh] and through making sure you can login without the need for a password,
you should be able to keep those connections alive for longer periods of time.
More information is available in this [guide],
but in summary you should perform the following steps:

1. On the remote server, create a key for the user if necessary.
2. Append it to the `authorized_keys` file mounted into the `/home/autossh/.ssh` directory of the container.
3. To keep the connection open at all times through `autossh`, issue the following:

```bash
  autossh \
    -M 10099 \
    -fN \
    -o "PubkeyAuthentication=yes" \
    -o "StrictHostKeyChecking=false" \
    -o "PasswordAuthentication=no" \
    -o "ServerAliveInterval 60" \
    -o "ServerAliveCountMax 3" \
    -R 10000:localhost:22 \
    -p 2222 \
    autossh@domain.tld
```

On a RaspberryPi, adding this line to `/etc/rc.local` will ensure that the connection is kept alive at all times.

  [autossh]: https://www.harding.motd.ca/autossh/
  [guide]: http://xmodulo.com/access-linux-server-behind-nat-reverse-ssh-tunnel.html

## Improving Security

If you set the environment variable `AUTOSSH_LOCAL` to `1`, e.g. `-e AUTOSSH_LOCAL=1`
when starting with `docker run`,
you will not be able to access the tunnels from outside the container.
Instead, you will have to jump in the container with `docker exec -it rsshd ash` and,
from within, issue commands such as:

```bash
  ssh -p 10000 user@localhost
```

This provides complete encapsulation, at the expense of another layer of
"jumping" whenever you need to access your servers.
