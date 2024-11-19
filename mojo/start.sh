#!/usr/bin/with-contenv bash
# must use with-contenv for scripts run within s6, it restores our env vars

export MOJO_JSON_FILE=/var/lib/tailscale/mojo/wakeonlan.json

R='\033[1;31m'
G='\033[1;32m'
X='\033[0m'

log() {
  echo "[WakeOnLAN] $@"
}

logG() {
  echo -e "${G}[WakeOnLAN] $@${X}"
}

logR() {
  echo -e "${R}[WakeOnLAN] $@${X}"
}

# Make sure tailscale started up and is logged in
tailscale ip 1>/dev/null 2>/tmp/tailscale.err
if [[ $? -ne 0 ]]; then
  cat /tmp/tailscale.err && rm /tmp/tailscale.err
  logR "Error: Tailscale is not logged in, please check your authkey."
  exit 1
fi

log "Trying to detect network configuration..."

# Use WOL_NETWORK if available
if [[ -n "$WOL_NETWORK" ]]; then
  # Validate CIDR and extract network address
  BROADCAST=$(/usr/bin/ipcalc --json -b "$WOL_NETWORK" 2>/tmp/ipcalc.err | jq -r '.BROADCAST' )
  if [[ -n "$BROADCAST" ]]; then
    log "Using WOL_NETWORK subnet ${WOL_NETWORK} to determine broadcast address."
  else
    cat /tmp/ipcalc.err && rm /tmp/ipcalc.err
    log "Error: WOL_NETWORK value of ${WOL_NETWORK} may be incorrect, I could not determine broadcast address." >&2
  fi
fi

# Try a simple detection
if [[ -z "$BROADCAST" ]]; then
  log "WOL_NETWORK not provided, attempting to auto-detect your LAN network..."
  IFACE=$(/sbin/ip --json route show default 0.0.0.0/0 | jq -r .[0].dev)
  if [[ -n "$IFACE" ]]; then
    BROADCAST=$(/sbin/ip --json addr show $IFACE | jq -r '.[0].addr_info[0].broadcast')
    if [[ -n "$BROADCAST" ]]; then
      if ip addr show docker0 &>/dev/null; then
        # Probably running in network=host mode, so we can see the LAN subnet directly
        log "LAN seems to be on $IFACE, with a broadcast IP address of $BROADCAST."
      else
        # in bridge network mode, need to use a traceroute to find the LAN
        unset BROADCAST
        log "We seem to be in Docker bridge mode, looking for next hop..."
        trace=$(traceroute -nm 2 1.1.1.1 2>/tmp/traceroute.err)
        if [[ -n "$trace" ]]; then
          # Extract the second hop IP address
          ip=$(echo "$trace" | grep -Eo '2\s+([0-9]{1,3}\.){3}[0-9]{1,3}' | awk '{print $2}')
          if [[ -n "$ip" ]]; then
            # Extract the first octet of the IP address
            first_octet=$(echo "$ip" | cut -d. -f1)
            # Set the broadcast address based on the private IP ranges
            if [[ $first_octet -eq 192 ]]; then
              BROADCAST=$(echo "$ip" | awk -F. '{print $1"."$2"."$3".255"}')
            elif [[ $first_octet -eq 172 ]]; then
              BROADCAST=$(echo "$ip" | awk -F. '{print $1"."$2".255.255"}')
            elif [[ $first_octet -eq 10 ]]; then
              BROADCAST=$(echo "$ip" | awk -F. '{print $1".255.255.255"}')
            fi
            if [[ -n "$BROADCAST" ]]; then
              log "The next hop, ${ip}, is a private IP, so we will assume the broadcast address is $BROADCAST."
            else
              log "Error: The next hop, ${ip}, is not a private IP address. Please use WOL_NETWORK to set the broadcast address." >&2
            fi
          else
            cat /tmp/traceroute.err && rm /tmp/traceroute.err
            log "Error: couldn't run 'traceroute -nm 2 1.1.1.1'. You will need to set WOL_NETWORK." >&2
          fi
        fi
      fi
    fi
  else
    log "Error: unable to get default network interface name. I tried: ip route show default 0.0.0.0/0" >&2
  fi
fi

if [[ -n "$BROADCAST" ]]; then
  # get the DNS suffix
  suffix=$(tailscale dns status | grep -oP 'suffix = \K[^)]+')
  if [[ -n "$suffix" ]]; then
    suffix=".${suffix}"
  fi
  logG "LAN broadcast address set to $BROADCAST. Access the web UI at https://${TAILSCALE_HOSTNAME}${suffix}"
  if [ ! -f /var/lib/tailscale/certs/acme-account.key.pem ]; then
    logG "Be patient! It will take several seconds for Tailscale to obtain an SSL certificate the first time you access the site."
  fi
else
  logR "Error: No broadcast address configured, wake-on-LAN won't work properly. You will need to set WOL_NETWORK." >&2
  # probably won't work, but at least allows us to still use the wake command
  BROADCAST="255.255.255.255"
fi

# XXX I don't think there is any way without help from outside of the container to verify that bc_forwarding is enabled or
# that our broadcast packets can make it out. If there is something, it would go here.

# create if needed, then update the JSON
if [ ! -f $MOJO_JSON_FILE ]; then
  mkdir -p /var/lib/tailscale/mojo
  echo '{"broadcast":null,"hosts":[]}' > $MOJO_JSON_FILE
fi
jq --arg broadcast "$BROADCAST" '.broadcast = $broadcast' $MOJO_JSON_FILE > /tmp/updated.json && \
    mv /tmp/updated.json $MOJO_JSON_FILE

# Run on port 3000 and accept reverse proxy headers from localhost (tailscale serve)
/mojo/main.pl prefork \
    --listen  http://127.0.0.1:3000 \
    --mode    development \
    --proxy   127.0.0.1 \
    --workers 1
