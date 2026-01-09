#!/bin/sh


set -eu
# shellcheck disable=SC3040 # now part of POSIX, but not everywhere yet!
if set -o | grep -q 'pipefail'; then set -o pipefail; fi

# Main SSHd settings directory
: "${AUTOSSH_SDIR:="/etc/ssh"}"

# Location of host keys
: "${AUTOSSH_KEYS:="${AUTOSSH_SDIR%%/}/keys"}"

# Location of the main SSHd config file. Our configuration will be placed in the
# first directory included from this file.
: "${AUTOSSH_SSHD_CONFIG:="${AUTOSSH_SDIR%%/}/sshd_config"}"

# Password for the autossh user. When set to "-", the user will have no login.
# When empty, a password will be generated and output in the log.
: "${AUTOSSH_PASSWORD:="-"}"

# When set to 1, only allow local connections (no GatewayPorts, no remote
# forwarding)
: "${AUTOSSH_LOCAL:=0}"

# Fully resolve location of the SSHd binary. Will be used to launch sshd at
# the end of this script.
: "${AUTOSSH_SSHD_BIN:="$(command -v sshd.pam || command -v sshd)"}"

# Verbosity level, can be increased with -v option
: "${AUTOSSH_VERBOSE:=0}"



usage() {
  # This uses the comments behind the options to show the help. Not extremely
  # correct, but effective and simple.
  echo "$0 sets up sshd and run it." && \
    grep "[[:space:]].)[[:space:]][[:space:]]*#" "$0" |
    sed 's/#//' |
    sed -E 's/([a-zA-Z-])\)/-\1/'
  printf \\nEnvironment:\\n
  set | grep '^AUTOSSH_' | sed 's/^AUTOSSH_/    AUTOSSH_/g'
  exit "${1:-0}"
}

# Parse named arguments using getopts
while getopts ":p:lvh-" opt; do
  case "$opt" in
    p) # Password for the autossh user. When set to "-", the user will have no login. When empty, a password will be generated and output in the log.
      AUTOSSH_PASSWORD=$OPTARG;;
    l) # Only allow local connections (no GatewayPorts, no remote forwarding)
      AUTOSSH_LOCAL=1;;
    -) # End of options, everything after is blindly passed to sshd.
      break;;
    v) # Increase verbosity each time repeated
      AUTOSSH_VERBOSE=$(( AUTOSSH_VERBOSE + 1 ));;
    h) # Show this help
      usage 0;;
    *)
      usage 1;;
  esac
done
shift $((OPTIND-1))


# PML: Poor Man's Logging on stderr
_log() {
  printf '[%s] [%s] [%s] ' \
    "$(basename "$0")" \
    "${1:-LOG}" \
    "$(date +'%Y%m%d-%H%M%S')" \
    >&2
  shift
  _fmt="$1"
  shift
  # shellcheck disable=SC2059 # ok, we want to use printf format
  printf "${_fmt}\n" "$@" >&2
}
trace() { [ "$AUTOSSH_VERBOSE" -ge "2" ] && _log DBG "$@" || true ; }
info() { [ "$AUTOSSH_VERBOSE" -ge "1" ] && _log NFO "$@" || true ; }
warn() { _log WRN "$@"; }
error() { _log ERR "$@" && exit 1; }

# Add the configuration key $1 with value $2 to the autossh config file
add_config() {
  if ! [ -f "$AUTOSSH_CONFIG" ]; then
    info "Creating autossh config file at %s" "$AUTOSSH_CONFIG"
    touch "$AUTOSSH_CONFIG"
    chmod 600 "$AUTOSSH_CONFIG"
  fi

  trace "Adding config: %s %s" "$1" "$2"
  printf "%s %s\n" "$1" "$2" >> "$AUTOSSH_CONFIG"
}


# Basic checks
[ ! -d "$AUTOSSH_SDIR" ] && error "SSHd settings directory %s does not exist" "$AUTOSSH_SDIR"
[ ! -f "$AUTOSSH_SSHD_CONFIG" ] && error "SSHd config file %s does not exist" "$AUTOSSH_SSHD_CONFIG"
[ ! -x "$AUTOSSH_SSHD_BIN" ] && error "SSHD binary %s is not executable" "$AUTOSSH_SSHD_BIN"

# Point AUTOSSH_CONFIG to a file that is included from the main sshd_config and
# using the proper extension.
cf_glob=$(grep '^Include' "$AUTOSSH_SSHD_CONFIG" |head -n 1|awk '{print $2}')
[ -z "$cf_glob" ] && error "Could not find Include directive in %s" "$AUTOSSH_SSHD_CONFIG"
CF_DIR=$(dirname "$cf_glob") # Directory of the included config files
[ ! -d "$CF_DIR" ] && error "Included config directory %s does not exist" "$CF_DIR"
CF_EXT=$(basename "$cf_glob"|sed 's;.*\.;;') # Extension of the included config files, no leading dot
[ -z "$CF_EXT" ] && error "Could not determine included config file extension from %s" "$cf_glob"
trace "Using included config directory %s and extension %s" "$CF_DIR" "$CF_EXT"
AUTOSSH_CONFIG="${CF_DIR%%/}/autossh.${CF_EXT}"

