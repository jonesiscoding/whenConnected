#!/bin/bash

## region ###################################### Static Variables

isDebug=false
isWorkNetwork=false
isWorkVpn=false
isAdd=false
isSet=false
bundleId="com.deviscoding.whenConnected"
prefFile="$bundleId.plist"
launchAgent="$HOME/Library/LaunchAgents/${bundleId}Agent.plist"

## endregion ################################### Static Variables

## region ###################################### Functions

function get-network-index() {
  local count last
  if [ -f "$1" ]; then
    count=$(get-count networks "$1")
    if [ "$count" -gt "0" ]; then
      for ((i = 0 ; i < "$count" ; i++ ))
      do
        # Find the name of the current EA we're processing
        if [ "$(/usr/bin/plutil -extract networks.$i.name raw "$1" | grep -v "Could not extract")" = "$network" ]; then
          echo "$i" && return 0
        fi
      done
    fi
  fi

  return 1
}

function get-network-config() {
  local index
  if [ -f "$1" ]; then
    if index=$(get-network-index "$1"); then
      /usr/bin/plutil -extract "networks.$index" xml1 "$1" -o - && return 0
    fi
  fi

  return 1
}

function dict_value() {
  local type count
  if [ -n "$1" ]; then
    type=$(/usr/bin/plutil -type "$2" - <<< "$1")
    if [ "$type" == "array" ]; then
      count=$(/usr/bin/plutil -extract "$2" raw - <<< "$1" | grep -v "Could not extract")
      for ((i = 0 ; i < "$count" ; i++ ))
      do
        # Find the name of the current EA we're processing
        /usr/bin/plutil -extract "$2.$i" raw - <<< "$1" | grep -v "Could not extract"
      done
    else
      /usr/bin/plutil -extract "$2" raw - <<< "$1" | grep -v "Could not extract"
    fi
  fi
}

function get-managed-preference() {
  dict_value "$(get-network-config "/Library/Managed Preferences/$prefFile")" "$1"
}

function get-system-preference() {
  dict_value "$(get-network-config "/Library/Preferences/$prefFile")" "$1"
}

function get-user-preference() {
  dict_value "$(get-network-config "$HOME/Library/Preferences/$prefFile")" "$1"
}

function get-preference() {
  local mPrefs uPrefs sPrefs outPref tryPref config

  outPref="$2"
  uPrefs="$HOME/Library/Preferences/$prefFile"
  sPrefs="/Library/Preferences/$prefFile"

  if [ -z "$outPref" ]; then
    # System Preference
    tryPref=$(get-system-preference "$1")
    [ -n "$tryPref" ] && outPref="$tryPref"

    # User Preference > System Preference
    tryPref=$(get-user-preference "$1")
    [ -n "$tryPref" ] && outPref="$tryPref"
  fi

  # Managed Preference > All Others
  tryPref=$(get-managed-preference "$1")
  [ -n "$tryPref" ] && outPref="$tryPref"

  # Return Error If Empty
  [ -z "$outPref" ] && return 1

  echo "$outPref" && return 0
}

get-count() {
  local count
  if [ -f "$2" ]; then
    count=$(plutil -extract "$1" raw "$2" | grep -v "Could not extract")
    if [ -z "$count" ]; then
      count=0
      plutil -insert "$1" -json "[]" "$2"
    fi

    echo $count
  fi
}

has-value() {
  plutil -extract "$1" xml1 "$3" -o - | grep -q "$2"
}

set-string-value() {
  [ -n "$2" ] && [ -f "$3" ] && plutil -replace "$1" -string "$2" "$3"
}

function get-ssid() {
  networksetup -getairportnetwork en0 | awk -F': ' '{print $NF}'
}

function get-vpn-ip() {
  local ip try interfaces
  ip=""
  interfaces=$(/sbin/ifconfig -u | /usr/bin/grep 'POINTOPOINT' | /usr/bin/cut -d: -f1)
  while IFS= read -r interface
  do
    try=$(/sbin/ifconfig "${interface}" | /usr/bin/grep "inet " | /usr/bin/cut -d ' ' -f2 2>/dev/null)
    [ -n "$try" ] && ip="$try"
  done <<< "$interfaces"

  [ -z "$ip" ] && return 1

  echo "$ip" && return 0
}

