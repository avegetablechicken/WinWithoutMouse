# Win Without Mouse

Utilizing AutoHotKey to improve your productivity by operating fully via your keyboard!

## Installation

Install [AutoHotkey(v1.1)](https://www.autohotkey.com/). AutoHotkey 2 is not supported currently. You can either download them from official websites or by [Chocolatey](https://chocolatey.org/):

```powershell
choco install autohotkey
```

Then clone this repository add run "init.ahk", "proxy-menu.ahk" and "sync.ahk" to enable all the functions. You can also run "init.ahk" to enable the hotkeys.

Currently, all the hotkeys are based on a MacBook-style keyboard layout. You have to adjust the keyboard layout by updating the registry. You can use [SharpKeys](https://github.com/randyrants/sharpkeys) to help you manage it. Note that softwares such as using PowerToys or AutoHotKey itself may not work.

If you are using an ordinary keyboard for PC, you can change the hotkeys by running following commands in Command Prompt or PowerShell:

```powershell
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout" /v "Scancode Map" /t REG_BINARY /d 0000000000000000060000001D0038005BE01D0038005BE01DE038E038E01DE000000000
```

Otherwise, if you are using a MacBook-style keyboard, run the following command:

```powershell
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout" /v "Scancode Map" /t REG_BINARY /d 0000000000000000040000005BE01D001D005BE01DE05CE000000000
```

You need to log out and log in to make the changes take effect.

## Acknowledgement

Some codes are taken from the following repositories:

- [AutoHotkey-JSON](https://github.com/cocobelgica/AutoHotkey-JSON)

- [WatchFolder](https://github.com/AHK-just-me/WatchFolder)
