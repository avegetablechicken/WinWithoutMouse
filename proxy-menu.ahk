#SingleInstance force
#NoEnv
#Persistent

; ----------------------------------------
;          auto-reload on change
; ----------------------------------------
#Include WatchFolder.ahk
WatchFolder(A_ScriptDir, "_ReloadHelper", False, 16)
_ReloadHelper(dir, changes) {
  Static relatedFiles := ["proxy-menu.ahk", "utils.ahk", "WatchFolder.ahk", "JSON.ahk"]
  For index, filename in relatedFiles
  {
    watchedFile := dir . "\" . filename
    For Each, change In changes
      If (change.action = 3 And change.name = watchedFile)
      {
        Reload
        Sleep 1000
      }
  }
}

#Include JSON.ahk
LoadProxies(table, filename)
{
  proxyJson := JSON.Load(FileOpen(filename, "r").Read())
  For name, config in proxyJson
  {
    If (config.condition != "")
    {
      entry := Object()
      entry.condition := config.condition
      entry.locations := config.locations
      For i, loc in config.locations
      {
        entry[loc] := _LoadProxyEntry(config[loc])
      }
    }
    Else
    {
      entry := _LoadProxyEntry(config)
    }
    
    table[name] := entry
  }
}

_LoadProxyEntry(config)
{
  entry := Object()
  If (config.global != "")
  {
    entry.global := Object()
    For i, spec in ["socks5", "http", "https"]
    {
      If (config.global[spec] != "")
      {
        address := StrSplit(config.global[spec], ":")
        entry.global[spec] := Object()
        entry.global[spec].ip := address[1]
        entry.global[spec].port := address[2]
      }
    }
  }
  If (config.pac != "")
  {
    entry.PAC := config.pac
  }
  Return entry
}

proxyConfigs := Object()
If FileExist("config\proxy.json")
  LoadProxies(proxyConfigs, "config\proxy.json")
If FileExist("config\private-proxy.json")
  LoadProxies(proxyConfigs, "config\private-proxy.json")

RegRootKey = HKEY_CURRENT_USER
RegSubKey  = Software\Microsoft\Windows\CurrentVersion\Internet Settings

appJsonObj := JSON.Load(FileOpen("config\application.json", "r").Read())
ShadowSocks_Installed := _CheckInstallation("shadowsocks")
v2rayN_Installed := _CheckInstallation("v2rayn")
MonoCloud_Installed := _CheckInstallation("monocloud")
If Not ShadowSocks_Installed
  proxyConfigs.Delete("ShadowSocks")
If Not v2rayN_Installed
  proxyConfigs.Delete("v2rayN")
If Not MonoCloud_Installed
  proxyConfigs.Delete("MonoCloud")

conditionSatisfied := Object()
For name, config in proxyConfigs
{
  If (config.condition != "")
    conditionSatisfied[name] := _CheckCondition(config.condition)
}

trayEntries := Object()
index := 0
trayEntries["Info"]     := "&Information"
trayEntries["Disable"]  := "Disable`t&" . index
index++
For i, name in ["System", "ShadowSocks", "v2rayN", "MonoCloud"]
{
  config := proxyConfigs[name]
  If (config != "")
  {
    trayEntries[name] := Object()
    index := _countTrayEntries(trayEntries[name], config, index, conditionSatisfied[name])
  }
}
For name, config in proxyConfigs
{
  If (trayEntries[name] == "")
  {
    trayEntries[name] := Object()
    index := _countTrayEntries(trayEntries[name], config, index, conditionSatisfied[name])
  }
}
_countTrayEntries(entry, config, index, cond)
{
  If (cond != "")
  {
    If cond
      validConfig := config[config.locations[1]]
    Else
      validConfig := config[config.locations[2]]
  }
  Else
    validConfig := config

  If (validConfig.global != "")
  {
    entry.globalMenu    := "    Global Mode`t&" . index
    entry.global        := validConfig.global
    entry.index         := index
    index++
  }
  If (validConfig.PAC != "")
  {
    entry.PACMenu       := "    PAC Mode`t&" . index
    entry.PAC           := validConfig.PAC
    entry.index         := index
    index++
  }
  return index
}
trayEntries["ProxyInfo1"]     := ""
trayEntries["ProxyInfo2"]     := ""

activeProxy :=

