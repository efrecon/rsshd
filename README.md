# RsshD

This provides a minimal Docker container for keeping the connections to remote
servers that are placed behind (several layers) of NATed networks. I use this to
keep track of Raspberry Pis, "in the wild" and behind mobile connections. The
image sacrifices a little bit of security for ease of use, but this can be
turned off.

The idea is to provide a dockerised sshd (on top of
[Alpine](http://www.alpinelinux.org/)), remote servers will open a reverse ssh
tunnels to the exposed host (running the docker container) and you will then be
able to log into the remote servers via the reverse tunnels, i.e. via the
exposed host.

As long as you carefully mount host directories through the `-v` option, you
will be able to keep your settings between restarts. Let's take a real life
example to kickstart the description:

    docker run -it --rm -p 2222:22 --name rsshd -p 10000-10100:10000-10100 -e PASSWORD=secret -v /opt/keys/host:/etc/ssh/keys -v /opt/keys/clients:/root/.ssh efrecon/rsshd
    
This example would:

* Start a container listening for incoming ssh connections on port `2222`.
* Be able to accept 101 clients, through exposing ports `10000` to `10100`.
  These will be the ports to which you will direct ssh connection on the host
  once everything is setup.
* Arrange to give a "very secret" password to the `root` user within the
  Alpine-based container. This is because Alpine has no default password for
  `root` and because this is probably not a very good idea, and not something
  that is supported by ssh. If you do not provide a password, one will be
  generated randomly at start, and printed to the logs for capture and use.
* Mount the host keys onto the `/opt/keys/host` on the host computer. This
  enables to keep the same keys at every restart of the container. The keys are
  generated if they do not exist whenever the container is started.
* Mount the list of authorised clients (your servers!) in the host directory at
  `/opt/keys/clients`, to pertain restarts.
* The command run in interactive mode, but you will probably want to replace the
  options `-it --rm`, with at least `-d` and even perhaps `-d --restart=always`
  to make sure your remote servers can always connect.
  
## Connecting from remote servers

To test things out, from a remote server, you could issue a command such as:

    ssh -p 2222 root@domain.tld
    
The command will prompt you for the password of the `root` user in the container
(e.g. `secret` in the previous example) and let you in. The command supposes
that you can access your server on `domain.tld` and that its firewall permits
connections on port `2222`. However, to open a permanent tunnel, you would
rather enter a command such as:

    ssh -fN -R 10000:localhost:22 -p 2222 root@domain.tld
    
This would create a reverse tunnel on port `10000` so you can connect to your
server from the host running the docker container using (`user` being a user on
the remote server):

    ssh -p 10000 user@localhost

## Keeping the Connection at all times

Using `autossh` and through making sure you can login without the need for a
password, you should be able to keep those connections alive for longer periods
of time. More information is available in this
[guide](http://xmodulo.com/access-linux-server-behind-nat-reverse-ssh-tunnel.html),
but in summary you should perform the following steps:

On the remote server, create the DSA key (if necessary) and copy it to the host running the
container through the following commands:

    ssh-keygen -t rsa
    ssh-copy-id -i ~/.ssh/id_rsa.pub -p 2222 root@domain.tld
    
To keep the connection open at all times through `autossh`, issue the following:

    autossh -M 10099 -fN -o "PubkeyAuthentication=yes" -o "StrictHostKeyChecking=false" -o "PasswordAuthentication=no" -o "ServerAliveInterval 60" -o "ServerAliveCountMax 3" -R 10000:localhost:22 -p 2222 root@domain.tld

On a RaspberryPi, adding this line to `/etc/rc.local` will ensure that the
connection is kept alive at all times.

## Improving Security

If you set the environment variable `LOCAL` to `1`, e.g. `-e LOCAL=1` when
starting with `docker run`, you will not be able to access the tunnels from
outside the container. Instead, you will have to jump in the container with
`docker exec -it rsshd ash` and from within, issue commands such as:

    ssh -p 10000 user@localhost
    
This provides complete encapsulation, at the expense of another layer of
"jumping" whenver you need to access your servers.



