#Include JSON.ahk

modsSymbols := { control: "^", alt: "!", win: "#", shift: "+" }
nonModifierHypers := []

LoadKeybindings(filename)
{
  Global modsSymbols, nonModifierHypers

  keybindingConfigs := JSON.Load(FileOpen("config\keybindings.json", "r").Read())
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