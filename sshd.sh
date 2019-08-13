#!/usr/bin/env ash

# This is the main startup script for the running sshd to keep client
# tunnels.

# Settings directory
SDIR=/etc/ssh

# Make sure we have a root password, since Alpine does not have a root
# password by default and we want to have this minimal level of security
if [ -z "$PASSWORD" ]; then
    PASSWORD=$(< /dev/urandom tr -dc A-Z-a-z-0-9 | head -c8)
    echo "==========="
    echo "== Root Password is $PASSWORD"
    echo "==========="
    echo
fi
echo "root:${PASSWORD}" | chpasswd

# Directory for HOSTKEYS, create if necessary
if [ -z "$KEYS" ]; then
    KEYS=$SDIR/keys
fi
if [ ! -d $KEYS ]; then
    mkdir -p $KEYS
fi

# Generate server keys, if necessary. ssh-keygen generates the keys in the
# default directory, not where we want the keys, so we move the keys once they
# have been generated.
if [ ! -f "${KEYS}/ssh_host_rsa_key" ]; then
    # One shot generation, -A really is for init.d style startup script, but
    # this is what we sort of are.
    ssh-keygen -A
    
    # Move the keys to the location that we want
    if [ -f "$SDIR/ssh_host_rsa_key" ]; then
        mv $SDIR/ssh_host_rsa_key $KEYS/ssh_host_rsa_key
        mv $SDIR/ssh_host_rsa_key.pub $KEYS/ssh_host_rsa_key.pub
    fi
    if [ -f "$SDIR/ssh_host_dsa_key" ]; then
        mv $SDIR/ssh_host_dsa_key $KEYS/ssh_host_dsa_key
        mv $SDIR/ssh_host_dsa_key.pub $KEYS/ssh_host_dsa_key.pub
    fi
    if [ -f "$SDIR/ssh_host_ecdsa_key" ]; then
        mv $SDIR/ssh_host_ecdsa_key $KEYS/ssh_host_ecdsa_key
        mv $SDIR/ssh_host_ecdsa_key.pub $KEYS/ssh_host_ecdsa_key.pub
    fi
    if [ -f "$SDIR/ssh_host_ed25519_key" ]; then
        mv $SDIR/ssh_host_ed25519_key $KEYS/ssh_host_ed25519_key
        mv $SDIR/ssh_host_ed25519_key.pub $KEYS/ssh_host_ed25519_key.pub
    fi
fi

# Arrange for the config to point at the proper server keys, i.e. at the proper
# location
if [ -f "$KEYS/ssh_host_rsa_key" ]; then
    sed -i "s;\#HostKey $SDIR/ssh_host_rsa_key;HostKey $KEYS/ssh_host_rsa_key;g" $SDIR/sshd_config
fi
if [ -f "$KEYS/ssh_host_dsa_key" ]; then
    sed -i "s;\#HostKey $SDIR/ssh_host_dsa_key;HostKey $KEYS/ssh_host_dsa_key;g" $SDIR/sshd_config
fi
if [ -f "$KEYS/ssh_host_ecdsa_key" ]; then
    sed -i "s;\#HostKey $SDIR/ssh_host_ecdsa_key;HostKey $KEYS/ssh_host_ecdsa_key;g" $SDIR/sshd_config
fi
if [ -f "$KEYS/ssh_host_ed25519_key" ]; then
    sed -i "s;\#HostKey $SDIR/ssh_host_ed25519_key;HostKey $KEYS/ssh_host_ed25519_key;g" $SDIR/sshd_config
fi

# Allow external hosts to connect
if [ -z "$LOCAL" -o "$LOCAL" == 0 ]; then
    sed -i "s;\GatewayPorts no;GatewayPorts yes;g" $SDIR/sshd_config
    sed -i "s;\AllowTcpForwarding no;AllowTcpForwarding yes;g" $SDIR/sshd_config
fi

# Allow root login if a password was set.
if [ -n "${PASSWORD}" ]; then
    sed -i "s;\#PermitRootLogin .*;PermitRootLogin yes;g" $SDIR/sshd_config
fi

# Fix permissions and access to the .ssh directory (in case it was shared with
# the host)
chown root $HOME/.ssh
chmod 755 $HOME/.ssh

# Absolute path necessary! Pass all remaining arguents to sshd. This enables to
# override some options through -o, for example.
/usr/sbin/sshd -f ${SDIR}/sshd_config -D -e "$@"
