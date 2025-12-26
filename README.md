# Automatic WiFi Toggle for macOS

When my MacBook is connected to an ethernet connection, I'd like my WiFi to automatically turn off.  
When I disconnect the ethernet, I'd like my WiFi to automatically turn back on. 

Sounds simple and obvious, but I couldn't find a tool to do this. I did find [this gist](https://gist.github.com/albertbori/1798d88a93175b9da00b#gistcomment-5913999) by Albert Bori. In 2024 I took Albert's basic idea and wrote `wifi-toggle.sh` from scratch to be as simple to use as possible.

For the last couple years there's been a steady stream of comments on the gist and a couple of forks to add features. This repo is an attempt to provide a central place to document and improve the script.

## Installation

Follow the below instructions with your normal user account (‼️ it will not work if you run it as `root` ‼️).

1. Download `wifi-toggle.sh` and move it to somewhere in your path (eg. `/usr/local/bin`)
   
1. Give the script execute permissions: `chmod 755 wifi-toggle.sh`

1. List your network devices by running: `networksetup -listnetworkserviceorder`

    ```
    > networksetup -listnetworkserviceorder
    An asterisk (*) denotes that a network service is disabled.
    (1) Thunderbolt Ethernet Slot 0
    (Hardware Port: Thunderbolt Ethernet Slot 0, Device: en3)
    
    (2) Wi-Fi
    (Hardware Port: Wi-Fi, Device: en0)
    ```

1. You are looking for the device name of your ethernet device. In the above example that's "Thunderbolt Ethernet Slot 0".

1. Edit `wifi-toggle.sh` and change the ETHERNET_REGEX variable to match the name of your ethernet device. It doesn't have to be the full name of the device, but it **MUST** uniquely match only a single ethernet device. In this case either "Thunderbolt" or "Ethernet" would work fine. If it matches more than one device, the script will error.

1. The script is setup to use the builtin Mac WiFi device called `Wi-Fi`. If you are using another device (eg. a USB WiFi adapter) you will also need to update the `WIFI_REGEX` variable.

1. Run `wifi-toggle.sh on` and it will install a launchd service in `~/Library/LaunchAgents`.  From now on ...

    - If your ethernet is active, your wifi will automatically turn off
    - If your ethernet is inactive, your wifi will automatically turn on.

1. If you want to stop the automatic toggle, remove the launchd service by running `wifi-toggle.sh off`.  You can enable it again anytime you like by running `wifi-toggle.sh on` again.

⚠️ ⚠️ ⚠️ If the script isn't working as expected, carefully read what it prints to the screen. It will usually show the error. 

## Usage

```
❯ wifi-toggle.sh help
Automatically toggle macOS Wi-Fi based on ethernet status (uses launchd)

Usage: wifi-toggle.sh [ on | off | help ]
   on - start automatically toggling Wi-Fi (install launchd service)
  off - stop automatically toggling Wi-Fi (uninstall launchd service)
  run - Toggle Wi-Fi status
```

Run the toggle manually.  This is a good way to test that everything is working as expected before you enable the launchd service to autmatically toggle.

If the script things your WiFi is correct, you'll see something like the below (pay attention to the last line).

```
> ~/bin/darwin/wifi-toggle.sh run
DEBUG: get_interface(): regex 'Ethernet' -> interface 'en3'
DEBUG: get_interface(): regex '(Wi-Fi|Airport)' -> interface 'en0'
DEBUG: ethernet status: 'inactive', wifi status: 'active'
DEBUG: not toggling wifi status
```

If the script thinks you're WiFi status needs to be changed, you'll see something like this:

```
> ~/bin/darwin/wifi-toggle.sh run
DEBUG: get_interface(): regex 'Ethernet' -> interface 'en3'
DEBUG: get_interface(): regex '(Wi-Fi|Airport)' -> interface 'en0'
DEBUG: ethernet status: 'inactive', wifi status: 'inactive'
DEBUG: enabling wifi
```

## Troubleshooting

- Sometimes write permssion to `~/Library/LaunchAgents` is restricted (I don't know why). If so you will see an error when the script runs that looks something like:
   ```
  /wifi-toggle.sh: line 53: /Users/adam/Library/LaunchAgents/nz.haume.wifi-toggle.plist: Permission denied
  ```
  
- If you are somewhere without WiFi or ethernet and want to WiFi to stay disabled, you'll need to disable the script with `wifi-toggle.sh off`.

- If you have more than one ethernet device, make sure that `ETHERNET_REGEX` only matches the device you want to monitor. Currently the script doesn't support monitoring more than one ethernet device.
