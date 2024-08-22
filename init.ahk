; AutoHotKey v1.1.33.20

; ----------------------------------------
;             global settings
; ----------------------------------------

#SingleInstance force
#NoEnv
Process, Priority, , High
SetWorkingDir, %A_ScriptDir%
Send, {Alt Up}{Ctrl Up}{Shift Up}{LWin Up}{RWin Up}
SetWinDelay, 0
Menu, Tray, Tip, HotKeys
FileEncoding, UTF-8


; ----------------------------------------
;             global variables
; ----------------------------------------
#Include JSON.ahk
#Include utils.ahk
appJsonObj := JSON.Load(FileOpen("config\application.json", "r").Read())
miscJsonObj := JSON.Load(FileOpen("config\misc.json", "r").Read())
keybindingConfigs := LoadKeybindings("config\keybindings.json")


; ----------------------------------------
;            elevated to admin
; ----------------------------------------
; If the script is not elevated, relaunch as administrator and kill current instance:

full_command_line := DllCall("GetCommandLine", "str")

If Not (A_IsAdmin Or RegExMatch(full_command_line, " /restart(?!\S)"))
{
  Try ; leads to having the script re-launching itself as administrator
  {
    If A_IsCompiled
      Run *RunAs "%A_ScriptFullPath%" /restart
    Else
      Run *RunAs "%A_AhkPath%" /restart "%A_ScriptFullPath%"
  }
  ExitApp
}

; back to non-admin
Run_AsUser(Program) {
  ComObjCreate("Shell.Application")
  .Windows.FindWindowSW(0, 0, 0x08, 0, 0x01)
  .Document.Application.ShellExecute(Program)
}


; ----------------------------------------
;          auto-reload on change
; ----------------------------------------

