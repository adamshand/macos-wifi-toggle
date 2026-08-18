#!/bin/bash

# Written by Adam Shand <adam@shand.net>
# https://github.com/adamshand/macos-wifi-toggle

# Automatically toggle macOS Wi-Fi based on wired network status (uses launchd).
# If any wired interface is active, Wi-Fi is disabled. When all wired interfaces
# become inactive, Wi-Fi is restored (if this script previously disabled it).

PATH="/bin:/sbin:/usr/bin:/usr/sbin"
LAUNCHD_SERVICE_NAME="nz.haume.wifi-toggle"
LAUNCHD_SERVICE_VERSION="2"
LAUNCHD_SERVICE_FILE="${HOME}/Library/LaunchAgents/${LAUNCHD_SERVICE_NAME}.plist"
STATE_DIRECTORY="${HOME}/Library/Application Support/${LAUNCHD_SERVICE_NAME}"
WIFI_DISABLED_FILE="${STATE_DIRECTORY}/wifi-disabled"
LEGACY_MIGRATION_FILE="${STATE_DIRECTORY}/legacy-migration-complete"
DEBUG="yes"

# Keep the launchd file and state file private to the current user.
umask 077

print_usage() {
  echo "Automatically toggle macOS Wi-Fi based on wired network status (uses launchd)"
  echo
  echo "Usage: $(basename "$0") [ on | off | run | status | help ]"
  echo "      on - start automatically toggling Wi-Fi (install launchd service)"
  echo "     off - stop automatically toggling Wi-Fi (uninstall launchd service)"
  echo "     run - toggle Wi-Fi now (also run automatically by launchd)"
  echo "  status - show detected interfaces and launchd status"
  echo "    help - show this help"
}

print_error() {
  echo "ERROR: $1" >&2
  exit 1
}

print_debug() {
  if [ -n "$DEBUG" ]; then
    echo "DEBUG: $1" >&2
  fi
}

notify() {
  # Configure notifications in: System Settings > Notifications > Script Editor
  if ! osascript - "$1" "$(basename "$0")" <<'APPLESCRIPT'; then
on run arguments
  display notification ("by " & item 2 of arguments) with title (item 1 of arguments)
end run
APPLESCRIPT
    print_debug "unable to display notification"
  fi
}

is_launchd_enabled() {
  if launchctl print "gui/$(id -u)/${LAUNCHD_SERVICE_NAME}" >/dev/null 2>&1; then
    print_debug "is_launchd_enabled(): $LAUNCHD_SERVICE_NAME is enabled"
    return 0
  else
    print_debug "is_launchd_enabled(): $LAUNCHD_SERVICE_NAME is disabled"
    return 1
  fi
}

xml_escape() {
  printf "%s" "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g'
}

get_script_file() {
  SCRIPT_DIRECTORY=$(cd "$(dirname "$0")" && pwd -P) || print_error "Unable to find the script directory"
  SCRIPT_FILE="${SCRIPT_DIRECTORY}/$(basename "$0")"
}

create_launchd_service() {
  get_script_file
  ESCAPED_SCRIPT_FILE=$(xml_escape "$SCRIPT_FILE")
  TEMP_SERVICE_FILE=$(mktemp "${LAUNCHD_SERVICE_FILE}.XXXXXX") || print_error "Unable to create launchd service file"

  echo "Creating launchd service: $LAUNCHD_SERVICE_FILE"
  if ! cat <<EOF >"$TEMP_SERVICE_FILE"; then
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LAUNCHD_SERVICE_NAME}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>WIFI_TOGGLE_SERVICE_VERSION</key>
    <string>${LAUNCHD_SERVICE_VERSION}</string>
  </dict>
  <key>ProgramArguments</key>
  <array>
    <string>${ESCAPED_SCRIPT_FILE}</string>
    <string>run</string>
  </array>
  <key>WatchPaths</key>
  <array>
    <string>/Library/Preferences/SystemConfiguration</string>
  </array>