function run-item() {
  local item

  item=$(echo "$1" | /usr/bin/sed -e 's/^[[:space:]]*//')

  if echo "$item" | /usr/bin/grep -q -E "\.app$"; then
    /usr/bin/open -a "$item"
  elif echo "$item" | /usr/bin/grep -q -E "^/Applications"; then
    /usr/bin/open "$item"
  elif [ -x "$item" ]; then
    "$item"
  fi
}

function csv-to-list() {
  for i in ${1//,/ }
  do
    echo "$i"
  done
}

function install-launchagent() {
  local agentOwner agentGroup
  agentOwner=$(/usr/bin/stat -f "%Su" "$HOME")
  agentGroup=$(/usr/bin/stat -f "%Sg" "$HOME")

	cat <<EOF > "${launchAgent}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${bundleId}Agent</string>
  <key>Program</key>
  <string>/Applications/whenConnected.app/Contents/MacOS/whenConnected</string>
  <key>WatchPaths</key>
  <array>
    <string>/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist</string>
    <string>/Library/Preferences/SystemConfiguration/com.apple.wifi.message-tracer.plist</string>
    <string>/Library/Preferences/com.apple.wifi.known-networks.plist</string>
    <string>$HOME/Library/Application Support/OpenVPN Connect/config.json</string>
  </array>
  <key>AssociatedBundleIdentifiers</key>
  <string>${bundleId}</string>
</dict>
</plist>
EOF
  chmod 755 "$launchAgent"
  chown "$agentOwner" "$launchAgent"
  chgrp "$agentGroup" "$launchAgent"
  launchctl load "$launchAgent"
}

## region ###################################### Input Handling

[ ! -f "$launchAgent" ] && install-launchagent

while [ "$1" != "" ]; do
  case "$1" in
      --verbose )               isDebug=true;                         ;;
      --set )                   isSet=true;    ;;
      --add )                   isAdd=true;     ;;
      --vpn )                   workVPN="$2"; shift ;;
      --ip )                    workIP="$2"; shift ;;
      --ssid )                  workSSID="$2"; shift ;;
      --on-connect )            onConnect="$2"; shift ;;
      --on-vpn )                onVPN="$2"; shift ;;
  esac
  [ -z "$network" ] && [ -n "$1" ] && network="$1"
  shift # move to next kv pair
done