#Include WatchFolder.ahk
WatchFolder(A_ScriptDir, "_ReloadHelper", False, 16)
_ReloadHelper(dir, changes) {
  Static relatedFiles := ["init.ahk", "utils.ahk", "WatchFolder.ahk", "JSON.ahk"]
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


; ----------------------------------------
;         detect clipboard change
; ----------------------------------------

OnClipboardChange("ClipChanged")

ClipChanged(Type)
{
  filterWebsiteAddedSuffix(Type)
}

filterWebsiteAddedSuffix(Type) {
  Global miscJsonObj
  If (Type == 1)
  {
    filterPattern := miscJsonObj.clipboardFilter
    For i, pattern In filterPattern
    {
      If RegExMatch(Clipboard, pattern, match)
      {
        Clipboard := match
        Break
      }
    }
  }
}


; ----------------------------------------
;             remap modifiers
; ----------------------------------------
RegistryRemapModifiers(keybindingConfigs.remap)


; ----------------------------------------
;          hotkeys for autohotkey
; ----------------------------------------

Bind(keybindingConfigs.hotkeys.global["reloadHotkeys"], "ReloadHotkeys")
ReloadHotkeys() ; reload this file
{
  Suspend, Permit
  Reload
  Sleep 1000
  MsgBox, 4,, "The script could not be reloaded. Would you like to open it for editing"?
  Ifmsgbox, yes, edit
}

Bind(keybindingConfigs.hotkeys.global["toggleHotkeys"], "ToggleHotkeys")
ToggleHotkeys() ; suspend / resume hotkeys
{
  Suspend
}

Bind(keybindingConfigs.hotkeys.global["showCurrentWindowInfo"], "ShowCurrentWindowInfo")
ShowCurrentWindowInfo() ; get attribute of focused window
{
  WinGet, proc, ProcessName, A
  WinGetClass, class_, A
  WinGetTitle, title, A
  WinGetText, text_, A
  MsgBox, process: %proc%`nwindow class: %class_%`nwindow title: %title%`nwindow text: %text_%
}


; ----------------------------------------
;        hotkeys for launching apps
; ----------------------------------------

Class _AppKey {
  __New(app, spec) {
    this.app := app
    this.spec := spec
  }

  __Call() {
    If (this.spec.launch != 1)
      _ActivateOrMinimize(this.app, this.spec.admin)
    Else
      _Launch(this.app, this.spec.admin)
  }
}

For app, spec in keybindingConfigs.hotkeys.appkeys
{
  If spec.mods != ""
    Bind(spec, New _AppKey(app, spec))
  Else
    For _, entry in spec
      Bind(entry, New _AppKey(app, entry))
}

Bind(keybindingConfigs.hotkeys.global["toggleTaskbarOrMyDock"], "ToggleTaskbarOrMyDock")

_ShowOrMinimize(app)
{
  Global appJsonObj

  procStem := appJsonObj[app].process
  If (procStem == "")
    procStem := app

  ; `ApplicationFrameHost.exe` relates to many UWP apps running at the same time
  If (procStem == "ApplicationFrameHost")
    Return _ProcessUWP(appJsonObj[app].title)

  If IsObject(procStem)
  {
    For _, proc in procStem
    {
      ret := _ShowOrMinimizeSingleProc(procStem)
      If (ret != -1)
        Return ret
    }
    Return -1
  }
  Else
    Return _ShowOrMinimizeSingleProc(procStem)
}

_ShowOrMinimizeSingleProc(procStem)
{
  Global appJsonObj

  WinGet, A_proc, ProcessName, A
  proc := procStem . ".exe"

  ; `explorer.exe` exists all the time with two useless windows
  If (proc = "explorer.exe")
    Return _ProcessExplorer(A_proc)

  ; minimize if active
  If (A_proc = proc)
  {
    WinGet, winList, List, ahk_exe %proc%
    Loop, %winList%
    {
      winHWD := winList%A_Index%
      WinMinimize, ahk_id %winHWD%
    }
    Return 0
  }

  ; specify whether to detect hidden windows
  winHidden := appJsonObj[app].hidden
  If (winHidden == 1)
    DetectHiddenWindows, On

  ; find all windows belonging to process %proc%
  winTitle := appJsonObj[app].title
  If Not winTitle == ""
  {
    winTitleMode := appJsonObj[app].title_mode
    If Not winTitleMode == ""
    {
      old_title_mode = %A_TitleMatchMode%
      SetTitleMatchMode, %winTitleMode%
    }
    WinGet, winList, List, %winTitle%
    If Not winTitleMode == ""
      SetTitleMatchMode, %old_title_mode%
  }
  Else
  {
    winClass := appJsonObj[app].class
    If Not winClass == ""
    {
      WinGet, winList, List, %winClass%
    }
    Else
    {
      WinGet, winList, List, ahk_exe %proc%
    }
  }

  ; restore detection mode
  If (winHidden == 1)
    DetectHiddenWindows, Off

  ; if any, activate them
  appWinState := -1
  Loop, %winList%
  {
    winHWD := winList%A_Index%
    WinShow, ahk_id %winHWD%
    WinActivate, ahk_id %winHWD%
    appWinState := 1
  }

  Return appWinState
}

_IsIgnoredExplorerWindow(WinTitle)
{
  WinGetClass, class, %WinTitle%
  WinGetTitle, title, %WinTitle%
  Return (class == "Shell_TrayWnd" And title == "") `
      Or (class == "WorkerW" And title == "") `
      Or (class == "Progman" And title == "Program Manager")
}

_ProcessExplorer(A_proc := "")
{
  If (A_proc == "")
    WinGet, A_proc, ProcessName, A

  onlyDesktopWindow := True
  WinGet, winList, List, ahk_exe explorer.exe
  Loop, %winList%
  {
    winHWD := winList%A_Index%
    If _IsIgnoredExplorerWindow("ahk_id " winHWD)
      Continue
    Else
      onlyDesktopWindow = False
  }

  If (onlyDesktopWindow == True)
    Return -1

  If (A_proc = "explorer.exe" And Not _IsIgnoredExplorerWindow("A"))
  {
    Loop, %winList%
    {
      winHWD := winList%A_Index%
      If _IsIgnoredExplorerWindow("ahk_id " winList%A_Index%)
        Continue
      WinMinimize, ahk_id %winHWD%
    }
    Return 0
  }
  Else
  {
    Loop, %winList%
    {
      winHWD := winList%A_Index%
      If _IsIgnoredExplorerWindow("ahk_id " winList%A_Index%)
        Continue
      WinShow, ahk_id %winHWD%
      WinActivate, ahk_id %winHWD%
    }
    Return 1
  }
}

_ProcessUWP(title, A_proc := "")
{
  If (A_proc == "")
    WinGet, A_proc, ProcessName, A

  WinGet, winList, List, ahk_exe ApplicationFrameHost.exe
  If (A_proc = "ApplicationFrameHost.exe")
  {
    WinGetTitle, A_title, A
    If (A_title == title)
    {
      Loop, %winList%
      {
        winHWD := winList%A_Index%
        WinGetTitle, winTitle, ahk_id %winHWD%
        If (winTitle == title)
          WinMinimize, ahk_id %winHWD%
      }
      Return 0
    }
  }

  appWinState := -1
  Loop, %winList%
  {
    winHWD := winList%A_Index%
    WinGetTitle, winTitle, ahk_id %winHWD%
    If (winTitle == title)
    {
      WinShow, ahk_id %winHWD%
      WinActivate, ahk_id %winHWD%
      appWinState := 1
    }
  }
  Return appWinState
}

_GetLnkFullPath(dir, pattern, ext := ".lnk")
{
  If Not IsObject(pattern)
  {
    link := dir "\" pattern . ext
    If Not (InStr(pattern, "*") Or InStr(pattern, "?")) And FileExist(link)
      Return link
    If InStr(pattern, "*") Or InStr(pattern, "?") Or Not Instr(pattern, "\")
    {
      Loop, Files, %dir%\%pattern%%ext%, R
        Return %A_LoopFileFullPath%
    }
  }
  Else
  {
    For _, pt In pattern
    {
      link := dir "\" pt . ext
      If Not (InStr(pt, "*") Or InStr(pt, "?")) And FileExist(link)
        Return link
      If InStr(pt, "*") Or InStr(pt, "?") Or Not Instr(pt, "\")
      {
        Loop, Files, %dir%\%pt%%ext%, R
          Return %A_LoopFileFullPath%
      }
    }
  }
}

_Launch(app, admin := False)
{
  Global appJsonObj
  cmd_run := ""

  If appJsonObj[app].run            ; shortcut or absolute path
    cmd_run := appJsonObj[app].run
  Else If appJsonObj[app].url       ; url
    cmd_run := appJsonObj[app].url
  Else                              ; relative path of a link in start menu
  {
    appLnkSearchDirs := [
    (Join
      A_Programs,
      A_Programs "\JetBrains Toolbox",
      A_Programs "\Scoop Apps",
      A_ProgramsCommon
    )]
    appLnkSearchDir_Parallels := A_Programs "\Parallels Shared Applications"

    For _, dir In appLnkSearchDirs
    {
      link := _GetLnkFullPath(dir, appJsonObj[app].link)
      If (link != "")
      {
        cmd_run := link
        Goto L_Launch
      }
    }
    If FileExist(appLnkSearchDir_Parallels)
    {
      lnk_suffix := " (Mac).lnk"
      If appJsonObj[app].parallels.alternative_preferred And appJsonObj[app].parallels.alternative != ""
      {
        link := _GetLnkFullPath(appLnkSearchDir_Parallels, appJsonObj[app].parallels.alternative, lnk_suffix)
        If (link != "")
        {
          cmd_run := link
          Goto L_Launch
        }
      }
      If appJsonObj[app].parallels.link != ""
      {
        link := _GetLnkFullPath(appLnkSearchDir_Parallels, appJsonObj[app].parallels.link, lnk_suffix)
        If (link != "")
        {
          cmd_run := link
          Goto L_Launch
        }
      }
      If appJsonObj[app].parallels.alternative != "" And Not appJsonObj[app].parallels.alternative_preferred
      {
        link := _GetLnkFullPath(appLnkSearchDir_Parallels, appJsonObj[app].parallels.alternative, lnk_suffix)
        If (link != "")
        {
          cmd_run := link
          Goto L_Launch
        }
      }
      If Not IsObject(appJsonObj[app].link)
      {
        If InStr(appJsonObj[app].link, "\")
          pattern := StrSplit(appJsonObj[app].link, "\").Pop()
        Else
          pattern := appJsonObj[app].link
      }
      Else
      {
        pattern := Array()
        For _, link In appJsonObj[app].link
        {
          If InStr(link, "\")
            pattern.Push(StrSplit(link, "\").Pop())
          Else
            pattern.Push(link)
        }
      }
      link := _GetLnkFullPath(appLnkSearchDir_Parallels, pattern, lnk_suffix)
      If (link != "")
      {
        cmd_run := link
        Goto L_Launch
      }
    }
  }

  If Not cmd_run
    Return 1

L_Launch:
  If (admin)
    Run % cmd_run
  Else
    Run_AsUser(cmd_run)
  WinActivate
  Return 0
}

; launch (if not launched), focus (if not focused) or minimize (if focused)
_ActivateOrMinimize(app, admin := False)
{
  If _ShowOrMinimize(app) == -1
    _Launch(app, admin)
}

_IsActive(app)
{
  Global appJsonObj

  procStem := appJsonObj[app].process
  If (procStem == "")
    procStem := app

  ; `ApplicationFrameHost.exe` relates to many UWP apps running at the same time
  If (procStem == "ApplicationFrameHost")
    Return _IsActive_UWP(appJsonObj[app].title)

  If IsObject(procStem)
  {
    For _, proc in procStem
    {
      If _IsActiveSingleProc(proc)
        Return True
    }
    Return False
  }
  Else
    Return _IsActiveSingleProc(procStem)
}

_IsActiveSingleProc(procStem)
{
  proc := procStem . ".exe"

  ; `explorer.exe` exists all the time with two useless windows
  If (proc = "explorer.exe")
    Return _IsActive_Explorer()

  WinGet, A_proc, ProcessName, A
  If Instr(proc, "*")
  {
    If RegExMatch(A_proc, proc)
      Return True
    Else
      Return False
  }
  Else
    Return A_proc = proc
}

_IsActive_Explorer()
{
  WinGet, A_proc, ProcessName, A
  If (A_proc != "explorer.exe")
    Return False

  WinGet, winList, List, ahk_exe explorer.exe
  Loop, %winList%
  {
    winHWD := winList%A_Index%
    If _IsIgnoredExplorerWindow("ahk_id " winList%A_Index%)
      Continue
    Else
      Return True
  }
  Return False
}

_IsActive_UWP(title)
{
  WinGet, A_proc, ProcessName, A
  If (A_proc != "ApplicationFrameHost.exe")
    Return False

  WinGetTitle, A_title, A
  Return A_title == title
}

_IsRunning(app)
{
  Global appJsonObj

  procStem := appJsonObj[app].process
  If (procStem == "")
    procStem := app
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

ToggleTaskbarOrMyDock()
{
  Static A_WinID := ""

  If Not _IsRunning("mydockfinder")
  {
    If Not WinActive("ahk_class Shell_TrayWnd")
    {
      A_WinID := WinExist("A")
      WinShow, ahk_class Shell_TrayWnd
      WinActivate, ahk_class Shell_TrayWnd
    }
    Else
    {
      If A_WinID
      {
        WinActivate, ahk_id %A_WinID%
        A_WinID := ""
      }
    }
  }
  Else
    Send !{z}
}


; ----------------------------------------
;             hotkeys in apps
; ----------------------------------------

; global hotkeys
quitAppHK := keybindingConfigs.hotkeys.appCommon["quitApp"]
closeWindowHK := keybindingConfigs.hotkeys.appCommon["closeWindow"]
closeAllHK := keybindingConfigs.hotkeys.appCommon["closeAll"]

; quit
Bind(quitAppHK, "HoldToQuit")

HoldToQuit()
{
  Global quitAppHK

  If _IsActive("explorer")
    delay := 2
  Else
    delay := 0.2
  start := A_TickCount
  KeyWait, % quitAppHK.key, T%delay%
  If (A_TickCount - start < delay * 1000) {
    delayInDecimal := Format("{:0.1f}", delay)
    hk := quitAppHK.mods . quitAppHK.key
    ToolTip, Press %hk% for %delayInDecimal% seconds to quit
    Sleep 1500
    ToolTip
  } Else {
    WinGet, pid, PID, A
    Process, Close, %pid%
  }
}

Hotkey, IfWinActive, QQ ahk_exe QQ.exe
  Bind(closeWindowHK, "MinimizeWindow")
Hotkey, IfWinActive,

; close window with only one tab
#If OneTabWindow()
#If
Hotkey, If, OneTabWindow()
  Bind(closeWindowHK, "CloseWindow")
Hotkey, If,

OneTabWindow()
{
  Return Not (_IsActive("explorer") `
     Or _IsActive("edge") `
     Or _IsActive("google-chrome") `
     Or _IsActive("sublime-text") `
     Or _IsActive("vscode") `
     Or _IsActive("terminal") `
     Or _IsActive("termius") `
     Or _IsActive("clion") `
     Or _IsActive("idea") `
     Or _IsActive("pycharm") `
     Or _IsActive("wps-office") `
     Or _IsActive("powerpoint") `
     Or _IsActive("updf") `
     Or _IsActive("typora") `
     Or _IsActive("vs") `
     Or _IsActive("matlab") `
     Or _IsActive("notepad") `
     Or _IsActive("word") `
     Or _IsActive("excel") `
     Or _IsActive("gimp") `
     Or _IsActive("spyxx") `
     Or _IsActive("foxwq") `
     Or _IsActive("qqgame"))
}

; force close window
Bind(closeAllHK, "CloseWindow")

CloseWindow()
{
  WinClose, A
}

; previous/next tab
#If Not _IsActive("vscode")
#If

Hotkey, If, Not _IsActive("vscode")
  Remap(keybindingConfigs.hotkeys.appCommon["previousTab"], "^+{Tab}")
  Remap(keybindingConfigs.hotkeys.appCommon["nextTab"], "^{Tab}")
Hotkey, If,


; app-specific hotkeys

; in UWP apps
config := keybindingConfigs.hotkeys.UWP
Hotkey, IfWinActive, ahk_exe ApplicationFrameHost.exe
  Bind(quitAppHK, "HoldToQuitUWP") ; quit
  Remap(config["back"], "!{Left}")          ; back
Hotkey, IfWinActive,

HoldToQuitUWP()
{
  Global quitAppHK

  delay := 0.2
  start := A_TickCount
  KeyWait, % quitAppHK.key, T%delay%
  If (A_TickCount - start < delay * 1000) {
    delayInDecimal := Format("{:0.1f}", delay)
    hk := quitAppHK.mods . quitAppHK.key
    ToolTip, Press %hk% for %delayInDecimal% seconds to quit
    Sleep 1500
    ToolTip
  } Else {
    WinClose, A
  }
}
       
; in spyxx
config := keybindingConfigs.hotkeys["spyxx"]
#If _IsActive("spyxx")
#If
Hotkey, If, _IsActive("spyxx")
  Remap(closeWindowHK, "!{w}{c}")
  Remap(closeAllHK, "!{w}{l}")
  Remap(config["showInfo"], "!{Enter}")
  Remap("#w", "^{w}")
  Remap("#p", "^{p}")
  Remap("#t", "^{t}")
  Remap("#m", "!{s}{m}")
Hotkey, If,

; in edge
config := keybindingConfigs.hotkeys["edge"]

#If _IsActive("edge")
#If

Hotkey, If, _IsActive("edge")
  Remap(config["back"], "!{Left}")                          ; back
  Remap(config["forward"], "!{Right}")                      ; forward
  Remap(config["showHistory"], "^{h}")                      ; history
  Remap(config["showDownloads"], "^{j}")                    ; downloads
  Remap(config["settings"], "{Alt Down}e{Alt Up}g{Enter}")  ; settings
Hotkey, If,

; in chrome
config := keybindingConfigs.hotkeys["google-chrome"]

#If _IsActive("google-chrome")
#If

Hotkey, If, _IsActive("google-chrome")
  Remap(config["back"], "!{Left}")                          ; back
  Remap(config["forward"], "!{Right}")                      ; forward
  Remap(config["showHistory"], "^{h}")                      ; history
  Remap(config["showDownloads"], "^{j}")                    ; downloads
  Remap(config["settings"], "{Alt Down}e{Alt Up}g{Enter}")  ; settings
Hotkey, If,

; in explorer
config := keybindingConfigs.hotkeys["explorer"]

_IsExplorerLike()
{
  Return _IsActive("explorer") || WinActive("ahk_class #32770", "命名空间树状控制项")
}
#If _IsExplorerLike()
#If

Hotkey, If, _IsExplorerLike()
  Remap(config["ShowInfo"], "!{Enter}")                   ; Cmd+i: Get Info / Properties
  Remap(config["refresh"], "{F5}")                        ; Cmd+R: Refresh view (Not actually a Finder shortcut? But works in Linux file browsers too.)
  Remap(config["openParentFolder"], "{CtrlUp}!{Up}")      ; Cmd+Up: Up to parent folder
  Remap(config["openSelectedFolder"], "{CtrlUp}{Enter}")  ; Cmd-Down: Navigate into the selected directory
  Remap(config["back"], "!{Left}")                        ; Cmd+Left_Brace: Go to prior location in history
  Remap(config["forward"], "!{Right}")                    ; Cmd+Right_Brace: Go to next location in history
  Bind(config["toggleDisplayHiddenFiles"], "ExplorerToggleDisplayHiddenFiles")  ; toggle hidden files display
  Bind(config["copyPath"], "ExplorerCopyPath")            ; Copy file path

  Remap("^Delete", "{Delete}")                            ; Cmd+Delete: Delete / Send to Trash
  Remap("^BackSpace", "{Delete}")                         ; Cmd+Delete: Delete / Send to Trash
  Remap("^d", "")                                         ; Block the unusual Explorer "delete" shortcut of Ctrl+D, used for "bookmark" in similar apps
  Bind("$Enter", "ExplorerRename")                        ; Use Enter key to rename (F2), unless focus is inside a text input field. 
  Bind("$BackSpace", "ExplorerBackSpace")                 ; Backspace (without Cmd): Block Backspace key with error beep, unless inside text input field
  Bind("$Delete", "ExplorerDelete")                       ; Delete (without Cmd): Block Delete key with error beep, unless inside text input field
Hotkey, If,

ExplorerRename()
{
  ControlGetFocus, fc, A
  If fc contains Edit,Search,Notify,Windows.UI.Core.CoreWindow1,SysTreeView321
    Send {Enter}
  Else Send {F2}
}

ExplorerBackSpace()
{
  ControlGetFocus, fc, A
  If fc contains Edit,Search,Notify,Windows.UI.Core.CoreWindow1
    Send {BackSpace}
  Else SoundPlay, *16
}

ExplorerDelete()
{
  ControlGetFocus, fc, A
  If fc contains Edit,Search,Notify,Windows.UI.Core.CoreWindow1
    Send {Delete}
  Else SoundPlay, *16
}

ExplorerToggleDisplayHiddenFiles()
{
  ID := WinExist("A")
  RootKey = HKEY_CURRENT_USER
  SubKey  = Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced

  RegRead, HiddenFiles_Status, % RootKey, % SubKey, Hidden

  If HiddenFiles_Status = 2
    RegWrite, REG_DWORD, % RootKey, % SubKey, Hidden, 1
  Else
    RegWrite, REG_DWORD, % RootKey, % SubKey, Hidden, 2
  Sleep 100
  PostMessage, 0x111, 41504,,, ahk_id %ID%
}

ExplorerCopyPath()
{
  Send ^c
  Sleep 200
  Clipboard = %Clipboard%
  Tooltip, %Clipboard%
  Sleep 500
  Tooltip
}

; in notepad
config := keybindingConfigs.hotkeys["notepad"]

#If _IsActive("notepad")
#If
Hotkey, If, _IsActive("notepad")
  Remap(config["newTab"], "^{n}")
  Remap(config["newWindow"], "+^{n}")
Hotkey, If,

; in sublime text
config := keybindingConfigs.hotkeys["sublime-text"]

#If _IsActive("sublime-text")
#If
Hotkey, If, _IsActive("sublime-text")
  Remap(config["openRecent"], "!{f}{r}")
Hotkey, If,

#If _IsActive("wps-office") || _IsActive("word")
#If
Hotkey, If, _IsActive("wps-office") || _IsActive("word")
  Remap("!Left", "^{Left}")
  Remap("!Right", "^{Right}")
  Remap("!+Left", "^+{Left}")
  Remap("!+Right", "^+{Right}")
  Remap("^Left", "{Home}")
  Remap("^Right", "{End}")
  Remap("^+Left", "+{Home}")
  Remap("^+Right", "+{End}")
  Remap("Home", "^{Home}")
  Remap("End", "^{End}")
  Remap("+Home", "^+{Home}")
  Remap("+End", "^+{End}")
  Remap("^Home", "")
  Remap("^End", "")
  Remap("^+Home", "")
  Remap("^+End", "")
Hotkey, If,

_IsWindowsShell()
{
  If WinActive("ahk_exe powershell.exe") `
    Or WinActive("ahk_exe PowerShell_ISE.exe") `
    Or WinActive("ahk_exe pwsh.exe") `
    Or WinActive("ahk_exe cmd.exe")
    Return True
  If _IsActive("terminal")
  {
    titleMatchModeBuffer := A_TitleMatchMode
    SetTitleMatchMode, 2
    If WinActive("PowerShell") `
      Or WinActive("Command Prompt") `
      Or WinActive("命令提示符")
    {
      SetTitleMatchMode, %titleMatchModeBuffer%
      Return True
    }
    SetTitleMatchMode, %titleMatchModeBuffer%
  }
  If _IsActive("termius") `
    And WinActive("Termius - Local Terminal")
    Return True
  Return False
}

_IsPosixShell()
{
  If WinActive("ahk_exe bash.exe") `
    Or WinActive("ahk_exe mintty.exe") `
    Or WinActive("ahk_exe ubuntu.exe") `
    Or WinActive("ahk_exe ubuntu1804.exe") `
    Or WinActive("ahk_exe ubuntu2004.exe") `
    Or WinActive("ahk_exe ubuntu2204.exe") `
    Return True
  If _IsActive("terminal")
  {
    titleMatchModeBuffer := A_TitleMatchMode
    SetTitleMatchMode, 2
    If Not (WinActive("PowerShell") `
      Or WinActive("Command Prompt") `
      Or WinActive("命令提示符"))
    {
      SetTitleMatchMode, %titleMatchModeBuffer%
      Return True
    }
    SetTitleMatchMode, %titleMatchModeBuffer%
  }
  If _IsActive("termius") `
    And Not WinActive("Termius - Local Terminal")
    Return True
  Return False
}

#If WinActive("ahk_exe powershell.exe") `
    || WinActive("ahk_exe pwsh.exe") `
    || WinActive("ahk_exe cmd.exe") `
    || WinActive("ahk_exe mintty.exe")
#If
Hotkey, If, WinActive("ahk_exe powershell.exe") `
    || WinActive("ahk_exe pwsh.exe") `
    || WinActive("ahk_exe cmd.exe") `
    || WinActive("ahk_exe mintty.exe")
  Remap("^c", "^{Insert}")
  Remap("^v", "+{Insert}")
Hotkey, If,

; in windows terminal
#If _IsActive("terminal")
#If
#If _IsActive("terminal") && Not _IsTmuxShell()
#If
Hotkey, If, _IsActive("terminal")
  Remap("^a", "+^{a}")
  Remap("^c", "^{Insert}")
  Remap("^v", "+{Insert}")
  Remap("^k", "+^{k}")
Hotkey, If,

Hotkey, If, _IsActive("terminal") && Not _IsTmuxShell()
  Remap("^f", "+^{f}")
  Remap("^n", "+^{n}")
  Remap("^t", "+^{t}")
  Bind("^w", "SafeClose")
Hotkey, If,

; in termius
#If _IsActive("termius")
#If
#If _IsActive("termius") && Not _IsTmuxShell()
#If
Hotkey, If, _IsActive("termius")
  Remap("^a", "+^{a}")
  Remap("^c", "+^{c}")
  Remap("^v", "+^{v}")
  Remap("+^Tab", "!{Left}")
  Remap("^Tab", "!{Right}")
  Remap("+^[", "!{Left}")
  Remap("+^]", "!{Right}")
Hotkey, If,

Hotkey, If, _IsActive("termius") && Not _IsTmuxShell()
  Remap("^f", "+^{f}")
  Bind("^w", "SafeClose")
Hotkey, If,

SafeClose()
{
  Hotkey, +^w, Off
  Send +^{w}
  Hotkey, +^w, On
}

; in PowerShell or Command Prompt
#If _IsWindowsShell()
#If
Hotkey, If, _IsWindowsShell()
  Remap("#c", "^{c}")
  Remap("#n", "{Down}")
  Remap("#p", "{Up}")
  Remap("#f", "{Right}")
  Remap("#b", "{Left}")
  Remap("#a", "{Home}")
  Remap("#e", "{End}")
  Remap("#w", "^{BackSpace}")
  Remap("!d", "^{Delete}")
  Remap("#d", "{Delete}")
  Remap("#u", "^{Home}")
  Remap("#k", "^{End}")
  Remap("!BackSpace", "^{BackSpace}")
  Remap("!Delete", "^{Delete}")
  Remap("^BackSpace", "{Delete}")
  Bind("Escape", "InvalidHotKeySound")
  Remap("!Left", "^{Left}")
  Remap("!Right", "^{Right}")
  Bind("^Left", "InvalidHotKeySound")
  Bind("^Right", "InvalidHotKeySound")
Hotkey, If,

; fixme: check whether integrated powershell or cmd is focused in vscode
#If _IsActive("vscode")
#If
Hotkey, If, _IsActive("vscode")
  Remap("#c", "^{c}")
  Remap("#n", "{Down}")
  Remap("#p", "{Up}")
  Remap("#f", "{Right}")
  Remap("#b", "{Left}")
  Remap("#a", "{Home}")
  Remap("#e", "{End}")
  Remap("#w", "^{BackSpace}")
  Remap("!d", "^{Delete}")
  Remap("#d", "{Delete}")
  ; remove conflicted vscode system shortcuts
  Remap("#u", "^{Home}")
  Remap("#k", "^{End}")
Hotkey, If,

; in posix shell
#If _IsPosixShell()
#If
Hotkey, If, _IsPosixShell()
  Remap("#c", "^{c}")
  Remap("#n", "^{n}")
  Remap("#p", "^{p}")
  Remap("#f", "^{f}")
  Remap("#b", "^{b}")
  Remap("#a", "^{a}")
  Remap("#e", "^{e}")
  Remap("#w", "^{w}")
  Remap("#d", "^{d}")
  Remap("#u", "^{u}")
  Remap("#k", "^{k}")
  Remap("!Left", "^{Left}")
  Remap("!Right", "^{Right}")
  Bind("^Left", "InvalidHotKeySound")
  Bind("^Right", "InvalidHotKeySound")
Hotkey, If,

InvalidHotKeySound()
{
  SoundPlay, *16
}

_IsTmuxShell()
{
  old_title_mode = %A_TitleMatchMode%
  SetTitleMatchMode, 2
  ret := WinActive("tmux")
  SetTitleMatchMode, %old_title_mode%
  Return ret
}

#If _IsTmuxShell()
#If
Hotkey, If, _IsTmuxShell()
  Remap("^+[", "^bo")
  Remap("^+]", "^b;")
  Remap("^+Up", "^b{Up}")
  Remap("^+Down", "^b{Down}")
  Remap("^+Left", "^b{Left}")
  Remap("^+Right", "^b{Right}")
  Remap("^t", "^b%")
  Remap("^+t", "^b""")
  Remap("^w", "^bx")
  Remap("!^``", "^bp")
  Remap("!^+``", "^bn")
  Remap("^1", "^b1")
  Remap("^2", "^b2")
  Remap("^3", "^b3")
  Remap("^4", "^b4")
  Remap("^5", "^b5")
  Remap("^6", "^b6")
  Remap("^7", "^b7")
  Remap("^8", "^b8")
  Remap("^9", "^b9")
  Remap("^+n", "^bc")
  Remap("^+w", "^b&")
  Remap("^d", "^bd")
  Remap("^b", "^b[")
  Remap("^f", "^b[^s")  ; emacs mode
Hotkey, If,

; in foxwq
config := keybindingConfigs.hotkeys["foxwq"]

#If _IsActive("foxwq") && WinActive("> [高级房1] >")
#If
Hotkey, If, _IsActive("foxwq") && WinActive("> [高级房1] >")
  Bind(config["backToHome"], "BackToHome")
  Bind(closeWindowHK, "ExitRoom")
Hotkey, If,

#If _IsActive("foxwq") && WinActive("> [高级房1]")
#If
Hotkey, If, _IsActive("foxwq") && WinActive("> [高级房1]")
  Bind(config["1stRoom"], "FirstRoom")
  Bind(config["2ndRoom"], "SecondRoom")
  Bind(config["3rdRoom"], "ThirdRoom")
  Bind(config["4thRoom"], "ForthRoom")
  Bind(config["5thRoom"], "FifthRoom")
  Bind(config["6thRoom"], "SixthRoom")
Hotkey, If,

#If _IsActive("foxwq") && Not WinActive("> [高级房1]")
#If
Hotkey, If, _IsActive("foxwq") && Not WinActive("> [高级房1]")
  Bind(closeWindowHK, "CloseWindow")
Hotkey, If,

BackToHome()
{
  WinGetPos, winX, winY, winW, WinH, A
  MouseClick, Left, 100, winH - 40
}
ExitRoom()
{
  WinGetPos, winX, winY, winW, WinH, A
  MouseClick, Left, winW - 150, winH - 100
}
FirstRoom()
{
  WinGetPos, winX, winY, winW, WinH, A
  MouseClick, Left, 220, winH - 40
}
SecondRoom()
{
  WinGetPos, winX, winY, winW, WinH, A
  MouseClick, Left, 420, winH - 40
}
ThirdRoom()
{
  WinGetPos, winX, winY, winW, WinH, A
  MouseClick, Left, 620, winH - 40
}
ForthRoom()
{
  WinGetPos, winX, winY, winW, WinH, A
  MouseClick, Left, 820, winH - 40
}
FifthRoom()
{
  WinGetPos, winX, winY, winW, WinH, A
  MouseClick, Left, 1020, winH - 40
}
SixthRoom()
{
  WinGetPos, winX, winY, winW, WinH, A
  MouseClick, Left, 1220, winH - 40
}

; in qqgame
#If _IsActive("qqgame")
#If
Hotkey, If, _IsActive("qqgame")
  Bind(closeWindowHK, "QQGameExitLastRoomOrQuitGame")
Hotkey, If,

QQGameExitLastRoomOrQuitGame()
{
  If (cnt := _GetNumberOfTabs()) > 1
  {
    x := 522 + (cnt - 2) * 274
    MouseClick, Left, %x%, 222
  }
  Else
    WinClose, A
}

_GetNumberOfTabs()
{
  WinGetText, Text, A
  Return (StrSplit(Text, "`n").MaxIndex() - 1) / 2 - 1
}