</dict>
</plist>
EOF
    rm -f "$TEMP_SERVICE_FILE"
    print_error "Unable to write launchd service file"
  fi

  if ! PLIST_ERROR=$(plutil -lint "$TEMP_SERVICE_FILE" 2>&1); then
    rm -f "$TEMP_SERVICE_FILE"
    print_error "Invalid launchd service file: $PLIST_ERROR"
  fi

  mv "$TEMP_SERVICE_FILE" "$LAUNCHD_SERVICE_FILE" || print_error "Unable to install launchd service file"
}

enable_launchd() {
  migrate_legacy_wifi_state

  LAUNCHD_WAS_ENABLED="no"
  if is_launchd_enabled; then
    LAUNCHD_WAS_ENABLED="yes"
    echo "Updating launchd service: $LAUNCHD_SERVICE_NAME"
  fi

  create_launchd_service

  if [ "$LAUNCHD_WAS_ENABLED" == "yes" ]; then
    launchctl bootout "gui/$(id -u)/${LAUNCHD_SERVICE_NAME}" || print_error "Unable to unload launchd service"
  fi

  echo "Enabling launchd service: $LAUNCHD_SERVICE_NAME"
  launchctl bootstrap "gui/$(id -u)" "$LAUNCHD_SERVICE_FILE" || print_error "Unable to enable launchd service"

  rm -f "$LEGACY_MIGRATION_FILE"
  rmdir "$STATE_DIRECTORY" >/dev/null 2>&1 || true
}

disable_launchd() {
  if is_launchd_enabled; then
    echo "Disabling launchd service: $LAUNCHD_SERVICE_NAME"
    launchctl bootout "gui/$(id -u)/${LAUNCHD_SERVICE_NAME}" || print_error "Unable to disable launchd service"
  else
    echo "launchd service already disabled: $LAUNCHD_SERVICE_NAME"
  fi

  if [ -e "$LAUNCHD_SERVICE_FILE" ]; then
    rm "$LAUNCHD_SERVICE_FILE" || print_error "Unable to remove launchd service file"
  fi
}

discover_interfaces() {
  HARDWARE_PORTS=$(networksetup -listallhardwareports 2>&1) || print_error "Unable to list network hardware: $HARDWARE_PORTS"
  ALL_INTERFACES=$(printf "%s\n" "$HARDWARE_PORTS" | awk -F ': ' '/^Device: en[0-9]+$/ { print $2 }')
  WIFI_INTERFACES=""
  WIRED_INTERFACES=""

  for INTERFACE in $ALL_INTERFACES; do
    if networksetup -getairportpower "$INTERFACE" >/dev/null 2>&1; then
      WIFI_INTERFACES="$WIFI_INTERFACES $INTERFACE"
    else
      WIRED_INTERFACES="$WIRED_INTERFACES $INTERFACE"
    fi
  done

  test -z "$WIFI_INTERFACES" && print_error "No Wi-Fi interface found"

  print_debug "Wi-Fi interfaces:${WIFI_INTERFACES}"
  if [ -n "$WIRED_INTERFACES" ]; then
    print_debug "wired interfaces:${WIRED_INTERFACES}"
  else
    print_debug "wired interfaces: none detected"
  fi
}

is_interface_active() {
  test -z "$1" && print_error "is_interface_active(): no interface provided"

  if ifconfig "$1" 2>/dev/null | grep -q "status: active"; then
    return 0
  else
    return 1
  fi
}

get_wifi_power() {
  test -z "$1" && print_error "get_wifi_power(): no interface provided"

  WIFI_POWER_OUTPUT=$(networksetup -getairportpower "$1" 2>&1) || print_error "Unable to get Wi-Fi power for $1: $WIFI_POWER_OUTPUT"

  if printf "%s\n" "$WIFI_POWER_OUTPUT" | grep -q ": On$"; then
    WIFI_POWER="on"
  elif printf "%s\n" "$WIFI_POWER_OUTPUT" | grep -q ": Off$"; then
    WIFI_POWER="off"
  else
    print_error "Unknown Wi-Fi power for $1: $WIFI_POWER_OUTPUT"
  fi
}

remember_wifi_disabled() {
  mkdir -p "$STATE_DIRECTORY" || print_error "Unable to create state directory: $STATE_DIRECTORY"
  touch "$WIFI_DISABLED_FILE" || print_error "Unable to save Wi-Fi state"
}

