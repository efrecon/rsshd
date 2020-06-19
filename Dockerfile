FROM alpine:3
MAINTAINER Emmanuel Frecon <efrecon@gmail.com>

RUN apk add --no-cache openssh-server-pam &&\
    addgroup -S autossh && \
    adduser -D -s /bin/true -G autossh autossh && \
    mkdir -p /home/autossh/.ssh && \
    chown -R autossh:autossh /home/autossh/ && \
    chmod 700 /home/autossh/.ssh

COPY sshd.sh /usr/local/bin/

# Expose the regular ssh port
EXPOSE 22
EXPOSE 10000-10100

# To set the password of the root user and activate the SSH root login
# ENV PASSWORD="xxx"

# You can modify the (internal) location to store the host keys
# with the following variable. You would probably want to expose the
# volume.
# ENV KEYS="/etc/ssh/keys"

# By default, the container allows external clients to jump into the tunnels from
# the outside (host, for example). If you want to turn off this behaviour,
# meaning that you will have to docker exec into the container before being able
# to jump into the tunnel, you could set the following variable.
# ENV LOCAL=1

# Where to store the host keys (to arrange for proper restarts/recreations)
VOLUME /etc/ssh/keys

# Where to store the list of authorised clients (good for restarts)
VOLUME /home/autossh/.ssh

ENTRYPOINT /usr/local/bin/sshd.sh