Class QQGameSitDown
{
  __New(x)
  {
    this.x := x
  }

  __Call()
  {
    MouseClick, Left, this.x, 300
  }
}

; in qqgame - 掼蛋
config := keybindingConfigs.hotkeys["qqgame:hapdk"]
#If _IsActive("qqgame") && WinActive("掼蛋(淮安跑得快)")
#If
Hotkey, If, _IsActive("qqgame") && WinActive("掼蛋(淮安跑得快)")
  Bind(config["sitDownAndShowPartnerInfo"], "HAPDKSitDownAndShowPartenerInfo")
Hotkey, If,

#If _IsActive("qqgame:hapdk")
#If
Hotkey, If, _IsActive("qqgame:hapdk")
  Bind(config["sitDownAndShowPartnerInfo"], "HAPDKShowPartnerInfo")
  Bind(config["kickOutPartner"], "HAPDKKickOutPartner")
  Bind(config["start"], "HAPDKStart")
  Bind(config["pass"], "HAPDKPass")
  Bind(config["play"], "HAPDKPlay")
  Bind(config["tip"], "HAPDKTip")
  Bind(config["lastRound"], "HAPDKLastRound")
Hotkey, If,

HAPDKSitDownAndShowPartenerInfo()
{
  MouseClick, Left, 1030, 300
  Sleep 1000
  If Not _IsActive("qqgame:hapdk")
    _ShowOrMinimize("qqgame:hapdk")
  If _IsActive("qqgame:hapdk")
    MouseClick, Right, 800, 400
}