# Arrange for the SSHd loglevel to follow our verbosity setting
case "$AUTOSSH_VERBOSE" in
  0) info "Setting SSHd LogLevel to INFO"; add_config "LogLevel" "INFO" ;;
  1) info "Setting SSHd LogLevel to VERBOSE"; add_config "LogLevel" "VERBOSE" ;;
  2) info "Setting SSHd LogLevel to DEBUG"; add_config "LogLevel" "DEBUG" ;;
  *) info "Setting SSHd LogLevel to DEBUG3"; add_config "LogLevel" "DEBUG3" ;;
esac

# Use the value of AUTOSSH_PASSWORD to set the password for the autossh user.
# When set to "-", disable login for the user.
if [ "$AUTOSSH_PASSWORD" = "-" ]; then
  info "Disabling login for autossh user"
  sed -i "s;^autossh:x:.*;autossh:x:$(id -u autossh):$(id -g autossh):autossh:/home/autossh:/sbin/nologin;g" /etc/passwd
  add_config "PasswordAuthentication" "no"
else
  if [ -z "$AUTOSSH_PASSWORD" ]; then
    info "Generating random password for autossh user"
    AUTOSSH_PASSWORD=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c13)
    _log PWD "==========="
    _log PWD "== autossh password is $AUTOSSH_PASSWORD"
    _log PWD "==========="
    _log PWD ""
  fi
  printf 'autossh:%s\n' "$AUTOSSH_PASSWORD" | chpasswd
fi


# Directory for HOSTKEYS, create if necessary
if [ ! -d "$AUTOSSH_KEYS" ]; then
  info "Creating host keys directory at %s" "$AUTOSSH_KEYS"
  mkdir -p "$AUTOSSH_KEYS"
  chmod 700 "$AUTOSSH_KEYS"
fi

# Generate server keys, if necessary. ssh-keygen generates the keys in the
# default directory, not where we want the keys, so we move the keys once they
# have been generated.
if [ ! -f "${AUTOSSH_KEYS%%/}/ssh_host_rsa_key" ]; then
  # One shot generation, -A really is for init.d style startup script, but
  # this is what we sort of are.
  ssh-keygen -A

  # Move the keys to the location that we want
  if [ -f "${AUTOSSH_SDIR%%/}/ssh_host_rsa_key" ]; then
    mv "${AUTOSSH_SDIR%%/}/ssh_host_rsa_key" "${AUTOSSH_KEYS%%/}/ssh_host_rsa_key"
    mv "${AUTOSSH_SDIR%%/}/ssh_host_rsa_key.pub" "${AUTOSSH_KEYS%%/}/ssh_host_rsa_key.pub"
  fi
  if [ -f "${AUTOSSH_SDIR%%/}/ssh_host_dsa_key" ]; then
    mv "${AUTOSSH_SDIR%%/}/ssh_host_dsa_key" "${AUTOSSH_KEYS%%/}/ssh_host_dsa_key"
    mv "${AUTOSSH_SDIR%%/}/ssh_host_dsa_key.pub" "${AUTOSSH_KEYS%%/}/ssh_host_dsa_key.pub"
  fi
  if [ -f "${AUTOSSH_SDIR%%/}/ssh_host_ecdsa_key" ]; then
    mv "${AUTOSSH_SDIR%%/}/ssh_host_ecdsa_key" "${AUTOSSH_KEYS%%/}/ssh_host_ecdsa_key"
    mv "${AUTOSSH_SDIR%%/}/ssh_host_ecdsa_key.pub" "${AUTOSSH_KEYS%%/}/ssh_host_ecdsa_key.pub"
  fi
  if [ -f "${AUTOSSH_SDIR%%/}/ssh_host_ed25519_key" ]; then
    mv "${AUTOSSH_SDIR%%/}/ssh_host_ed25519_key" "${AUTOSSH_KEYS%%/}/ssh_host_ed25519_key"
    mv "${AUTOSSH_SDIR%%/}/ssh_host_ed25519_key.pub" "${AUTOSSH_KEYS%%/}/ssh_host_ed25519_key.pub"
  fi
fi

# Arrange for the config to point at the proper server keys, i.e. at the proper
# location
info "Configuring sshd to use host keys from $AUTOSSH_KEYS"
[ -f "${AUTOSSH_KEYS%%/}/ssh_host_rsa_key" ] && add_config "HostKey" "${AUTOSSH_KEYS%%/}/ssh_host_rsa_key"
[ -f "${AUTOSSH_KEYS%%/}/ssh_host_dsa_key" ] && add_config "HostKey" "${AUTOSSH_KEYS%%/}/ssh_host_dsa_key"
[ -f "${AUTOSSH_KEYS%%/}/ssh_host_ecdsa_key" ] && add_config "HostKey" "${AUTOSSH_KEYS%%/}/ssh_host_ecdsa_key"
[ -f "${AUTOSSH_KEYS%%/}/ssh_host_ed25519_key" ] && add_config "HostKey" "${AUTOSSH_KEYS%%/}/ssh_host_ed25519_key"

# Allow external hosts to connect
if [ -z "$AUTOSSH_LOCAL" ] || [ "$AUTOSSH_LOCAL" = 0 ]; then
  info "Enabling GatewayPorts and AllowTcpForwarding"
  add_config "GatewayPorts" "yes"
  add_config "AllowTcpForwarding" "yes"
fi

# UsePAM so that our autossh user can login
add_config "UsePAM" "yes"

# Absolute path necessary! Pass all remaining arguments to sshd. This enables to
# override some options through -o, for example.
exec "$AUTOSSH_SSHD_BIN" -f "$AUTOSSH_SSHD_CONFIG" -D -e "$@"
