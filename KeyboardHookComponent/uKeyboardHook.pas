unit uKeyboardHook;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes;

{ ---- Low-level keyboard hook flag constants -------------------------------- }
const
  LLKHF_EXTENDED = $0001; // Extended key (right Ctrl, right Alt, Numpad Enter…)
  LLKHF_INJECTED = $0010; // Key was injected via SendInput / keybd_event
  LLKHF_ALTDOWN  = $0020; // Alt key is held at the time of this event
  LLKHF_UP       = $0080; // This is a key-up event

type

  { ---- Windows KBDLLHOOKSTRUCT -------------------------------------------
    The structure Windows passes to our hook callback for every key event.
    We redeclare it here so this unit has no dependency on the full header. }
  PKBDLLHOOKSTRUCT = ^TKBDLLHOOKSTRUCT;
  TKBDLLHOOKSTRUCT = record
    vkCode     : DWORD;       // Virtual-key code  (VK_*)
    scanCode   : DWORD;       // Hardware scan code
    flags      : DWORD;       // Event flags       (see LLKHF_* above)
    time       : DWORD;       // System tick count at moment of event
    dwExtraInfo: ULONG_PTR;   // Extra data (set by whoever generated the event)
  end;

  { ---- TKeyEventInfo -------------------------------------------------------
    Comprehensive snapshot of a single key event. Every field is populated
    before OnKeyDown / OnKeyUp fires — just read what you need. }
  TKeyEventInfo = record
    VirtualKey    : DWORD;   // Windows VK_* code  (e.g. VK_RETURN = 13)
    ScanCode      : DWORD;   // Raw hardware scan code from the keyboard
    KeyName       : string;  // Human-readable name: '[ESC]', '[F5]', 'A', etc.
    Character     : string;  // Printable result if the key produces one: 'a','@'
                             //   Empty string for non-printable keys (F-keys, arrows…)
    IsShiftDown   : Boolean; // Left OR right Shift is held
    IsCtrlDown    : Boolean; // Left OR right Ctrl is held
    IsAltDown     : Boolean; // Left OR right Alt is held
    IsWinKeyDown  : Boolean; // Left OR right Windows key is held
    IsExtendedKey : Boolean; // True for right-side modifiers, Numpad Enter, etc.
    IsInjected    : Boolean; // True if the event was synthesised (SendInput etc.)
    TimeStamp     : DWORD;   // System tick at the moment of the key event
    ActiveWindow  : string;  // Title of the foreground window at time of event
  end;

  { ---- Event types -------------------------------------------------------- }

  { Fired for every key press or release. KeyInfo contains all details. }
  TKeyHookEvent = procedure(Sender: TObject; const KeyInfo: TKeyEventInfo) of object;

  { Fired when the foreground window title changes (requires TrackWindowChanges). }
  TWindowChangeEvent = procedure(Sender: TObject;
                                 const WindowTitle: string) of object;

  { ---- TKeyboardHook ------------------------------------------------------
    The component class. Non-visual; appears as an icon in the form's
    component tray at design time. }
  TKeyboardHook = class(TComponent)
  private
    FHookHandle       : HHOOK;
    FActive           : Boolean;
    FCurrentWindow    : string;
    FTrackWindows     : Boolean;
    FOnKeyDown        : TKeyHookEvent;
    FOnKeyUp          : TKeyHookEvent;
    FOnWindowChange   : TWindowChangeEvent;

    procedure SetActive(const Value: Boolean);
    function  GetActive: Boolean;

  protected
    { Called from Loaded so that Active=True in the DFM starts the hook
      AFTER the form has fully streamed in rather than during loading. }
    procedure Loaded; override;

    { Invoked by the global stdcall hook callback for each keyboard message. }
    procedure ProcessKeyEvent(wParam: WPARAM; HookData: PKBDLLHOOKSTRUCT);

  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;

    { Install the keyboard hook. Raises an exception if it fails. }
    procedure StartHook;

    { Remove the keyboard hook. Safe to call when already inactive. }
    procedure StopHook;

    { Read-only: the raw HHOOK handle (0 when inactive). }
    property HookHandle: HHOOK read FHookHandle;

  published
    { Set True to start capturing, False to stop.
      Safe at design time — the hook is never installed inside the IDE. }
    property Active: Boolean
      read    GetActive
      write   SetActive
      default False;

    { When True the OnWindowChange event fires whenever the title of the
      foreground window changes. }
    property TrackWindowChanges: Boolean
      read    FTrackWindows
      write   FTrackWindows
      default True;

    { Fires for every WM_KEYDOWN and WM_SYSKEYDOWN (Alt-key combos). }
    property OnKeyDown: TKeyHookEvent
      read  FOnKeyDown
      write FOnKeyDown;

    { Fires for every WM_KEYUP and WM_SYSKEYUP. }
    property OnKeyUp: TKeyHookEvent
      read  FOnKeyUp
      write FOnKeyUp;

    { Fires when the foreground window title changes (if TrackWindowChanges). }
    property OnWindowChange: TWindowChangeEvent
      read  FOnWindowChange
      write FOnWindowChange;
  end;