HAPDKShowPartnerInfo()
{
  MouseClick, Right, 800, 400
}

HAPDKKickOutPartner()
{
  MouseClick, Right, 800, 400
  Sleep, 500
  MouseClick, Left, 800 + 5, 400 + 150
}

HAPDKStart()
{
  Send {Enter}
  MouseClick, Left, 840, 1300
}

HAPDKPass()
{
  MouseClick, Left, 615, 1130
}

HAPDKPlay()
{
  MouseClick, Left, 808, 1130
}

HAPDKTip()
{
  MouseClick, Left, 1000, 1130
}

HAPDKLastRound()
{
  MouseClick, Left, 1485, 1328
}

; in qqgame - 飞行棋
config := keybindingConfigs.hotkeys["qqgame:fxq"]
#If _IsActive("qqgame") && WinActive("飞行棋")
#If
Hotkey, If, _IsActive("qqgame") && WinActive("飞行棋")
  Bind(config["sitDown"], New QQGameSitDown(540))
Hotkey, If,

; in qqgame - 斗地主
config := keybindingConfigs.hotkeys["qqgame:ddzrpg"]
#If _IsActive("qqgame") && WinActive("斗地主")
#If
Hotkey, If, _IsActive("qqgame") && WinActive("斗地主")
  Bind(config["sitDown"], New QQGameSitDown(680))
