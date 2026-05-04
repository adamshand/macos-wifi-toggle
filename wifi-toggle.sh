#!/bin/bash

# Automatically toggle macOS Wi-Fi based on ethernet status (uses launchd).
# If ethernet is active, Wi-Fi is disabled. If ethernet is inactive, Wi-Fi is enabled.

PATH="/bin:/sbin:/usr/bin:/usr/sbin"
LAUNCHD_SERVICE_NAME="nz.haume.wifi-toggle"
LAUNCHD_SERVICE_FILE="${HOME}/Library/LaunchAgents/${LAUNCHD_SERVICE_NAME}.plist"
DEBUG=""  # Set to "yes" to enable debug output

# Each regex matches one or more interfaces from `networksetup -listnetworkserviceorder`
# Wi-Fi is disabled if ANY matching ethernet interface is active.
# NOTE: Customize this regex to match your ethernet adapter(s). Common values:
#   "Thunderbolt Ethernet"       - Thunderbolt-to-Ethernet adapters
#   "Apple USB Ethernet Adapter" - Apple USB ethernet
#   "Ethernet"                   - matches any interface containing "Ethernet"
ETHERNET_REGEX="Thunderbolt Ethernet|LAN"
WIFI_REGEX="(Wi-Fi|Airport)"

print_usage() {
  echo -e "Automatically toggle macOS Wi-Fi based on ethernet status (uses launchd)\n"
  echo "Usage: $(basename "$0") [ on | off | help ]"
  echo "   on - start automatically toggling Wi-Fi (install launchd service)"
  echo "  off - stop automatically toggling Wi-Fi (uninstall launchd service)"
  echo "  run - Toggle Wi-Fi status (run by launchd)"
  exit 1
}

print_error() {
  echo -e "ERROR: $1" >&2
  exit 1
}

print_debug() {
  test -n "$DEBUG" && echo -e "DEBUG: $1" >&2
}

notify() {
  # Configure notifications in: System Settings > Notifications > Script Editor
  osascript -e "display notification \"by $(basename "$0")\" with title \"$1\""
}

is_launchd_enabled() {
  if launchctl print gui/$(id -u)/nz.haume.wifi-toggle > /dev/null 2>&1; then
    print_debug "is_launchd_loaded(): $LAUNCHD_SERVICE_NAME already loaded"
    return 0
  else
    print_debug "is_launchd_loaded(): $LAUNCHD_SERVICE_NAME not loaded"
    return 1
  fi
}

enable_launchd() {
  local SCRIPT_PATH
  SCRIPT_PATH=$(realpath "$0") || print_error "Could not resolve script path"

  echo "Creating launchd service: $LAUNCHD_SERVICE_FILE"
  cat <<EOF > "$LAUNCHD_SERVICE_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LAUNCHD_SERVICE_NAME}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>ProgramArguments</key>
  <array>
  <string>${SCRIPT_PATH}</string>
  <string>run</string>
  </array>
  <key>WatchPaths</key>
  <array>
    <string>/Library/Preferences/SystemConfiguration</string>
  </array>
</dict>
</plist>
EOF
  echo "Enabling launchd service: $LAUNCHD_SERVICE_NAME"
  launchctl bootstrap gui/$(id -u) "$LAUNCHD_SERVICE_FILE"
}

disable_launchd() {
  echo "Disabling launchd service: $LAUNCHD_SERVICE_NAME"
  launchctl bootout gui/$(id -u) "$LAUNCHD_SERVICE_FILE"
  rm "$LAUNCHD_SERVICE_FILE"
}

# Returns a newline-separated list of interface names matching the given regex,
# or empty string if none found (does not exit on no match).
get_interface() {
  test -z "$1" && print_error "get_interface(): no regex provided"
  local INTERFACE
  INTERFACE=$(networksetup -listnetworkserviceorder | grep -E -A 1 "^\([0-9]+\).* $1" | grep -E -o "en[0-9]+")
  print_debug "get_interface(): regex '$1' -> interface(s) '$(echo "$INTERFACE" | tr '\n' ' ')'"
  echo "$INTERFACE"
}

# Parameters: $1=interface name, $2=is_wifi ("true" for Wi-Fi, omit for ethernet)
# Outputs: "active" or "inactive" to stdout
is_interface_active() {
  test -z "$1" && print_error "is_interface_active(): no interface provided"
  local IS_WIFI="${2:-false}"

  if ! ifconfig "$1" > /dev/null 2>&1; then
    echo "inactive"
    return
  fi

  local STATUS
  STATUS=$(ifconfig "$1" 2>&1 | grep "status:" | awk '{print $2}')

  if [ "$STATUS" = "active" ]; then
    if [ "$IS_WIFI" = "true" ]; then
      echo "active"
    else
      # For ethernet: also require an IP address to confirm a real connection
      if ifconfig "$1" | grep -q "inet "; then
        echo "active"
      else
        echo "inactive"
      fi
    fi
  else
    echo "inactive"
  fi
}

toggle_wifi() {
  local ETHERNET_INTERFACES WIFI_INTERFACE
  ETHERNET_INTERFACES=$(get_interface "$ETHERNET_REGEX")
  WIFI_INTERFACE=$(get_interface "$WIFI_REGEX" | head -n1)

  if [ -z "$WIFI_INTERFACE" ]; then
    print_error "No Wi-Fi interface found matching: $WIFI_REGEX"
  fi

  # Check if any ethernet interface is active; treat no interfaces found as inactive
  local ETHERNET_STATUS="inactive"
  if [ -n "$ETHERNET_INTERFACES" ]; then
    for ETH_IF in $ETHERNET_INTERFACES; do
      local STATUS
      STATUS=$(is_interface_active "$ETH_IF" false)
      print_debug "ethernet interface '$ETH_IF' status: '$STATUS'"
      if [ "$STATUS" = "active" ]; then
        ETHERNET_STATUS="active"
        break
      fi
    done
  else
    print_debug "no ethernet interfaces found matching: $ETHERNET_REGEX"
  fi

  local WIFI_STATUS
  WIFI_STATUS=$(is_interface_active "$WIFI_INTERFACE" true)
  print_debug "ethernet status: '$ETHERNET_STATUS', wifi status: '$WIFI_STATUS'"

  if [ "$ETHERNET_STATUS" = "active" ] && [ "$WIFI_STATUS" = "active" ]; then
    print_debug "disabling wifi"
    networksetup -setairportpower "$WIFI_INTERFACE" off
    notify "Wi-Fi Disabled"
  elif [ "$ETHERNET_STATUS" = "inactive" ] && [ "$WIFI_STATUS" = "inactive" ]; then
    print_debug "enabling wifi"
    networksetup -setairportpower "$WIFI_INTERFACE" on
    notify "Wi-Fi Enabled"
  else
    print_debug "not toggling wifi status"
  fi
}

### main script
if [ "${OSTYPE:0:6}" != "darwin" ]; then
  print_error "This script only runs on macOS"
fi

if [ "$1" = "run" ]; then
  toggle_wifi

elif [ "$1" = "on" ]; then
  if is_launchd_enabled; then
    print_error "launchd service already enabled"
  else
    mkdir -p "${HOME}/Library/LaunchAgents"
    enable_launchd
  fi

elif [ "$1" = "off" ]; then
  if is_launchd_enabled; then
    disable_launchd
  else
    print_error "launchd service already disabled"
  fi

else
  print_usage

fi