if [ -z "$network" ]; then
  hostname=$(hostname)
  len="${hostname//[^\.]}"
  len=${#len}
  if [ "${len}" -ge "3" ]; then
    network=$(echo "$hostname" | awk -F. '{s="";for (i=NF;i>1;i--) s=s sprintf("%s.",$i);$0=s $1}1' | cut -d'.' -f-$((len-1)) )
  else
    network="default"
  fi
fi
keySSID="ssid"
keyIP="ip"
keyVPN="vpn"
keyOnConnect="on_connect"
keyOnVPN="on_vpn"

## endregion ################################### Input Handling

## region ###################################### Setting Preferences

if $isAdd || $isSet; then
  prefs="$HOME/Library/Preferences/$prefFile"
  # This could be spoofed, but a standard user still won't be able to write to the global preferences
  [ "$USER" == "root" ] && prefs="/Library/Preferences/$prefFile"

  # Get Index
  [ ! -f "$prefs" ] && plutil -create xml1 "$prefs"

  index=$(get-network-index "$prefs")
  echo "Index: $index"
  if [ -z "$index" ]; then
    echo "Creating"
    index=$(get-count "networks" "$prefs")
    plutil -insert "networks.${index}" -json "{}" "$prefs"
    set-string-value "networks.${index}.name" "$network" "$prefs"
  fi

  # Add Filters
  set-string-value "networks.${index}.${keySSID}" "$workSSID" "$prefs"
  set-string-value "networks.${index}.${keyIP}" "$workIP" "$prefs"
  set-string-value "networks.${index}.${keyVPN}" "$workVPN" "$prefs"

  # Add on_connect Automation
  if [ -n "$onConnect" ]; then
    # Get count and create key if needed
    x=$(get-count "networks.${index}.${keyOnConnect}" "$prefs")
    echo "Count: $x"
    # Remove previous values if needed
    $isSet && [ "$x" -gt 0 ] && plutil -replace "networks.${index}.${keyOnConnect}" -json "[]" "$prefs" && x=0
    # Loop through and add values
    for i in "${onConnect//,/ }"
    do
      if ! has-value "networks.${index}.${keyOnConnect}" "${i}" "$prefs"; then
        set-string-value "networks.${index}.${keyOnConnect}.${x}" "${i}" "$prefs"
        x=$((x+1))
      fi
    done
  fi

  # Add on_vpn Automation
  if [ -n "$onVPN" ]; then
    # Get count and create key if needed
    x=$(get-count "networks.${index}.${keyOnVPN}" "$prefs")
    echo "Count: $x"
    # Remove previous values if needed
    $isSet && [ "$x" -gt 0 ] && plutil -replace "networks.${index}.${keyOnVPN}" -json "[]" "$prefs" && x=0
    # Loop through and add values
    for i in "${onVPN//,/ }"
    do
      if ! has-value "networks.${index}.${keyOnVPN}" "${i}" "$prefs"; then
        set-string-value "networks.${index}.${keyOnVPN}.${x}" "${i}" "$prefs"
        x=$((x+1))
      fi
    done
  fi

  exit 0
fi

## endregion ################################### Setting Preferences

## region ###################################### Variables from Preferences

workSSID=$(get-preference "$keySSID" "$workSSID")
workIP=$(get-preference "$keyIP" "$workIP")
workVPN=$(get-preference "$keyVPN" "$workVPN")

# Convert --on-connect CSV input to List, Unless Managed Preference Exists
if [ -n "$onConnect" ] && [ -z "$(get-managed-preference "$keyOnConnect")" ]; then
  onConnect=$(csv-to-list "$onConnect")
else
  onConnect=$(get-preference "$keyOnConnect")
fi

# Convert --on-vpn CSV input to List, Unless Managed Preference Exists
if [ -n "$onVPN" ] && [ -z "$(get-managed-preference "$keyOnVPN")" ]; then
  onVPN=$(csv-to-list "$onVPN")
else
  onVPN=$(get-preference "$keyOnVPN" | grep -v -E "^(Array {|})")
fi

if $isDebug; then
  echo "$network Config"
  echo "----------------------------"
  echo "SSID: $workSSID"
  echo "IP: $workIP"
  echo "VPN: $workVPN"
  echo "On Connect:"
  while IFS= read -r line || [[ -n $line ]]; do
    echo "  $line"
  done < <(printf '%s' "$onConnect")
  echo "On VPN:"
  while IFS= read -r line || [[ -n $line ]]; do
    echo "  $line"
  done < <(printf '%s' "$onVPN")
  echo "----------------------------"
fi

## endregion ################################### Variables from Preferences

## region ###################################### Run Code

# SSID Test
if [ -n "$workSSID" ]; then
  ssid=$(get-ssid)
  if [ -n "$ssid" ]; then
    $isDebug && echo "Matching SSID: $ssid"
    echo "$ssid" | grep -q -E "$workSSID" && isWorkNetwork=true
  fi
fi

# IP Test
if ! $isWorkNetwork && [ -n "$workIP" ]; then
  wip=""
  interfaces=$(/usr/sbin/networksetup -listallhardwareports | grep -A2 'Wi-Fi\|Airport\|Ethernet\|Thunderbolt' | grep -o en.)
  while IFS= read -r interface
  do
    ip=$(/sbin/ifconfig "${interface}" | grep "inet " | cut -d ' ' -f2 2>/dev/null)
    if [ -n "$ip" ]; then
      wip="$ip"
    fi
  done <<< "$interfaces"
  if echo "$wip" | grep -q -E "$workIP"; then
    echo "Matching IP: $wip"
    isWorkNetwork=true
  fi
fi

# VPN Test
if ! $isWorkNetwork && [ -n "$workVPN" ]; then
  vpnIP=$(get-vpn-ip)
  if [ -n "$vpnIP" ]; then
    $isDebug && echo "Matching VPN IP: $vpnIP"
    if echo "$vpnIP" | grep -q -E "$workVPN"; then
      isWorkNetwork=true
      isWorkVpn=true
    fi
  fi
fi

# Run Automation
if $isWorkNetwork; then
  $isDebug && echo "Running Connected Automation..."
  # Connected Automation
  while IFS= read -r line || [[ -n $line ]]; do
    $isDebug && echo "  $line..."
    run-item "$line"
  done < <(printf '%s' "$onConnect")

  # VPN Connected Automation
  if $isWorkVpn; then
    $isDebug && echo "Running VPN Connected Automation..."
    while IFS= read -r line || [[ -n $line ]]; do
      $isDebug && echo "  $line..."
      run-item "$line"
    done < <(printf '%s' "$onVPN")
  fi
fi

exit 0

## endregion ################################### Preference Variables