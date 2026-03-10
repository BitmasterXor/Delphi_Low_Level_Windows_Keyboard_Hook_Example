program KBHookDemo;

{*******************************************************************************
  TKeyboardHook Component - Demo Application
  ==========================================
  Author  : BitmasterXor
  Version : 1.0

  This demo shows how to use the TKeyboardHook component both:
    a) Programmatically (creates it in code - works without installing the pkg)
    b) Via the form DFM     (after installing the package in the IDE, you can
                             drag TKeyboardHook from the palette and drop it
                             on the form just like any other component)

  Build:
    File -> Open -> KBHookDemo.dpr  (or double-click in Explorer)
    Then: Run -> Run  (F9)

  Note: The demo references uKeyboardHook directly via the search path.
        No package installation is needed just to compile and run the demo.
*******************************************************************************}

uses
  Vcl.Forms,
  Vcl.Themes,
  Vcl.Styles,
  DemoForm in 'DemoForm.pas' {frmDemo},
  uKeyboardHook in '..\uKeyboardHook.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'TKeyboardHook Demo';
  Application.CreateForm(TfrmDemo, frmDemo);
  Application.Run;
end.
