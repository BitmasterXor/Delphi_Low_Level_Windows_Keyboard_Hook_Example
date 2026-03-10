unit DemoForm;

{*******************************************************************************
  TKeyboardHook Component - Demo Form
  =====================================
  Author  : BitmasterXor
  Version : 1.0

  This demo shows TKeyboardHook used exactly as a drag-and-drop component:
    - KeyboardHook1 was dropped onto the form from the "BitmasterXor" palette
    - All three events are wired in the DFM (Object Inspector), not in code
    - The form class declares KeyboardHook1 in its published section, just like
      any other VCL control (TButton, TMemo, etc.)

  Events demonstrated:
    KeyboardHook1KeyDown      - fires for every key press
    KeyboardHook1KeyUp        - fires for every key release
    KeyboardHook1WindowChange - fires when the active window title changes
*******************************************************************************}

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  uKeyboardHook;

type
  TfrmDemo = class(TForm)

    // ---- Controls ----
    pnlToolbar     : TPanel;
    btnStart       : TButton;
    btnStop        : TButton;
    btnClearLog    : TButton;
    btnClearTyping : TButton;
    lblStatus      : TLabel;
    shpIndicator   : TShape;
    grpKeyLog      : TGroupBox;
    mmoKeyLog      : TMemo;
    grpTyping      : TGroupBox;
    mmoTyping      : TMemo;

    // ---- The drag-and-drop component (dropped from BitmasterXor palette) ----
    KeyboardHook1  : TKeyboardHook;

    // ---- Form events ----
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);

    // ---- Button events ----
    procedure btnStartClick(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure btnClearLogClick(Sender: TObject);
    procedure btnClearTypingClick(Sender: TObject);

    // ---- TKeyboardHook events (wired in DFM / Object Inspector) ----
    procedure KeyboardHook1KeyDown(Sender: TObject; const KeyInfo: TKeyEventInfo);
    procedure KeyboardHook1KeyUp(Sender: TObject; const KeyInfo: TKeyEventInfo);
    procedure KeyboardHook1WindowChange(Sender: TObject; const WindowTitle: string);

  private
    procedure UpdateUI;
    procedure AppendLog(const Line: string);
  end;

var
  frmDemo: TfrmDemo;

implementation

{$R *.dfm}

// ============================================================================
//  Form lifecycle
// ============================================================================

procedure TfrmDemo.FormCreate(Sender: TObject);
begin
  // KeyboardHook1 already exists — it was streamed in from the DFM.
  // No Create call needed. Just sync the UI to the initial state.
  UpdateUI;
  AppendLog('TKeyboardHook component ready.  (dropped from component palette)');
  AppendLog('Click "Start Hook" to begin capturing keyboard input.');
  AppendLog(StringOfChar('-', 60));
end;

procedure TfrmDemo.FormDestroy(Sender: TObject);
begin
  // Ensure the hook is uninstalled before the form tears down.
  // KeyboardHook1 is owned by the form and freed automatically after this.
  KeyboardHook1.StopHook;
end;

// ============================================================================
//  Button handlers
// ============================================================================

procedure TfrmDemo.btnStartClick(Sender: TObject);
begin
  try
    KeyboardHook1.StartHook;
    AppendLog('[' + FormatDateTime('hh:nn:ss ampm', Now) + '] Hook started successfully.');
    AppendLog(StringOfChar('-', 60));
  except
    on E: Exception do
    begin
      AppendLog('[ERROR] Could not start hook: ' + E.Message);
      ShowMessage('Could not install keyboard hook:' + #13#10 + E.Message);
    end;
  end;
  UpdateUI;
end;

procedure TfrmDemo.btnStopClick(Sender: TObject);
begin
  KeyboardHook1.StopHook;
  AppendLog('[' + FormatDateTime('hh:nn:ss ampm', Now) + '] Hook stopped.');
  AppendLog(StringOfChar('-', 60));
  UpdateUI;
end;

procedure TfrmDemo.btnClearLogClick(Sender: TObject);
begin
  mmoKeyLog.Clear;
end;

procedure TfrmDemo.btnClearTypingClick(Sender: TObject);
begin
  mmoTyping.Clear;
end;

// ============================================================================
//  TKeyboardHook event handlers
//  These are assigned in the DFM (just like OnClick on a TButton).
//  The Delphi IDE wired them by name when you double-clicked each event
//  in the Object Inspector with KeyboardHook1 selected.
// ============================================================================

procedure TfrmDemo.KeyboardHook1KeyDown(Sender: TObject;
                                        const KeyInfo: TKeyEventInfo);
// Fires for every WM_KEYDOWN and WM_SYSKEYDOWN (Alt-key combinations).
// KeyInfo contains every detail about the key event — just read what you need.
var
  Mods    : string;
  LogLine : string;
  SelPos  : Integer;
begin
  // Build a modifier prefix  e.g. "[CTRL]+[SHIFT]+"
  Mods := '';
  if KeyInfo.IsCtrlDown   then Mods := Mods + '[CTRL]+';
  if KeyInfo.IsShiftDown  then Mods := Mods + '[SHIFT]+';
  if KeyInfo.IsAltDown    then Mods := Mods + '[ALT]+';
  if KeyInfo.IsWinKeyDown then Mods := Mods + '[WIN]+';

  // Build the log entry line
  LogLine := Format('[%s] %s%s',
    [FormatDateTime('hh:nn:ss ampm', Now), Mods, KeyInfo.KeyName]);

  // Show the typed character when the key produces one  e.g.  -> 'a'
  if KeyInfo.Character <> '' then
    LogLine := LogLine + Format(' -> ''%s''', [KeyInfo.Character]);

  // Show which application window was in focus
  if KeyInfo.ActiveWindow <> '' then
    LogLine := LogLine + Format('  [%s]', [KeyInfo.ActiveWindow]);

  AppendLog(LogLine);

  // ---- Typing simulation in the lower memo ----
  case KeyInfo.VirtualKey of

    VK_BACK:
      // Backspace: remove the character immediately left of the cursor
      with mmoTyping do
        if SelStart > 0 then
        begin
          SelPos   := SelStart - 1;
          Text     := Copy(Text, 1, SelPos) + Copy(Text, SelPos + 2, MaxInt);
          SelStart := SelPos;
        end;

    VK_RETURN:
      // Enter: start a new line
      mmoTyping.Lines.Add('');

  else
    // Any other printable character: insert at cursor
    if KeyInfo.Character <> '' then
      with mmoTyping do
      begin
        SelPos   := SelStart;
        Text     := Copy(Text, 1, SelPos)
                  + KeyInfo.Character
                  + Copy(Text, SelPos + 1, MaxInt);
        SelStart := SelPos + 1;
      end;
  end;
end;

procedure TfrmDemo.KeyboardHook1KeyUp(Sender: TObject;
                                      const KeyInfo: TKeyEventInfo);
// Fires for every WM_KEYUP and WM_SYSKEYUP.
// Not logged here to keep the log readable, but all KeyInfo fields are
// available — add your own logic whenever you need key-release detection.
begin
  // Example use: detect modifier release, toggle states, etc.
end;

procedure TfrmDemo.KeyboardHook1WindowChange(Sender: TObject;
                                             const WindowTitle: string);
// Fires when TrackWindowChanges = True and the foreground window title changes.
// Insert a visual separator so it is clear which window each key went to.
begin
  AppendLog('');
  AppendLog(Format('>>> Active window: %s', [WindowTitle]));
  AppendLog(StringOfChar('=', 60));
end;

// ============================================================================
//  Internal helpers
// ============================================================================

procedure TfrmDemo.UpdateUI;
begin
  btnStart.Enabled := not KeyboardHook1.Active;
  btnStop.Enabled  :=     KeyboardHook1.Active;

  if KeyboardHook1.Active then
  begin
    lblStatus.Caption        := 'Status: ACTIVE - capturing all keyboard input';
    lblStatus.Font.Color     := clGreen;
    shpIndicator.Brush.Color := clLime;
  end
  else
  begin
    lblStatus.Caption        := 'Status: Idle';
    lblStatus.Font.Color     := clGrayText;
    shpIndicator.Brush.Color := $004040BF;
  end;
end;

procedure TfrmDemo.AppendLog(const Line: string);
begin
  mmoKeyLog.Lines.Add(Line);
  SendMessage(mmoKeyLog.Handle, WM_VSCROLL, SB_BOTTOM, 0);
end;

end.
