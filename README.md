# <img height="28" alt="toggle switch" src="https://github.com/user-attachments/assets/54f8838f-8b61-4931-a7f3-793973ad1eaa" /> Automatic Wi-Fi Toggle for macOS

⚠️ If you would like this added to Homebrew, click the star. Homebrew's [package acceptance policy](https://docs.brew.sh/Package-Acceptance-Policy#notability) normally requires 75 stars for a third-party submission or 225 stars for an owner self-submission. Fork and watcher thresholds can also qualify.

- When I connect my MacBook to a wired network, I'd like Wi-Fi to automatically turn off.
- When I disconnect my MacBook from all wired networks, I'd like Wi-Fi to automatically turn back on.

Sounds simple and obvious, but I couldn't find a tool to do this. I did find [this gist](https://gist.github.com/albertbori/1798d88a93175b9da00b#gistcomment-5913999) by Albert Bori. In 2024 I took Albert's basic idea and wrote `wifi-toggle.sh` from scratch to be as simple to use as possible.

For the last couple of years there has been a steady stream of comments on the gist and a couple of forks adding features. This repo is an attempt to provide a central place to document and improve the script.

## How it works

The script automatically discovers network hardware using macOS's built-in `networksetup` command. There is nothing to configure:

- Interfaces that support `networksetup -getairportpower` are treated as Wi-Fi.
- Other `en` interfaces are treated as wired interfaces.
- If any wired interface is active, Wi-Fi is turned off.
- When every wired interface becomes inactive, Wi-Fi is turned back on if this script previously turned it off.

This supports multiple Ethernet adapters, docks, and Thunderbolt interfaces. "Active" means the interface has an active link; it does not guarantee that the wired network has Internet access.

The script remembers when it turns Wi-Fi off. If you manually turn Wi-Fi off, it will respect that choice rather than turning Wi-Fi back on later.

## Installation

Follow these instructions with your normal user account. The script will show an error if you run it as `root`.

1. Download `wifi-toggle.sh` and move it to a stable location outside Desktop, Documents, or Downloads. For example:

    ```bash
    mkdir -p ~/bin
    mv ~/Downloads/wifi-toggle.sh ~/bin/
    chmod 755 ~/bin/wifi-toggle.sh
    ```

1. If `~/bin` is not in your `$PATH`, either add it to your path, add `wifi-toggle.sh` to another folder which is in your path, or use the full script path in the commands below.

1. Check the automatically detected interfaces:

    ```bash
    wifi-toggle.sh status
    ```

1. Test the toggle manually:

    ```bash
    wifi-toggle.sh run
    ```

1. Enable automatic toggling:

    ```bash
    wifi-toggle.sh on
    ```

    This installs and loads a service in `~/Library/LaunchAgents`. From now on:

    - If any wired interface is active, Wi-Fi will automatically turn off.
    - When every wired interface is inactive, Wi-Fi will turn back on if the script disabled it.

1. To stop automatic toggling:

    ```bash
    wifi-toggle.sh off
    ```

    This unloads and removes the launchd service. If the script previously disabled Wi-Fi, it also restores Wi-Fi.

Running `wifi-toggle.sh on` again safely updates the launchd service. Do this after moving the script to a different location.

## Upgrading

- Copy the new version of `wifi-toggle.sh` over the top of the old one (launchd will use the upgraded script the next time it runs).
- Run `wifi-toggle.sh on` to validate the installed service.

## Usage

```text
❯ wifi-toggle.sh help
Automatically toggle macOS Wi-Fi based on wired network status (uses launchd)

Usage: wifi-toggle.sh [ on | off | run | status | help ]
      on - start automatically toggling Wi-Fi (install launchd service)
     off - stop automatically toggling Wi-Fi (uninstall launchd service)
     run - toggle Wi-Fi now (also run automatically by launchd)
  status - show detected interfaces and launchd status
    help - show this help
```

The `status` command shows whether automatic toggling is enabled, every detected interface, and its current state:

```text
❯ wifi-toggle.sh status
Automatic toggle: enabled
Installed script: /Users/adam/bin/wifi-toggle.sh
Installed service version: 2
Wi-Fi interfaces:
  en0: on
Wired interfaces:
  en4: active
  en5: inactive
Wi-Fi restore pending: yes
```

The `run` command is a good way to test behavior before enabling the launchd service. Debug output explains which interfaces were detected and whether Wi-Fi needs to change:

```text
❯ wifi-toggle.sh run
DEBUG: Wi-Fi interfaces: en0
DEBUG: wired interfaces: en4 en5
DEBUG: wired interface en4 is inactive
DEBUG: wired interface en5 is inactive
DEBUG: all wired interfaces are inactive; Wi-Fi was not disabled by this script
```

## Troubleshooting

- First run `wifi-toggle.sh status`, followed by `wifi-toggle.sh run`. Errors from automatic interface discovery or Wi-Fi control will be shown directly.

- Inspect the loaded launchd service with:

    ```bash
    launchctl print gui/$(id -u)/nz.haume.wifi-toggle
    ```

- Validate the installed launchd file with:

    ```bash
    plutil -lint ~/Library/LaunchAgents/nz.haume.wifi-toggle.plist
    ```

- The script requires permission to write to `~/Library/LaunchAgents`. It creates that directory automatically when necessary.

- macOS may quarantine a script downloaded through a browser. If you downloaded the file from this repository and receive an `Operation not permitted` error, move it outside Desktop, Documents, and Downloads. If necessary, remove its quarantine attribute:

    ```bash
    xattr -d com.apple.quarantine ~/bin/wifi-toggle.sh
    ```

- Do not run the script as `root`. A per-user launchd agent must be installed by the user it belongs to.

- If a wired link is active but has no Internet access, the script still considers it active and turns Wi-Fi off. Disconnect that interface or disable automatic toggling with `wifi-toggle.sh off`.
