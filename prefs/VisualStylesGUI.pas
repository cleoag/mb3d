unit VisualStylesGUI;

{$mode delphi}

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls;

type
  TVisualStylesForm = class(TForm)
    SaveAndExitBtn: TButton;
    StylesCmb: TComboBox;
    Label1: TLabel;
    ApplyBtn: TButton;
    procedure SaveAndExitBtnClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure ApplyBtnClick(Sender: TObject);
  private
    { Private-Deklarationen }
    FInitialStyle: String;
  public
    { Public-Deklarationen }
  end;

var
  VisualStylesForm: TVisualStylesForm;

implementation

{$R *.dfm}

{ Note: Vcl.Themes / TStyleManager is not available in LCL (Lazarus).
  LCL applications use native OS widget themes automatically.
  This form is kept functional but theme selection is disabled. }

procedure TVisualStylesForm.SaveAndExitBtnClick(Sender: TObject);
begin
    Visible := False;
end;

procedure TVisualStylesForm.ApplyBtnClick(Sender: TObject);
begin
  { TStyleManager.TrySetStyle is not available in LCL.
    LCL uses native OS themes automatically. }
end;

procedure TVisualStylesForm.FormShow(Sender: TObject);
begin
  FInitialStyle := 'Default (System)';
  StylesCmb.Items.BeginUpdate;
  try
    StylesCmb.Items.Clear;
    { LCL does not support TStyleManager.StyleNames.
      Show a single entry indicating native OS theming is in use. }
    StylesCmb.Items.Add('Default (System)');
    StylesCmb.ItemIndex := 0;
  finally
    StylesCmb.Items.EndUpdate;
  end;
end;

end.