Menu, Tray, Tip, Proxy Menu
Menu, Tray, NoStandard
Menu, Tray, Click, 1
Menu, Tray, Add, % trayEntries["Info"], ShowProxyInfo
Menu, Tray, Add, % trayEntries["Disable"], ClearProxy
Menu, Tray, Add
For i, name in ["System", "ShadowSocks", "v2rayN", "MonoCloud"]
{
  entries := trayEntries[name]
  If (entries == "")
    Continue
  If (name == "System")
  {
    Menu, Tray, Add, System, NoOperation
    If (entries.globalMenu != "")
      Menu, Tray, Add, % entries.globalMenu, EnableProxy
    If (entries.PACMenu != "")
      Menu, Tray, Add, % entries.PACMenu, EnableProxy
    Menu, Tray, Add
    Menu, Tray, Disable, System
  }
  If (name == "ShadowSocks")
  {
    Menu, Tray, Add, &ShadowSocks, ShowShadowSocksWindow
    If (entries.globalMenu != "")
      Menu, Tray, Add, % entries.globalMenu, EnableShadowSocks
    If (entries.PACMenu != "")
      Menu, Tray, Add, % entries.PACMenu, EnableShadowSocksPAC
    Menu, Tray, Add
    Menu, Tray, Disable, &ShadowSocks
  }
  If (name == "v2rayN")
  {
    Menu, Tray, Add, &v2rayN, ShowV2rayNWindow
    If (entries.globalMenu != "")
      Menu, Tray, Add, % entries.globalMenu, EnableV2rayN
    If (entries.PACMenu != "")
      Menu, Tray, Add, % entries.PACMenu, EnableV2rayNPAC
    Menu, Tray, Add
  }
  If (name == "MonoCloud")
  {
    Menu, Tray, Add, &MonoCloud, ShowMonoCloudWindow
    If (entries.globalMenu != "")
      Menu, Tray, Add, % entries.globalMenu, EnableMonoCloud
    Menu, Tray, Add
    Menu, Tray, Disable, &MonoCloud
  }
}
For name, entries in trayEntries
{
  If name Not in System,shadowsocks,v2rayn,monocloud
  {
    If IsObject(entries)
    {
      Menu, Tray, Add, % name, NoOperation
      If (entries.globalMenu != "")
        Menu, Tray, Add, % entries.globalMenu, EnableProxy
      If (entries.PACMenu != "")
        Menu, Tray, Add, % entries.PACMenu, EnableProxy
      Menu, Tray, Add
      Menu, Tray, Disable, % name
    }
  }
}
Menu, Tray, Add, &Proxy Settings, OpenProxySettings