Hotkey, If,

; in klatexformula
config := keybindingConfigs.hotkeys["klatexformula"]

#If _IsActive("klatexformula")
#If
Hotkey, If, _IsActive("klatexformula")
  Remap(config["render"], "{Tab}{Tab}{Enter}")
Hotkey, If,

#If _IsRunning("klatexformula")
#If
Hotkey, If, _IsRunning("klatexformula")
  Bind(config["renderClipboardInKlatexformula"], "RenderClipboardInKlatexformula")
Hotkey, If,

; pipeline of copying latex to `klatexformula` and rendering
RenderClipboardInKlatexformula()
{
  Global appJsonObj

  proc := appJsonObj["klatexformula"].process . ".exe"
  WinGet, winList, List, ahk_exe %proc%
  Loop, %winList%
  {
    winHWD := winList%A_Index%
    WinGetTitle, title, ahk_id %winHWD%
    If (title == "KLatexFormula")
    {
      WinShow, ahk_id %winHWD%
      WinActivate, ahk_id %winHWD%
      Break
    }
  }

  Send +{F4}
  Send ^v

  Send {Tab}{Tab}{Enter}
}


; ----------------------------------------
;          hotkeys for window ops
; ----------------------------------------

; minimize
Bind(keybindingConfigs.hotkeys.appCommon["minimizeWindow"], "MinimizeWindow")

