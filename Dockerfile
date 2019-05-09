FROM alpine:3.9
MAINTAINER Emmanuel Frecon <efrecon@gmail.com>

RUN apk --update add openssh
COPY sshd.sh /usr/local/bin/

# Expose the regular ssh port
EXPOSE 22
EXPOSE 10000-10100

# To set the password of the root user (Alpine has no password per
# default!) use the following variable.  Otherwise, a password will
# be generated and output in the log.
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
VOLUME /root/.ssh


ENTRYPOINT /usr/local/bin/sshd.sh