{ Call this inside a package to register TKeyboardHook in the component palette. }
procedure Register;

implementation

{$R uKeyboardHook.dcr}

{ ===========================================================================
  Module-level globals
  Only one TKeyboardHook instance may be active at a time.  The global hook
  callback (a plain stdcall function) delegates to this instance pointer.
  =========================================================================== }
var
  _ActiveHook  : TKeyboardHook = nil;  // The currently active component instance
  _HookHandle  : HHOOK         = 0;    // Mirrored here for the callback to read

{ ===========================================================================
  Private helper functions
  These are unit-level (not methods) because they don't need component state.
  =========================================================================== }

{------------------------------------------------------------------------------
  MapVKeyToChar
  Returns the printable character produced by the given virtual key, taking
  the Shift state into account.  Returns '' for non-printable keys.
------------------------------------------------------------------------------}
function MapVKeyToChar(vkCode: DWORD; ShiftDown: Boolean): string;
const
  { Shifted symbols on the US standard number row }
  ShiftedNumbers: array[Ord('0')..Ord('9')] of Char =
    (')', '!', '@', '#', '$', '%', '^', '&', '*', '(');
begin
  case vkCode of

    { ---- Letters ---------------------------------------------------------- }
    Ord('A')..Ord('Z'):
      if ShiftDown then Result := Chr(vkCode)          // Uppercase
      else              Result := Chr(vkCode + 32);    // Lowercase

    { ---- Number row with shift symbols ------------------------------------ }
    Ord('0')..Ord('9'):
      if ShiftDown then Result := ShiftedNumbers[vkCode]
      else              Result := Chr(vkCode);

    { ---- Numpad digits (NumLock on) --------------------------------------- }
    VK_NUMPAD0..VK_NUMPAD9:
      Result := Chr(Ord('0') + (vkCode - VK_NUMPAD0));

    { ---- Space / Tab ------------------------------------------------------ }
    VK_SPACE: Result := ' ';
    VK_TAB:   Result := #9;

    { ---- OEM / punctuation keys with shift variants ----------------------- }
    VK_OEM_1:      if ShiftDown then Result := ':'  else Result := ';';
    VK_OEM_PLUS:   if ShiftDown then Result := '+'  else Result := '=';
    VK_OEM_COMMA:  if ShiftDown then Result := '<'  else Result := ',';
    VK_OEM_MINUS:  if ShiftDown then Result := '_'  else Result := '-';
    VK_OEM_PERIOD: if ShiftDown then Result := '>'  else Result := '.';
    VK_OEM_2:      if ShiftDown then Result := '?'  else Result := '/';
    VK_OEM_3:      if ShiftDown then Result := '~'  else Result := '`';
    VK_OEM_4:      if ShiftDown then Result := '{'  else Result := '[';
    VK_OEM_5:      if ShiftDown then Result := '|'  else Result := '\';
    VK_OEM_6:      if ShiftDown then Result := '}'  else Result := ']';
    VK_OEM_7:      if ShiftDown then Result := '"'  else Result := '''';

  else
    Result := ''; // Non-printable key — no character produced
  end;
end;

{------------------------------------------------------------------------------
  MapVKeyToName
  Returns a human-readable bracketed name for any virtual key code.
  E.g.  VK_ESCAPE -> '[ESC]',  VK_F5 -> '[F5]',  Ord('A') -> '[A]'
------------------------------------------------------------------------------}
function MapVKeyToName(vkCode: DWORD): string;
begin
  case vkCode of
    VK_ESCAPE:   Result := '[ESC]';
    VK_F1..VK_F24:
      Result := '[F' + IntToStr(Integer(vkCode) - VK_F1 + 1) + ']';
    VK_RETURN:   Result := '[ENTER]';
    VK_BACK:     Result := '[BACKSPACE]';
    VK_SPACE:    Result := '[SPACE]';
    VK_TAB:      Result := '[TAB]';
    VK_CAPITAL:  Result := '[CAPS LOCK]';

    VK_SHIFT, VK_LSHIFT, VK_RSHIFT:
      Result := '[SHIFT]';
    VK_CONTROL, VK_LCONTROL, VK_RCONTROL:
      Result := '[CTRL]';
    VK_MENU, VK_LMENU, VK_RMENU:
      Result := '[ALT]';
    VK_LWIN, VK_RWIN:
      Result := '[WIN]';

    VK_LEFT:     Result := '[LEFT]';
    VK_RIGHT:    Result := '[RIGHT]';
    VK_UP:       Result := '[UP]';
    VK_DOWN:     Result := '[DOWN]';
    VK_HOME:     Result := '[HOME]';
    VK_END:      Result := '[END]';
    VK_PRIOR:    Result := '[PAGE UP]';
    VK_NEXT:     Result := '[PAGE DOWN]';
    VK_DELETE:   Result := '[DEL]';
    VK_INSERT:   Result := '[INS]';

    VK_SNAPSHOT: Result := '[PRINT SCREEN]';
    VK_SCROLL:   Result := '[SCROLL LOCK]';
    VK_PAUSE:    Result := '[PAUSE]';
    VK_NUMLOCK:  Result := '[NUM LOCK]';

    VK_NUMPAD0..VK_NUMPAD9:
      Result := '[NUMPAD ' + IntToStr(Integer(vkCode) - VK_NUMPAD0) + ']';
    VK_MULTIPLY: Result := '[NUMPAD *]';
    VK_ADD:      Result := '[NUMPAD +]';
    VK_SUBTRACT: Result := '[NUMPAD -]';
    VK_DIVIDE:   Result := '[NUMPAD /]';
    VK_DECIMAL:  Result := '[NUMPAD .]';

    VK_OEM_1:      Result := '[;/:]';
    VK_OEM_PLUS:   Result := '[=/+]';
    VK_OEM_COMMA:  Result := '[,/<]';
    VK_OEM_MINUS:  Result := '[-/_]';
    VK_OEM_PERIOD: Result := '[./>]';
    VK_OEM_2:      Result := '[//?]';
    VK_OEM_3:      Result := '[`/~]';
    VK_OEM_4:      Result := '[[/{]';
    VK_OEM_5:      Result := '[\|]';
    VK_OEM_6:      Result := '[][}]';
    VK_OEM_7:      Result := '[''/" ]';

  else
    { Letters and digits that haven't been matched above }
    if (vkCode >= Ord('0')) and (vkCode <= Ord('Z')) then
      Result := '[' + Chr(vkCode) + ']'
    else
      Result := '[VK_' + IntToStr(vkCode) + ']';
  end;
end;

{ ===========================================================================
  Global hook callback
  Windows calls this stdcall function for EVERY keyboard event system-wide.
  It MUST NOT be a method — Windows does not know about Delphi objects.
  We simply delegate to the active TKeyboardHook instance.
  =========================================================================== }
function LowLevelKeyboardProc(Code: Integer;
                              wParam: WPARAM;
                              lParam: LPARAM): LRESULT; stdcall;
begin
  { HC_ACTION means a real key event — only process those }
  if (Code = HC_ACTION) and Assigned(_ActiveHook) then
    _ActiveHook.ProcessKeyEvent(wParam, PKBDLLHOOKSTRUCT(lParam));

  { ALWAYS pass the event along to the next hook in the chain.
    Skipping this breaks keyboard input for the entire system! }
  Result := CallNextHookEx(_HookHandle, Code, wParam, lParam);
end;

{ ===========================================================================
  TKeyboardHook — implementation
  =========================================================================== }

constructor TKeyboardHook.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHookHandle    := 0;
  FActive        := False;
  FCurrentWindow := '';
  FTrackWindows  := True;
end;

destructor TKeyboardHook.Destroy;
begin
  StopHook; // Always clean up the hook before freeing
  inherited Destroy;
end;

procedure TKeyboardHook.Loaded;
begin
  inherited Loaded;
  { If Active was set to True in the Object Inspector / DFM, apply it now
    that the form has finished loading (avoids hooking during DFM streaming). }
  if FActive then
  begin
    FActive := False;  // Reset so StartHook can proceed
    StartHook;
  end;
end;

function TKeyboardHook.GetActive: Boolean;
begin
  Result := FActive;
end;

procedure TKeyboardHook.SetActive(const Value: Boolean);
begin
  if Value = FActive then Exit;

  { During form loading, just store the value — Loaded will apply it. }
  if csLoading in ComponentState then
  begin
    FActive := Value;
    Exit;
  end;

  { At design time inside the IDE, only store the value — never install a
    system-wide hook into the IDE process itself. }
  if csDesigning in ComponentState then
  begin
    FActive := Value;
    Exit;
  end;

  if Value then
    StartHook
  else
    StopHook;
end;

procedure TKeyboardHook.StartHook;
var
  WinBuf: array[0..255] of Char;
begin
  if csDesigning in ComponentState then Exit; // Safety guard for IDE
  if FHookHandle <> 0              then Exit; // Already active

  { Only one hook instance at a time }
  if Assigned(_ActiveHook) then
    raise Exception.Create(
      'TKeyboardHook: Another instance is already active. ' +
      'Call StopHook on the existing instance first.');

  { Register this instance as the active one before installing }
  _ActiveHook := Self;

  { Install the low-level keyboard hook into the Windows hook chain }
  _HookHandle := SetWindowsHookEx(
    WH_KEYBOARD_LL,             // Hook type: low-level keyboard
    @LowLevelKeyboardProc,      // Our callback function
    HInstance,                  // This module's instance handle
    0                           // 0 = monitor all threads on the desktop
  );

  if _HookHandle = 0 then
  begin
    _ActiveHook := nil;
    raise Exception.CreateFmt(
      'TKeyboardHook: SetWindowsHookEx failed (%s)',
      [SysErrorMessage(GetLastError)]);
  end;

  FHookHandle := _HookHandle;
  FActive     := True;

  { Seed the window tracker so the first OnWindowChange fires correctly }
  if FTrackWindows then
  begin
    GetWindowText(GetForegroundWindow, WinBuf, 256);
    FCurrentWindow := string(WinBuf);
  end;
end;

procedure TKeyboardHook.StopHook;
begin
  if FHookHandle = 0 then Exit; // Nothing to do

  UnhookWindowsHookEx(FHookHandle);

  FHookHandle    := 0;
  _HookHandle    := 0;
  _ActiveHook    := nil;
  FActive        := False;
  FCurrentWindow := '';
end;

procedure TKeyboardHook.ProcessKeyEvent(wParam: WPARAM;
                                        HookData: PKBDLLHOOKSTRUCT);
var
  KeyInfo   : TKeyEventInfo;
  WinBuf    : array[0..255] of Char;
  WinTitle  : string;
  IsKeyDown : Boolean;
begin
  { Determine event direction }
  IsKeyDown := (wParam = WM_KEYDOWN) or (wParam = WM_SYSKEYDOWN);

  { ---- Populate TKeyEventInfo ------------------------------------------- }
  KeyInfo.VirtualKey    := HookData^.vkCode;
  KeyInfo.ScanCode      := HookData^.scanCode;
  KeyInfo.TimeStamp     := HookData^.time;
  KeyInfo.IsExtendedKey := (HookData^.flags and LLKHF_EXTENDED) <> 0;
  KeyInfo.IsInjected    := (HookData^.flags and LLKHF_INJECTED)  <> 0;

  { GetKeyState returns a SHORT; the high-order bit (sign bit) = key is down }
  KeyInfo.IsShiftDown   := GetKeyState(VK_SHIFT)   < 0;
  KeyInfo.IsCtrlDown    := GetKeyState(VK_CONTROL) < 0;
  KeyInfo.IsAltDown     := GetKeyState(VK_MENU)    < 0;
  KeyInfo.IsWinKeyDown  := (GetKeyState(VK_LWIN)   < 0) or
                           (GetKeyState(VK_RWIN)   < 0);

  KeyInfo.KeyName    := MapVKeyToName(HookData^.vkCode);
  KeyInfo.Character  := MapVKeyToChar(HookData^.vkCode, KeyInfo.IsShiftDown);

  { ---- Foreground window title ------------------------------------------ }
  GetWindowText(GetForegroundWindow, WinBuf, 256);
  WinTitle := StringReplace(string(WinBuf), '*', '', [rfReplaceAll]);
  KeyInfo.ActiveWindow := WinTitle;

  { ---- Fire OnWindowChange if the title changed -------------------------- }
  if FTrackWindows and (WinTitle <> FCurrentWindow) then
  begin
    FCurrentWindow := WinTitle;
    if Assigned(FOnWindowChange) then
      FOnWindowChange(Self, WinTitle);
  end;

  { ---- Fire the appropriate key event ------------------------------------ }
  if IsKeyDown then
  begin
    if Assigned(FOnKeyDown) then
      FOnKeyDown(Self, KeyInfo);
  end
  else
  begin
    if Assigned(FOnKeyUp) then
      FOnKeyUp(Self, KeyInfo);
  end;
end;

{ ===========================================================================
  Package registration
  =========================================================================== }
procedure Register;
begin
  RegisterComponents('KeyBoardHook', [TKeyboardHook]);
end;

end.