MinimizeWindow()
{
  WinMinimize, A
}

config := keybindingConfigs.hotkeys.global

; maximize
Bind(config["toggleMaximize"], "ToggleMaximize")
ToggleMaximize()
{
  ; every window has its own maximize state
  Static frameCacheMaximize := {}
  WinGet, wid, ID, A
  If Not frameCacheMaximize[wid]
  {
    WinGet, minmax, MinMax, A
    If minmax = 1
      Return
    WinGetPos, x, y, w, h, A
    frameCacheMaximize[wid] := x "," y "," w "," h
    WinMaximize, A
  }
  Else
  {
    WinRestore, A
    WinMove A,, frameCacheMaximize[wid]
    frameCacheMaximize[wid] := ""
  }
}

; move and zoom to center
Bind(config["toggleZoomToCenter"], "ToggleCenter")
ToggleCenter()
{
  Global keybindingConfigs

  Static frameCacheCenter := {}
  WinGet, wid, ID, A
  If Not frameCacheCenter[wid]
  {
    WinGet, minmax, MinMax, A
    If minmax = 1
    {
      frameCacheCenter[wid] := 1
      WinRestore, A
    }
    Else
    {
      WinGetPos, x, y, w, h, A
      frameCacheCenter[wid] := x "," y "," w "," h
    }
    SysGet, WA, MonitorWorkArea
    width := WARight - WALeft
    height := A_ScreenHeight - WATop
    ; consistent with the occupation of the window on MacOS
    WinGetPos ,,, w, h, A
    targetWidth := keybindingConfigs.parameters.windowZoomToCenterSize.w
    targetHeight := keybindingConfigs.parameters.windowZoomToCenterSize.h
    If (targetWidth == "")
      targetWidth := w
    If (targetHeight == "")
      targetHeight := h
    WinMove A,, WALeft + (width - targetWidth) / 2, WATop + (height - targetHeight) / 2, targetWidth, targetHeight
  }
  Else
  {
    WinRestore, A
    If frameCacheCenter[wid] = 1
      WinMaximize, A
    Else
      WinMove A,, frameCacheCenter[wid]
    frameCacheCenter[wid] := ""
  }
}

; move and zoom to side/corner
Bind(config["zoomToLeft"], New WinZoom(0, 0, 0.5, 1))
Bind(config["zoomToRight"], New WinZoom(0.5, 0, 0.5, 1))
Bind(config["zoomToTopLeft"], New WinZoom(0, 0, 0.5, 0.5))
Bind(config["zoomToBottomLeft"], New WinZoom(0, 0.5, 0.5, 0.5))
Bind(config["zoomToTopRight"], New WinZoom(0.5, 0, 0.5, 0.5))
Bind(config["zoomToBottomRight"], New WinZoom(0.5, 0.5, 0.5, 0.5))

