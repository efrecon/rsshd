FROM alpine:3.23
LABEL org.opencontainers.image.authors="Emmanuel Frecon <efrecon+github@gmail.com>"

RUN apk --no-cache add openssh-server-pam && \
    addgroup -S autossh && \
    adduser -D -G autossh autossh && \
    mkdir -p /home/autossh/.ssh && \
    chown -R autossh:autossh /home/autossh/ && \
    chmod 700 /home/autossh/.ssh

COPY --chmod=755 *.sh /usr/local/bin/

# Expose the regular ssh port
EXPOSE 22
EXPOSE 10000-10100

# When password is set to "-", the user will be the autossh user with no login.
# When password is set, it will be used as the password for the autossh user.
# When empty, a password will be generated and set for the autossh user.
# ENV AUTOSSH_PASSWORD="-"

# You can modify the (internal) location to store the host keys
# with the following variable. You would probably want to expose the
# volume.
# ENV AUTOSSH_KEYS="/etc/ssh/keys"

# By default, the container allows external clients to jump into the tunnels from
# the outside (host, for example). If you want to turn off this behaviour,
# meaning that you will have to docker exec into the container before being able
# to jump into the tunnel, you could set the following variable.
# ENV AUTOSSH_LOCAL=1

# Where to store the host keys (to arrange for proper restarts/recreations)
VOLUME /etc/ssh/keys

# Where to store the list of authorised clients (good for restarts)
VOLUME /home/autossh/.ssh


ENTRYPOINT [ "/usr/local/bin/autossh.sh", "--" ]
