; AutoHotKey v1.1.33.20

; ----------------------------------------
;         global settings
; ----------------------------------------

#SingleInstance force
#Persistent
#NoEnv
Process, priority, , high
SetWorkingDir, %A_ScriptDir%
Send, {Alt Up}{Ctrl Up}{Shift Up}{LWin Up}{RWin Up}
Menu, Tray, NoIcon

; ----------------------------------------
;        auto-reload on change
; ----------------------------------------

#Include WatchFolder.ahk
WatchFolder(A_ScriptDir, "_ReloadHelper", False, 16)
_ReloadHelper(dir, changes) {
  Static relatedFiles := ["sync.ahk", "WatchFolder.ahk", "JSON.ahk"]
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
syncConfigs := JSON.Load(FileOpen("config\sync.json", "r").Read())

Replace1(var)
{
  pos := 1
  While (pos := RegExMatch(var, "%(A_\w+)%", match, pos)) != 0
    var := SubStr(var, 1, pos - 1) . %match1% . SubStr(var, pos + StrLen(match1) + 2)
  pos := 1
  While (pos := RegExMatch(var, "%(\w+)%", match, pos)) != 0
  {
    len := StrLen(match1)
    EnvGet, match1, %match1%
    var := SubStr(var, 1, pos - 1) . match1 . SubStr(var, pos + len + 2)
  }
  Return var
}

Replace2(var, dict)
{
  pos := 1
  While (pos := RegExMatch(var, "\${(\w+)}", match, pos)) != 0
    var := SubStr(var, 1, pos - 1) . dict[match1] . SubStr(var, pos + StrLen(match1) + 3)
  Return var
}

For k, var in syncConfigs.variable
{
  var := StrReplace(var, "/", "\")
  var := Replace1(var)
  syncConfigs.variable[k] := var
}
For k, var in syncConfigs.variable
{
  var := Replace2(var, syncConfigs.variable)
  syncConfigs.variable[k] := var
}

syncMaps := {}
For src, dst in syncConfigs.file
{
  src := StrReplace(src, "/", "\")
  src := Replace1(src)
  src := Replace2(src, syncConfigs.variable)

  dst := StrReplace(dst, "/", "\")
  dst := Replace1(dst)
  dst := Replace2(dst, syncConfigs.variable)

  syncMaps[src] := dst
}

paramsBuffer := {}
For src, dst in syncMaps
{
  attr := FileExist(src)
  If (attr == "")
    Continue
  If Not InStr(attr, "D")
  {
    pos := 0
    While (newPos := InStr(src, "\", False, pos + 1)) != 0
      pos := newPos
    parent := SubStr(src, 1, pos - 1)
    filename := SubStr(src, pos + 1)
    If (paramsBuffer[parent] == "")
    {
      paramsBuffer[parent] := {}
      _WatchModifiedFiles(parent, "_SyncModifiedFiles")
    }
    paramsBuffer[parent][filename] := dst
  }
  Else
  {
    If (paramsBuffer[src] == "")
    {
      paramsBuffer[src] := {}
      _WatchModifiedFiles(src, "_SyncModifiedFiles")
    }
    paramsBuffer[src][dst] := True
  }
}

_WatchModifiedFiles(Folder, Func)
{
  Return WatchFolder(Folder, Func, True, 16)
}

_SyncModifiedFiles(dir, changes)
{
  Global paramsBuffer

  For filename, dst in paramsBuffer[dir]
  {
    If (dst == True)
    {
      dst := filename
      For Each, change In changes
        If (change.action = 3)
        {
          FileCopyDir, % dir, % dst, 1
          Break
        }
    }
    Else
    {
      watchedFile := dir . "\" . filename
      For Each, change In changes
        If (change.action = 3 && change.name = watchedFile)
          FileCopy, % change.name, % dst, 1
    }
  }
}
