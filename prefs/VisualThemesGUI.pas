unit VisualThemesGUI;

{$mode delphi}

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls;

type
  TVisualThemesFrm = class(TForm)
    SaveAndExitBtn: TButton;
    StylesCmb: TComboBox;
    Label1: TLabel;
    DefaultThemeBtn: TButton;
    ThemesOffBtn: TButton;
    procedure SaveAndExitBtnClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure DefaultThemeBtnClick(Sender: TObject);
    procedure StylesCmbChange(Sender: TObject);
    procedure ThemesOffBtnClick(Sender: TObject);
  private
    { Private-Deklarationen }
  public
    { Public-Deklarationen }
  end;

var
  VisualThemesFrm: TVisualThemesFrm;

implementation

{$R *.dfm}

uses
  FileHandling;

{ Note: Vcl.Themes / TStyleManager is not available in LCL (Lazarus).
  LCL applications use native OS widget themes automatically.
  This form is kept functional but theme selection is disabled. }

procedure TVisualThemesFrm.SaveAndExitBtnClick(Sender: TObject);
begin
  SaveIni(True);
  LoadIni;
  Visible := False;
end;

procedure TVisualThemesFrm.StylesCmbChange(Sender: TObject);
begin
  { TStyleManager.TrySetStyle is not available in LCL.
    LCL uses native OS themes automatically. }
end;

procedure TVisualThemesFrm.ThemesOffBtnClick(Sender: TObject);
begin
  StylesCmb.ItemIndex := 0;
end;

procedure TVisualThemesFrm.DefaultThemeBtnClick(Sender: TObject);
begin
  StylesCmb.ItemIndex := 0;
end;

procedure TVisualThemesFrm.FormShow(Sender: TObject);
begin
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