is_legacy_launchd_service() {
  if [ -e "$LAUNCHD_SERVICE_FILE" ]; then
    INSTALLED_SERVICE_VERSION=$(plutil -extract EnvironmentVariables.WIFI_TOGGLE_SERVICE_VERSION raw "$LAUNCHD_SERVICE_FILE" 2>/dev/null) || return 0
    test "$INSTALLED_SERVICE_VERSION" != "$LAUNCHD_SERVICE_VERSION" && return 0
    return 1
  fi

  # A loaded service without its plist is also from an older installation.
  is_launchd_enabled
}

migrate_legacy_wifi_state() {
  test -e "$LEGACY_MIGRATION_FILE" && return 0
  is_legacy_launchd_service || return 0

  LEGACY_WIFI_WAS_OFF="no"
  for WIFI_INTERFACE in $WIFI_INTERFACES; do
    get_wifi_power "$WIFI_INTERFACE"
    if [ "$WIFI_POWER" == "off" ]; then
      LEGACY_WIFI_WAS_OFF="yes"
    fi
  done

  if [ "$LEGACY_WIFI_WAS_OFF" == "yes" ]; then
    print_debug "legacy launchd service found with Wi-Fi off; saving Wi-Fi state"
    remember_wifi_disabled
  else
    mkdir -p "$STATE_DIRECTORY" || print_error "Unable to create state directory: $STATE_DIRECTORY"
  fi

  touch "$LEGACY_MIGRATION_FILE" || print_error "Unable to save legacy migration state"
}

prepare_wifi_toggle() {
  discover_interfaces

  # Current launchd services provide their version in the environment. An old
  # service enters this migration once, then leaves a marker until it is updated.
  if [ "${WIFI_TOGGLE_SERVICE_VERSION:-}" != "$LAUNCHD_SERVICE_VERSION" ] && [ ! -e "$LEGACY_MIGRATION_FILE" ]; then
    migrate_legacy_wifi_state
  fi
}

restore_wifi() {
  test ! -e "$WIFI_DISABLED_FILE" && return 0

  WIFI_CHANGED="no"
  for WIFI_INTERFACE in $WIFI_INTERFACES; do
    get_wifi_power "$WIFI_INTERFACE"
    if [ "$WIFI_POWER" == "off" ]; then
      print_debug "enabling Wi-Fi on $WIFI_INTERFACE"
      networksetup -setairportpower "$WIFI_INTERFACE" on || print_error "Unable to enable Wi-Fi on $WIFI_INTERFACE"
      WIFI_CHANGED="yes"
    fi
  done

  rm "$WIFI_DISABLED_FILE" || print_error "Unable to clear saved Wi-Fi state"
  rmdir "$STATE_DIRECTORY" >/dev/null 2>&1 || true

  if [ "$WIFI_CHANGED" == "yes" ]; then
    notify "Wi-Fi Enabled"
  fi
}

toggle_wifi() {
  WIRED_ACTIVE="no"
  for WIRED_INTERFACE in $WIRED_INTERFACES; do
    if is_interface_active "$WIRED_INTERFACE"; then
      print_debug "wired interface $WIRED_INTERFACE is active"
      WIRED_ACTIVE="yes"
    else
      print_debug "wired interface $WIRED_INTERFACE is inactive"
    fi
  done

  if [ "$WIRED_ACTIVE" == "yes" ]; then
    WIFI_CHANGED="no"
    for WIFI_INTERFACE in $WIFI_INTERFACES; do
      get_wifi_power "$WIFI_INTERFACE"
      print_debug "Wi-Fi interface $WIFI_INTERFACE is $WIFI_POWER"

      if [ "$WIFI_POWER" == "on" ]; then
        remember_wifi_disabled
        print_debug "disabling Wi-Fi on $WIFI_INTERFACE"
        networksetup -setairportpower "$WIFI_INTERFACE" off || print_error "Unable to disable Wi-Fi on $WIFI_INTERFACE"
        WIFI_CHANGED="yes"
      fi
    done

    if [ "$WIFI_CHANGED" == "yes" ]; then
      notify "Wi-Fi Disabled"
    fi
  elif [ -e "$WIFI_DISABLED_FILE" ]; then
    print_debug "all wired interfaces are inactive; restoring Wi-Fi"
    restore_wifi
  else
    print_debug "all wired interfaces are inactive; Wi-Fi was not disabled by this script"
  fi
}