Class WinZoom
{
  __New(x, y, w, h)
  {
    this.x := x
    this.y := y
    this.w := w
    this.h := h
  }

  __Call()
  {
    SysGet, WA, MonitorWorkArea
    width := WARight - WALeft
    height := A_ScreenHeight - WATop
    WinMove A,, WALeft + this.x * width, WATop + this.y * height, this.w * width, this.h * height
  }
}

; move to side/corner/center
Bind(config["moveToTopLeft"], New WinMoveTo("left", "top"))
Bind(config["moveToTop"], New WinMoveTo("", "top"))
Bind(config["moveToTopRight"], New WinMoveTo("right", "top"))
Bind(config["moveToLeft"], New WinMoveTo("left", ""))
Bind(config["moveToCenter"], New WinMoveTo("center", "center"))
Bind(config["moveToRight"], New WinMoveTo("right", ""))
Bind(config["moveToBottomLeft"], New WinMoveTo("left", "bottom"))
Bind(config["moveToBottom"], New WinMoveTo("", "bottom"))
Bind(config["moveToBottomRight"], New WinMoveTo("right", "bottom"))

Class WinMoveTo
{
  __New(horizontal, vertical)
  {
    this.horizontal := horizontal
    this.vertical := vertical
  }

  __Call()
  {
    SysGet, WA, MonitorWorkArea
    WinGetPos ,,, w, h, A
    If this.horizontal = "left"
      horizontal := WALeft
    Else If this.horizontal = "right"
      horizontal := WARight - w
    Else If this.horizontal = "center"
      horizontal := WALeft + (WARight - WALeft - w) / 2
    If this.vertical = "top"
      vertical := WATop
    Else If this.vertical = "bottom"
      vertical := A_ScreenHeight - h
    Else If this.vertical = "center"
      vertical := WATop + (A_ScreenHeight - WATop - h) / 2
    WinMove A,, % horizontal, % vertical
  }
}

; move in direction
step := keybindingConfigs.parameters.windowMoveStep
If (step == "")
  step := 100
Bind(config["moveTowardsTopLeft"], New WinMoveBy(-step, -step))
Bind(config["moveTowardsTop"], New WinMoveBy(0, -step))
Bind(config["moveTowardsTopRight"], New WinMoveBy(step, -step))
Bind(config["moveTowardsLeft"], New WinMoveBy(-step, 0))
Bind(config["moveTowardsRight"], New WinMoveBy(step, 0))
Bind(config["moveTowardsBottomLeft"], New WinMoveBy(-step, step))
Bind(config["moveTowardsBottom"], New WinMoveBy(0, step))
Bind(config["moveTowardsBottomRight"], New WinMoveBy(step, step))

Class WinMoveBy
{
  __New(dx, dy)
  {
    this.dx := dx
    this.dy := dy
  }

  __Call()
  {
    WinGetPos, X, Y, , , A
    WinMove A,, X + this.dx, Y + this.dy
  }
}

; toggle full screen
Remap(config["toggleFullScreen"], "{F11}")

; move cursor to another desktop
Remap(config["focusNextDesktop"], "^#{Right}")
Remap(config["focusPrevDesktop"], "^#{Left}")

; move window to another desktop
Bind(config["moveToNextDesktop"], "MoveToNextDesktop")
Bind(config["moveToPrevDesktop"], "MoveToPrevDesktop")
MoveToNextDesktop()
{
  WinGet, active_id, ID, A
  WinHide, ahk_id %active_id%
  Send #^{Right}
  WinShow, ahk_id %active_id%
  WinActivate, ahk_id %active_id%
}
MoveToPrevDesktop()
{
  WinGet, active_id, ID, A
  WinHide, ahk_id %active_id%
  Send #^{Left}
  WinShow, ahk_id %active_id%
  WinActivate, ahk_id %active_id%
  Return
}

; increase / decrease non-transparency
Bind(config["transparentPlus"], "WinTransPlus")
Bind(config["transparentMinus"], "WinTransMinus")

WinTransPlus()
{
  WinGet, w, id, A
  WinGet, transparent, Transparent, ahk_id %w%
  If transparent < 255
    transparent := transparent + 2
  Else
    transparent =
  If transparent
    WinSet, Transparent, %transparent%, ahk_id %w%
  Else
    WinSet, Transparent, off, ahk_id %w%
}

WinTransMinus()
{
  WinGet, w, id, A
  WinGet, transparent, Transparent, ahk_id %w%
  If transparent
    transparent := transparent - 2
  Else
    transparent := 255
  WinSet, Transparent, %transparent%, ahk_id %w%
}


; ----------------------------------------
;                  others
; ----------------------------------------

Remap("XButton2", "^{c}")
Remap("XButton1", "^{v}")

Hotkey, XButton2 & WheelUp, ShiftAltTab
Hotkey, XButton2 & WheelDown, AltTab

Hotkey, IfWinActive, 任务切换 ahk_exe Explorer.EXE
  Remap("!``", "!+Tab")
Hotkey, IfWinActive

; switch between windows of frontmost application
Hotkey, IfWinNotActive, 任务切换 ahk_exe Explorer.EXE
  Bind("!``", "SwitchFrontmostAppWindow")
Hotkey, IfWinNotActive