_CheckInstallation(app)
{
  Global appJsonObj

  If (FileExist(appJsonObj[app].run))
  {
    ; absolute path of an executable
    Return appJsonObj[app].run
  }
  Else
  {
    ; relative path of a link in start menu
    appLnkSearchDirs := [
    (Join
      A_ProgramsCommon,
      A_Programs,
      A_Programs "\Scoop Apps"
    )]

    For i, dir In appLnkSearchDirs
    {
      If (FileExist(dir "\" appJsonObj[app].link ".lnk"))
      {
        Return dir "\" appJsonObj[app].link ".lnk"
      }
    }
  }
}

_IsRunning(app)
{
  Global appJsonObj

  procStem := appJsonObj[app].process
  If IsObject(procStem)
  {
    For _, proc in procStem
    {
      If _IsRunningSingleProc(proc)
        Return True
    }
    Return False
  }
  Else
    Return _IsRunningSingleProc(procStem)
}

_IsRunningSingleProc(procStem)
{
  proc := procStem . ".exe"

  If Instr(proc, "*")
  {
    proc := StrReplace(proc, ".", "\.")
    proc := StrReplace(proc, "*", ".*")
    proc := "^" . proc . " "
    shell_command = tasklist | findStr %proc%
    RunWait, %ComSpec% /c %shell_command% > nul 2>&1,, Hide
    Return %ErrorLevel% = 0
  }
  Else
  {
    Process, Exist, %proc%
    If ErrorLevel = 0
      Return False
    Else
      Return True
  }
}

_CheckCondition(cond)
{
  If (cond.shell_command != "")
  {
    shell_command := cond.shell_command
    RunWait, %ComSpec% /c %shell_command% > nul 2>&1,, Hide
    Return %ErrorLevel% = 0
  }
}

_CheckProxyAvailable(ip, port)
{
  EnvGet, HOME_DIR, USERPROFILE
  RunWait, %ComSpec% /c %HOME_DIR%\scoop\shims\echo.EXE 'qcloseq' | telnet -e 'q' %ip% %port% > nul 2>&1,, Hide
  Return %ErrorLevel% = 0
}

_CheckConditionChange()
{
  Global proxyConfigs, conditionSatisfied

  For name, satisfiesOld in conditionSatisfied
  {
    satisfied := _CheckCondition(proxyConfigs[name].condition)
    conditionSatisfied[name] := satisfied
    If (satisfiesOld != satisfied)
      EnableProxy(A_ThisMenuItem)
  }
}

NoOperation()
{}

OpenProxySettings()
{
  Global RegRootKey, RegSubKey

  Run ms-settings:network-proxy
  RegRead, outputEnable, % RegRootKey, % RegSubKey, ProxyEnable
  RegRead, outputGlobal, % RegRootKey, % RegSubKey, ProxyServer
  RegRead, outputPAC, % RegRootKey, % RegSubKey, AutoConfigURL
  WinWait ahk_exe ApplicationFrameHost.exe
  Sleep 100
  If outputGlobal And outputEnable = 1
    Send, {Tab}{Tab}{Enter}
  Else If outputPAC
    Send, {Tab}{Enter}
}

ShowShadowSocksWindow()
{
}

ShowV2rayNWindow()
{
  If (_CheckLaunch("v2rayn") == 0)
    Send +!{F1}
}

ShowMonoCloudWindow()
{
}

_UnCheckAllProxies()
{
  Global trayEntries
  Global ShadowSocks_Installed, v2rayN_Installed, MonoCloud_Installed

  Menu, Tray, UnCheck, % trayEntries["Disable"]
  For name, entries in trayEntries
  {
    If (entries.globalMenu != "")
      Menu, Tray, UnCheck, % entries.globalMenu
    If (entries.PACMenu != "")
      Menu, Tray, UnCheck, % entries.PACMenu
  }
  If trayEntries["ProxyInfo1"]
  {
    Menu, Tray, Delete, % trayEntries["ProxyInfo1"]
    trayEntries["ProxyInfo1"] := ""
  }
  If trayEntries["ProxyInfo2"]
  {
    Menu, Tray, Delete, % trayEntries["ProxyInfo2"]
    trayEntries["ProxyInfo2"] := ""
  }
}

proxyInfo := ""
ShowProxyInfo()
{
  Global proxyInfo
  _CheckProxy()
  MsgBox, 0x144, Proxy Information, %proxyInfo%`nConfigure proxy in settings?
  IfMsgBox Yes
    Run ms-settings:network-proxy
}

ClearProxy()
{
  Global RegRootKey, RegSubKey
  Global trayEntries

  RegDelete, % RegRootKey, % RegSubKey, AutoConfigURL
  RegWrite, REG_SZ, % RegRootKey, % RegSubKey, ProxyServer,
  RegWrite, REG_DWORD, % RegRootKey, % RegSubKey, ProxyEnable, 0

  _UnCheckAllProxies()
  Menu, Tray, Check, % trayEntries["Disable"]
}

EnableProxy(ItemName)
{
  Global RegRootKey, RegSubKey
  Global proxyConfigs, trayEntries, conditionSatisfied

  activeProxy :=
  FirstMenuItemName :=
  For name, entries in trayEntries
  {
    If Not IsObject(entries)
      Continue
    config := proxyConfigs[name]
    If (conditionSatisfied[name] != "")
    {
      If (conditionSatisfied[name])
        config := config[config.locations[1]]
      Else
        config := config[config.locations[2]]
    }
    If (entries.globalMenu == ItemName)
    {
      activeProxy := config.global
      FirstMenuItemName := entries.globalMenu
      Break
    }
    Else If (entries.PACMenu == ItemName)
    {
      activeProxy := config.PAC
      If (entries.globalMenu != "")
        FirstMenuItemName := entries.globalMenu
      Else
        FirstMenuItemName := entries.PACMenu
      Break
    }
  }

  _UnCheckAllProxies()
  If IsObject(activeProxy)
  {
    If (activeProxy.http != "")
    {
      ip := activeProxy.http.ip
      port := activeProxy.http.port
    }
    Else If (activeProxy.https != "")
    {
      ip := activeProxy.https.ip
      port := activeProxy.https.port
    }
    RegDelete, % RegRootKey, % RegSubKey, AutoConfigURL
    RegWrite, REG_SZ, % RegRootKey, % RegSubKey, ProxyServer, % ip . ":" . port
    RegWrite, REG_DWORD, % RegRootKey, % RegSubKey, ProxyEnable, 1
    _EnableProxyMenu(ItemName, FirstMenuItemName, ip, port, activeProxy.socks5)
  }
  Else
  {
    PAC := activeProxy
    RegWrite, REG_SZ, % RegRootKey, % RegSubKey, ProxyServer,
    RegWrite, REG_DWORD, % RegRootKey, % RegSubKey, ProxyEnable, 0
    RegWrite, REG_SZ, % RegRootKey, % RegSubKey, AutoConfigURL, % PAC
    _EnableProxyMenu(ItemName, FirstMenuItemName, PAC)
  }
}

_EnableProxyMenu(ItemName, position, ip, port := "", socks5 := "")
{
  Global trayEntries

  If (port != "")
  {
    Menu, Tray, Check, % ItemName
    trayEntries["ProxyInfo1"] := "HTTP Proxy: http://" .  ip . ":" . port
    Menu, Tray, Insert, % position, % trayEntries["ProxyInfo1"], NoOperation
    Menu, Tray, Disable, % trayEntries["ProxyInfo1"]
    If (socks5 != "")
    {
      ip := socks5.ip
      port := socks5.port
      trayEntries["ProxyInfo2"] := "SOCKS5 Proxy: http://" .  ip . ":" . port
      Menu, Tray, Insert, % position, % trayEntries["ProxyInfo2"], NoOperation
      Menu, Tray, Disable, % trayEntries["ProxyInfo2"]
    }
  }
  Else
  {
    PACURL := ip
    Menu, Tray, Check, % ItemName
    trayEntries["ProxyInfo1"] := "PAC File: " . PACURL
    Menu, Tray, Insert, % position, % trayEntries["ProxyInfo1"], NoOperation
    Menu, Tray, Disable, % trayEntries["ProxyInfo1"]
  }
}

; need to configure shift+ctrl+F2 as hotkey for change proxy mode in `ShadowSocks`
; assume that if enabled proxy is ShadowSocks, then ShadowSocks has been running

EnableShadowSocks()
{
  _CheckLaunch("shadowsocks")

  ret := _CheckProxy()
  enabledProxy := ret.1
  If (enabledProxy == "ShadowSocks (Global)")
    Return
  Else If (enabledProxy == "ShadowSocks (PAC)")
    Send +^{F2}
  Else
  {
    Sleep 1000
    Send +^{F2}
    Sleep 2000
    ret := _CheckProxy()
    enabledProxy := ret.1
    If (enabledProxy == "ShadowSocks (PAC)")
      Send +^{F2}
  }

  _UnCheckAllProxies()
  _EnableShadowSocksMenu()
}

_EnableShadowSocksMenu(spec := "")
{
  Global proxyConfigs, trayEntries

  Menu, Tray, Check, % trayEntries["ShadowSocks"].globalMenu
  If (spec == "")
  {
    If (proxyConfigs["ShadowSocks"].global.http != "")
      spec := proxyConfigs["ShadowSocks"].global.http
    Else
      spec := proxyConfigs["ShadowSocks"].global.https
  }
  ip := spec.ip
  port := spec.port
  trayEntries["ProxyInfo1"] := "Proxy: http://" .  ip . ":" . port
  Menu, Tray, Insert, % trayEntries["ShadowSocks"].globalMenu, % trayEntries["ProxyInfo1"], NoOperation
  Menu, Tray, Disable, % trayEntries["ProxyInfo1"]
}

EnableShadowSocksPAC()
{
  _CheckLaunch("shadowsocks")

  ret := _CheckProxy()
  enabledProxy := ret.1
  If (enabledProxy == "ShadowSocks (PAC)")
    Return
  Else If (enabledProxy == "ShadowSocks (Global)")
    Send +^{F2}
  Else
  {
    Sleep 1000
    Send +^{F2}
    Sleep 2000
    ret := _CheckProxy()
    enabledProxy := ret.1
    If (enabledProxy == "ShadowSocks (Global)")
      Send +^{F2}
  }

  _UnCheckAllProxies()
  _EnableShadowSocksPACMenu()
}

_EnableShadowSocksPACMenu()
{
  Global proxyConfigs, trayEntries
  
  Menu, Tray, Check, % trayEntries["ShadowSocks"].PACMenu
  PACURL := proxyConfigs["ShadowSocks"].PAC
  trayEntries["ProxyInfo1"] := "PAC File: " . PACURL . "?hash=..."
  Menu, Tray, Insert, % trayEntries["ShadowSocks"].globalMenu, % trayEntries["ProxyInfo1"], NoOperation
  Menu, Tray, Disable, % trayEntries["ProxyInfo1"]
}

; need to configure shift+{alt+}ctrl+F1 as hotkey for change proxy mode in `v2rayN`
; assume that if enabled proxy is v2rayN, then v2rayN has been running

EnableV2rayN()
{
  Global proxyConfigs, appJsonObj
  Global RegRootKey, RegSubKey

  If (_CheckLaunch("v2rayn") == 1)
  {
    proc := appJsonObj["v2rayn"].process . ".exe"
    WinWait, ahk_exe %proc%
    Send +!{F1}
  }
  Send +!^{F1}

  If (proxyConfigs["v2rayN"].global.http != "")
    spec := proxyConfigs["v2rayN"].global.http
  Else
    spec := proxyConfigs["v2rayN"].global.https
  ip := spec.ip
  port := spec.port
  RegDelete, % RegRootKey, % RegSubKey, AutoConfigURL
  RegWrite, REG_SZ, % RegRootKey, % RegSubKey, ProxyServer, % ip . ":" . port
  RegWrite, REG_DWORD, % RegRootKey, % RegSubKey, ProxyEnable, 1
  
  _UnCheckAllProxies()
  _EnableV2rayNMenu(spec)
}

_EnableV2rayNMenu(spec := "")
{
  Global proxyConfigs, trayEntries

  Menu, Tray, Check, % trayEntries["v2rayN"].globalMenu
  If (spec == "")
  {
    If (proxyConfigs["v2rayN"].global.http != "")
      spec := proxyConfigs["v2rayN"].global.http
    Else
      spec := proxyConfigs["v2rayN"].global.https
  }
  ip := spec.ip
  port := spec.port
  socksip := proxyConfigs["v2rayN"]["global"]["socks5"]["ip"]
  socksport := proxyConfigs["v2rayN"]["global"]["socks5"]["port"]
  trayEntries["ProxyInfo1"] := "HTTP Proxy: http://" .  ip . ":" . pport
  trayEntries["ProxyInfo2"] := "SOCKS5 Proxy: http://" .  socksip . ":" . socksport
  Menu, Tray, Insert, % trayEntries["v2rayN"].globalMenu, % trayEntries["ProxyInfo1"], NoOperation
  Menu, Tray, Insert, % trayEntries["v2rayN"].globalMenu, % trayEntries["ProxyInfo2"], NoOperation
  Menu, Tray, Disable, % trayEntries["ProxyInfo1"]
  Menu, Tray, Disable, % trayEntries["ProxyInfo2"]
}

EnableV2rayNPAC()
{
  Global appJsonObj
  If (_CheckLaunch("v2rayn") == 1)
  {
    proc := appJsonObj["v2rayn"].process . ".exe"
    WinWait, ahk_exe %proc%
    Send +!{F1}
  }
  Send +!^{F1}
  Send +^{F1}

  _UnCheckAllProxies()
  _EnableV2rayNPACMenu()
}

_EnableV2rayNPACMenu()
{
  Global proxyConfigs, trayEntries

  Menu, Tray, Check, % trayEntries["v2rayN"].PACMenu
  PACURL := proxyConfigs["v2rayN"]["PAC"]
  trayEntries["ProxyInfo1"] := "PAC: " . PACURL . "?t=..."
  Menu, Tray, Insert, % trayEntries["v2rayN"].globalMenu, % trayEntries["ProxyInfo1"], NoOperation
  Menu, Tray, Disable, % trayEntries["ProxyInfo1"]
}

EnableMonoCloud()
{
  Global proxyConfigs
  Global RegRootKey, RegSubKey

  _CheckLaunch("monocloud")

  If (proxyConfigs["monocloud"].global.http != "")
    spec := proxyConfigs["monocloud"].global.http
  Else
    spec := proxyConfigs["monocloud"].global.https
  ip := spec.ip
  port := spec.port
  RegDelete, % RegRootKey, % RegSubKey, AutoConfigURL
  RegWrite, REG_SZ, % RegRootKey, % RegSubKey, ProxyServer, % ip . ":" . port
  RegWrite, REG_DWORD, % RegRootKey, % RegSubKey, ProxyEnable, 1

  _UnCheckAllProxies()
  _EnableMonoCloudMenu(spec)
}

_EnableMonoCloudMenu(spec := "")
{
  Global proxyConfigs, trayEntries

  Menu, Tray, Check, % trayEntries["MonoCloud"].globalMenu
  If (spec == "")
  {
    If (proxyConfigs["MonoCloud"].global.http != "")
      spec := proxyConfigs["MonoCloud"].global.http
    Else
      spec := proxyConfigs["MonoCloud"].global.https
  }
  ip := spec.ip
  port := spec.port
  trayEntries["ProxyInfo1"] := "Proxy: http://" .  ip . ":" . port
  Menu, Tray, Insert, % trayEntries["MonoCloud"].globalMenu, % trayEntries["ProxyInfo1"], NoOperation
  Menu, Tray, Disable, % trayEntries["ProxyInfo1"]
}

_Launch(app)
{
  Global appJsonObj
  cmd_run := ""

  If appJsonObj[app].run          ; shortcut or absolute path
    cmd_run := appJsonObj[app].run
  Else If appJsonObj[app].url       ; url
    cmd_run := appJsonObj[app].url
  Else                  ; relative path of a link in start menu
  {
    appLnkSearchDirs := [
    (Join
      A_Programs,
      A_Programs "\Scoop Apps",
      A_ProgramsCommon
    )]

    For i, dir In appLnkSearchDirs
    {
      link := dir "\" appJsonObj[app].link ".lnk"
      If FileExist(link)
      {
        cmd_run := link
        Break
      }
    }
  }

  If Not cmd_run
    MsgBox, % "Cannot find " appJsonObj[app].cmd_run
  Else
    Run % cmd_run
}

_CheckLaunch(app)
{
  If Not _IsRunning(app)
  {
    _Launch(app)
    Return 1
  }
  Else
    Return 0
}

_MatchWebProxy(spec, regOutput)
{
  If (spec != "")
  {
    If (spec.http != "" And regOutput == spec.http.ip . ":" . spec.http.port)
      Return spec.http
    Else If (spec.https != "" And regOutput == spec.https.ip . ":" . spec.https.port)
      Return spec.https
  }
}

_CheckProxy()
{
  Global proxyConfigs, trayEntries, conditionSatisfied
  Global RegRootKey, RegSubKey
  Global proxyInfo
  Global ShadowSocks_Installed, v2rayN_Installed, MonoCloud_Installed

  _UnCheckAllProxies()

  RegRead, outputEnable, % RegRootKey, % RegSubKey, ProxyEnable
  RegRead, outputGlobal, % RegRootKey, % RegSubKey, ProxyServer
  RegRead, outputPAC, % RegRootKey, % RegSubKey, AutoConfigURL

  enabledProxy := ""
  If outputGlobal And outputEnable = 1
  {
    For name, satisfied in conditionSatisfied
    {
      If (satisfied)
        entry := proxyConfigs[name][proxyConfigs[name].locations[1]]
      Else
        entry := proxyConfigs[name][proxyConfigs[name].locations[2]]
      spec := _MatchWebProxy(entry.global, outputGlobal)
      If (spec != "")
      {
        enabledProxy := name . " (Global)"
        _EnableProxyMenu(trayEntries[name].globalMenu, trayEntries[name].globalMenu, spec.ip, spec.port, entry.global.socks5)
        Goto L_END_CHECKPROXY
      }
    }
    If v2rayN_Installed
    {
      spec := _MatchWebProxy(proxyConfigs["v2rayN"]["global"], outputGlobal)
      If (spec != "" and _IsRunning("v2rayn"))
      {
        enabledProxy := "v2rayN (Global)"
        _EnableV2rayNMenu(spec)
        Goto L_END_CHECKPROXY
      }
    }
    Else If ShadowSocks_Installed
    {
      spec := _MatchWebProxy(proxyConfigs["ShadowSocks"].global, outputGlobal)
      If (spec != "" and _IsRunning("shadowsocks"))
      {
        enabledProxy := "ShadowSocks (Global)"
        _EnableShadowSocksMenu(spec)
        Goto L_END_CHECKPROXY
      }
    }
    Else If MonoCloud_Installed
    {
      spec := _MatchWebProxy(proxyConfigs["MonoCloud"].global, outputGlobal)
      If (spec != "" and _IsRunning("monocloud"))
      {
        enabledProxy := "MonoCloud"
        _EnableMonoCloudMenu(spec)
        Goto L_END_CHECKPROXY
      }
    }
    For name, config in proxyConfigs
    {
      If name Not in shadowsocks,v2rayn,monocloud And (conditionSatisfied[name] == "")
      {
        If (config.global != "")
        {
          spec := _MatchWebProxy(config.global, outputGlobal)
          If (spec != "")
          {
            enabledProxy := name . " (Global)"
            _EnableProxyMenu(trayEntries[name].globalMenu, trayEntries[name].globalMenu, spec.ip, spec.port, config.global.socks5)
            Goto L_END_CHECKPROXY
          }
        }
      }
    }
    RegWrite, REG_DWORD, % RegRootKey, % RegSubKey, ProxyEnable, 0
  }
  If outputPAC
  {
    For name, satisfied in conditionSatisfied
    {
      If (satisfied)
        entry := proxyConfigs[name][proxyConfigs[name].locations[1]]
      Else
        entry := proxyConfigs[name][proxyConfigs[name].locations[2]]
      If Instr(outputPAC, entry.PAC)
      {
        enabledProxy := name . " (PAC)"
        If (trayEntries[name].globalMenu != "")
          _EnableProxyMenu(trayEntries[name].PACMenu, trayEntries[name].globalMenu, entry.PAC)
        Else
          _EnableProxyMenu(trayEntries[name].PACMenu, trayEntries[name].PACMenu, entry.PAC)
        Goto L_END_CHECKPROXY
      }
    }
    If v2rayN_Installed And InStr(outputPAC, proxyConfigs["v2rayN"].PAC) And _IsRunning("v2rayn")
    {
      enabledProxy := "v2rayN (PAC)"
      _EnableV2rayNPACMenu()
      Goto L_END_CHECKPROXY
    }
    Else If ShadowSocks_Installed And InStr(outputPAC, proxyConfigs["ShadowSocks"].PAC And _IsRunning("shadowsocks"))
    {
      enabledProxy := "ShadowSocks (PAC)"
      _EnableShadowSocksPACMenu()
      Goto L_END_CHECKPROXY
    }
    For name, config in proxyConfigs
    {
      If name Not in shadowsocks,v2rayn,monocloud And (conditionSatisfied[name] == "")
      {
        If (config.PAC != "" And InStr(outputPAC, config.PAC))
        {
          enabledProxy := name . " (PAC)"
          If (trayEntries[name].globalMenu != "")
            _EnableProxyMenu(trayEntries[name].PACMenu, trayEntries[name].globalMenu, config.PAC)
          Else
            _EnableProxyMenu(trayEntries[name].PACMenu, trayEntries[name].PACMenu, config.PAC)
          Goto L_END_CHECKPROXY
        }
      }
    }
    RegDelete, % RegRootKey, % RegSubKey, AutoConfigURL
  }

  L_END_CHECKPROXY:

  If Not enabledProxy
    Menu, Tray, Check, % trayEntries["Disable"]

  If enabledProxy
    info := "Enabled: " enabledProxy "`n`n"
  Else
    info := "No Proxy Enabled`n`n"
  If Not outputPAC
    outputPAC := "(null)"
  If Not outputGlobal
    outputGlobal := "(null)"
  
  info .= "AutoConfigURL: " outputPAC "`n"
  info .= "ProxyEnable: " outputEnable "`n"
  info .= "ProxyServer: " outputGlobal "`n"
  proxyInfo := info

  Return [enabledProxy, outputPAC, outputEnable, outputGlobal]
}

_CheckProxy()

SetTimer, _CheckConditionChange, 10000
SetTimer, _CheckProxy, 5000

; popup menu
#Include utils.ahk
keybindingConfigs := LoadKeybindings("config\keybindings.json")
Bind(keybindingConfigs.hotkeys.global["showProxyMenu"], "showProxyMenu")
showProxyMenu() {
  Menu, Tray, Show
}