print_status() {
  discover_interfaces

  if is_launchd_enabled; then
    echo "Automatic toggle: enabled"
  else
    echo "Automatic toggle: disabled"
  fi

  if [ -e "$LAUNCHD_SERVICE_FILE" ]; then
    INSTALLED_SCRIPT=$(plutil -extract ProgramArguments.0 raw "$LAUNCHD_SERVICE_FILE" 2>/dev/null) || INSTALLED_SCRIPT="unknown"
    INSTALLED_SERVICE_VERSION=$(plutil -extract EnvironmentVariables.WIFI_TOGGLE_SERVICE_VERSION raw "$LAUNCHD_SERVICE_FILE" 2>/dev/null) || INSTALLED_SERVICE_VERSION="legacy"
    echo "Installed script: $INSTALLED_SCRIPT"
    echo "Installed service version: $INSTALLED_SERVICE_VERSION"

    get_script_file
    if [ "$INSTALLED_SCRIPT" != "unknown" ] && [ "$INSTALLED_SCRIPT" != "$SCRIPT_FILE" ]; then
      echo "Warning: this is not the script used by the installed launchd service"
    fi
  fi

  echo "Wi-Fi interfaces:"
  for WIFI_INTERFACE in $WIFI_INTERFACES; do
    get_wifi_power "$WIFI_INTERFACE"
    echo "  $WIFI_INTERFACE: $WIFI_POWER"
  done

  echo "Wired interfaces:"
  if [ -n "$WIRED_INTERFACES" ]; then
    for WIRED_INTERFACE in $WIRED_INTERFACES; do
      if is_interface_active "$WIRED_INTERFACE"; then
        echo "  $WIRED_INTERFACE: active"
      else
        echo "  $WIRED_INTERFACE: inactive"
      fi
    done
  else
    echo "  none detected"
  fi

  if [ -e "$WIFI_DISABLED_FILE" ]; then
    echo "Wi-Fi restore pending: yes"
  else
    echo "Wi-Fi restore pending: no"
  fi
}

### main script
COMMAND="${1:-}"

if [ "$COMMAND" == "help" ] || [ "$COMMAND" == "-h" ] || [ "$COMMAND" == "--help" ]; then
  print_usage
  exit 0
elif [ -z "$COMMAND" ]; then
  print_usage
  exit 1
fi

if [ "${OSTYPE:0:6}" != "darwin" ]; then
  print_error "This script only runs on macOS"
elif [ "$(id -u)" == "0" ]; then
  print_error "Run this script with your normal user account, not as root"
fi

if [ "$COMMAND" == "run" ]; then
  prepare_wifi_toggle
  toggle_wifi

elif [ "$COMMAND" == "on" ]; then
  discover_interfaces

  LAUNCHD_DIRECTORY="${HOME}/Library/LaunchAgents"
  if [ -d "$LAUNCHD_DIRECTORY" ]; then
    print_debug "$LAUNCHD_DIRECTORY exists"
  else
    mkdir -p "$LAUNCHD_DIRECTORY" || print_error "Unable to create $LAUNCHD_DIRECTORY"
    echo "Created directory: $LAUNCHD_DIRECTORY"
  fi

  enable_launchd

elif [ "$COMMAND" == "off" ]; then
  disable_launchd

  if [ -e "$WIFI_DISABLED_FILE" ]; then
    discover_interfaces
    echo "Restoring Wi-Fi disabled by this script"
    restore_wifi
  fi

  rm -f "$LEGACY_MIGRATION_FILE"
  rmdir "$STATE_DIRECTORY" >/dev/null 2>&1 || true

elif [ "$COMMAND" == "status" ]; then
  print_status

else
  print_error "Unknown command: $COMMAND"
fi