SwitchFrontmostAppWindow()
{
WinGet, A_proc, ProcessName, A
WinGet, A_winID, ID, A
WinGet, WinCount, Count, ahk_exe %A_proc%
If WinCount = 1
  Return
WinGet, List, List, % "ahk_exe " A_proc

Loop % List
{
  If (List%A_Index% = A_winID)
  {
    index := A_Index
    Break
  }
}

While GetKeyState("Alt")
{
  If Not (A_proc = "ApplicationFrameHost.exe")
  {
    If GetKeyState("Shift")
      index := Mod(List + index - 2, List) + 1
    Else
      index := Mod(List + index, List) + 1
    WinGet, State, MinMax, % "ahk_id " List%index%
    If (State == -1)
      Continue
    If (A_proc = "explorer.exe")
    {
      While _IsIgnoredExplorerWindow("ahk_id " List%index%)
      {
        If GetKeyState("Shift")
          index := Mod(List + index - 2, List) + 1
        Else
          index := Mod(List + index, List) + 1
      }
    }
    WinID := List%index%
    WinActivate, % "ahk_id " WinID
  }
  ErrorLevel := 1
  Sleep 200
  While (ErrorLevel != 0) and GetKeyState("Alt") {
    KeyWait, sc029, DT1 ; sc029 is ` (backtick)
  }
}
}

config := keybindingConfigs.hotkeys.global

; screen capture
#If Not _IsActive("terminal")
#If
Hotkey, If, Not _IsActive("terminal")
  Remap(config["screenShot"], "#+{S}")
Hotkey, If

hyper := keybindingConfigs.hyper.hyper
; hyper + tab/` -> forward / back
Remap(hyper " & ``", "^{[}")
Remap(hyper " & Tab", "^{]}")

; hyper + 1 -> enter
Remap(hyper " & 1", "{Enter}")

; system clipboard history
Remap(config["showClipboardHistory"], "#v")

; show or hide desktop
Remap(config["toggleDesktop"], "#d")

; focus on task tray
Remap(config["focusSystemTray"], "#b")
; focus on taskbar applications
Remap(config["focusTaskbarIcon"], "#t")

; task view
Remap(config["toggleTaskView"], "#{Tab}")

; mydockfinder launchbar
#If _IsRunning("mydockfinder")
#If

Hotkey, If, _IsRunning("mydockfinder")
  Remap(keybindingConfigs.hotkeys["mydockfinder"]["showLaunchPad"], "!{x}")
Hotkey, If,

; control center
Remap(config["toggleQuickSettings"], "#a")
Remap(config["toggleNotificationCenter"], "#n")
Hotkey, If, _IsRunning("mydockfinder")
  Bind(keybindingConfigs.hotkeys["mydockfinder"]["toggleControlCenter"], "ToggleControlCenter")
  ToggleControlCenter()
  {
    CoordMode, Mouse, Screen
    x := 2044
    y := 15
    MouseMove, %x%, %y%
    Click
  }
Hotkey, If,

; system tray
Bind(config["toggleSystemTray"], "ToggleSystemTray")
ToggleSystemTray()
{
  If Not WinExist("ahk_class TopLevelWindowForOverflowXamlIsland")
  {
    Send #{b}{Space}
    If _IsRunning("mydockfinder")
    {
      WinWait, ahk_class TopLevelWindowForOverflowXamlIsland
      New WinMoveTo("right", "bottom").__Call()
    }
  }
  Else
    Send {Escape}
}

Hotkey, If, _IsRunning("mydockfinder")
  Bind(keybindingConfigs.hotkeys["mydockfinder"]["toggleMenuBarTray"], "ToggleMenuBarTray")
  toggleMenuBarTray()
  {
    CoordMode, Mouse, Screen
    x := 2000
    y := 15
    MouseMove, %x%, %y%
    Click
  }
Hotkey, If,

; windows run
Bind("~#r", "WindowsRun")
WindowsRun()
{
  Send #r
  WinWait, 运行 ahk_class #32770 ahk_exe explorer.exe
  New WinMoveTo("center", "center").__Call()
}


; ----------------------------------------
;           third party scripts
; ----------------------------------------

; Window Menu Search - tap the Alt key to search the active window's menus. http://www.autohotkey.com/board/topic/91067-/

SetBatchLines -1
OnMessage(0x100, "GuiKeyDown")
OnMessage(0x6, "GuiActivate")
return

Alt::
Gui +LastFoundExist
if WinActive()
  goto GuiEscape
Gui Destroy
Gui Font, s11
Gui Margin, 0, 0
Gui Add, Edit, x20 w500 vQuery gType
Gui Add, Text, x5 y+2 w15, 1`n2`n3`n4`n5`n6`n7`n8`n9
Gui Add, ListBox, x+0 yp-2 w500 r21 vCommand gSelect AltSubmit
Gui Add, StatusBar
Gui +ToolWindow +Resize +MinSize +MinSize200x +MaxSize +MaxSize%A_ScreenWidth%x
window := WinExist("A")
if !(cmds := MenuGetAll(window))
{
  Send {Alt}
  return
}
gosub Type
WinGetTitle title, ahk_id %window%
title := RegExReplace(title, ".* - ")
Gui Show,, Searching menus of:  %title%
GuiControl Focus, Query
return

Type:
SetTimer Refresh, -10
return

Refresh:
GuiControlGet Query
r := cmds
if (Query != "")
{
  StringSplit q, Query, %A_Space%
  Loop % q0
    r := Filter(r, q%A_Index%, c)
}
rows := ""
row_id := []
Loop Parse, r, `n
{
  RegExMatch(A_LoopField, "(\d+)`t(.*)", m)
  row_id[A_Index] := m1
  rows .= "|"  m2
}
GuiControl,, Command, % rows ? rows : "|"
if (Query = "")
  c := row_id.MaxIndex()

Select:
GuiControlGet Command
if !Command
  Command := 1
Command := row_id[Command]
SB_SetText("Total " c " results`t`tID: " Command)
if (A_GuiEvent != "DoubleClick")
  return

Confirm:
if !GetKeyState("Shift")
{
  gosub GuiEscape
  WinActivate ahk_id %window%
}
DllCall("SendNotifyMessage", "ptr", window, "uint", 0x111, "ptr", Command, "ptr", 0)
return

GuiEscape:
Gui Destroy
cmds := r := ""
return

GuiSize:
GuiControl Move, Query, % "w" A_GuiWidth-20
GuiControl Move, Command, % "w" A_GuiWidth-20
return

GuiActivate(wParam)
{
  if (A_Gui && wParam = 0)
    SetTimer GuiEscape, -5
}

GuiKeyDown(wParam, lParam)
{
  if !A_Gui
    return
  if (wParam = GetKeyVK("Enter"))
  {
    gosub Confirm
    return 0
  }
  if (wParam = GetKeyVK(key := "Down")
   || wParam = GetKeyVK(key := "Up"))
  {
    GuiControlGet focus, FocusV
    if (focus != "Command")
    {
      GuiControl Focus, Command
      if (key = "Up")
        Send {End}
      else
        Send {Home}
      return 0
    }
    return
  }
  if (wParam >= 49 && wParam <= 57 && !GetKeyState("Shift"))
  {
    SendMessage 0x18E,,, ListBox1
    GuiControl Choose, Command, % wParam-48 + ErrorLevel
    GuiControl Focus, Command
    gosub Select
    return 0
  }
  if (wParam = GetKeyVK(key := "PgUp")
   || wParam = GetKeyVK(key := "PgDn"))
  {
    GuiControl Focus, Command
    Send {%key%}
    return
  }
}

Filter(s, q, ByRef count)
{
  if (q = "")
  {
    StringReplace s, s, `n, `n, UseErrorLevel
    count := ErrorLevel
    return s
  }
  i := 1
  match := ""
  result := ""
  count := 0
  while i := RegExMatch(s, "`ami)^.*\Q" q "\E.*$", match, i + StrLen(match))
  {
    result .= match "`n"
    count += 1
  }
  return SubStr(result, 1, -1)
}

MenuGetAll(hwnd)
{
  if !menu := DllCall("GetMenu", "ptr", hwnd, "ptr")
    return ""
  MenuGetAll_sub(menu, "", cmds)
  return cmds
}

MenuGetAll_sub(menu, prefix, ByRef cmds)
{
  Loop % DllCall("GetMenuItemCount", "ptr", menu)
  {
    VarSetCapacity(itemString, 2000)
    if !DllCall("GetMenuString", "ptr", menu, "int", A_Index-1, "str", itemString, "int", 1000, "uint", 0x400)
      continue
    StringReplace itemString, itemString, &
    itemID := DllCall("GetMenuItemID", "ptr", menu, "int", A_Index-1)
    if (itemID = -1)
    if subMenu := DllCall("GetSubMenu", "ptr", menu, "int", A_Index-1, "ptr")
    {
      MenuGetAll_sub(subMenu, prefix itemString " > ", cmds)
      continue
    }
    cmds .= itemID "`t" prefix RegExReplace(itemString, "`t.*") "`n"
  }
}