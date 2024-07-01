#Include JSON.ahk

modsSymbols := { control: "^", alt: "!", win: "#", shift: "+" }
remapModsStandard := {
(Join
  left_shift: "LShift",
  right_shift: "RShift",
  left_control: "LCtrl",
  right_control: "RCtrl",
  left_alt: "LAlt",
  right_alt: "RAlt",
  left_windows: "LWin",
  right_windows: "RWin"
)}
nonModifierHypers := []

LoadKeybindings(filename)
{
  Global modsSymbols, remapModsStandard, nonModifierHypers

  keybindingConfigs := JSON.Load(FileOpen("config\keybindings.json", "r").Read())

  If (keybindingConfigs.remap != "")
  {
    maps := {}
    If FileExist(A_Programs "\Parallels Shared Applications")
      maps := keybindingConfigs.remap.fromMac
    Else
      maps := keybindingConfigs.remap.default
    newMaps := {}
    For src, dst in maps
    {
      newSrc := remapModsStandard[src]
      newDst := remapModsStandard[dst]
      If (newSrc != "" And newDst != "")
        newMaps[newSrc] := newDst
    }
    keybindingConfigs.remap := newMaps
  }

  For k, hp in keybindingConfigs.hyper
  {
    modsRepr := ""
    If Not isObject(hp)
    {
      If modsSymbols[hp] != ""
        modsRepr := modsSymbols[hp]
      Else
      {
        modsRepr := hp
        nonModifierHypers[modsRepr] := 1
      }
    }
    Else
    {
      For modName, symbol in modsSymbols
      {
        For _, mod in hp
          If (mod = modName)
            modsRepr .= symbol
      }
    }
    keybindingConfigs.hyper[k] := modsRepr
  }

  For cat, config in keybindingConfigs.hotkeys
  {
    For hkID, spec in config
    {
      If spec.mods != ""
        spec.mods := _GetAHKMods(spec.mods, keybindingConfigs)
      Else
        For _, entry in spec
          entry.mods := _GetAHKMods(entry.mods, keybindingConfigs)
    }
  }

  Return keybindingConfigs
}

_GetAHKMods(mods, config)
{
  Global modsSymbols

  If Not IsObject(mods)
  {
    If RegExMatch(mods, "\${(.*)}", hkMatch) != 0
    {
      modsRepr := config
      For _, key in StrSplit(hkMatch1, ".")
        modsRepr := modsRepr[key]
    }
    Else
      mods := [mods]
  }
  If IsObject(mods)
  {
    modsRepr := ""
    For modName, symbol in modsSymbols
    {
      For _, mod in mods
        If (mod = modName)
          modsRepr .= symbol
    }
  }
  Return modsRepr
}

Bind(spec, func)
{
  Global nonModifierHypers

  If IsObject(spec)
  {
    If (nonModifierHypers[spec.mods] != "")
      hk := % spec.mods " & " spec.key
    Else
      hk := spec.mods . spec.key
  }
  Else
    hk := spec
  Hotkey, % hk, % func
  Return hk
}

Class _Sender {
  __New(param) {
    this.param := param
  }

  __Call() {
    Send, % this.param
  }
}

Remap(src, dsc)
{
  If IsObject(src)
  {
    If nonModifierHypers[src.mods] != ""
      hk := src.mods " & " src.key
    Else
      hk := src.mods src.key
  }
  Else
    hk := src
  sender := New _Sender(dsc)
  Hotkey, % hk, % sender
}

RegistryRemapModifiers(maps, dryrun := False)
{
  Static SCANCODE_MAP := {
  (Join
    LCtrl: "1D00",
    RCtrl: "1DE0",
    LShift: "2A00",
    RShift: "3600",
    LAlt: "3800",
    RAlt: "38E0",
    LWin: "5BE0",
    RWin: "5CE0",

    LControl: "1D00",
    RControl: "1DE0"
  )}

  Static HEADER := "0000000000000000"
  Static TAILER := "00000000"

  If maps.Count() = 0 Or maps.Count() > 0xFF
    Return
  scancode := HEADER . Format("{:02X}", maps.Count() + 1) . "000000"
  for src, dst in maps
  {
    srcCode := SCANCODE_MAP[src]
    dstCode := SCANCODE_MAP[dst]
    If (srcCode = "" Or dstCode = "")
      Return
    scancode .= dstCode . srcCode
  }
  scancode .= TAILER

  If Not dryrun
  {
    RegRead, oldScanCode, HKEY_LOCAL_MACHINE, SYSTEM\CurrentControlSet\Control\Keyboard Layout, Scancode Map
    If (oldScanCode != scancode)
    {
      MsgBox, 4,, Do you want to write new scancode map to registry?,
      IfMsgBox, Yes
      {
        RegWrite, REG_BINARY, HKEY_LOCAL_MACHINE, SYSTEM\CurrentControlSet\Control\Keyboard Layout, Scancode Map, % scancode
        MsgBox, 4,, you have to log out to apply the changes. Log out now?
        IfMsgBox, Yes
          Shutdown, 0
      }
    }
  }
  Return scancode
}