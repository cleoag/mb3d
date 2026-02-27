unit SpeedButtonEx;

{$mode delphi}

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms,
  Dialogs, ExtCtrls, Buttons;

type
  TSpeedButtonEx = class (TSpeedButton)
  private
    { Private declarations }
{$IFNDEF FPC}
    { In LCL, TControl already provides OnMouseEnter/OnMouseLeave
      and the corresponding CM_MOUSEENTER/CM_MOUSELEAVE handling.
      We only need this custom implementation for Delphi VCL. }
    FOnMouseLeave: TNotifyEvent;
    FOnMouseEnter: TNotifyEvent;
    procedure CMMouseEnter(var msg: TMessage);
      message CM_MOUSEENTER;
    procedure CMMouseLeave(var msg: TMessage);
      message CM_MOUSELEAVE;
{$ENDIF}
  protected
    { Protected declarations }
{$IFNDEF FPC}
    procedure DoMouseEnter; dynamic;
    procedure DoMouseLeave; dynamic;
{$ENDIF}
  public
    { Public declarations }
  published
    { Published declarations }
{$IFNDEF FPC}
    property OnMouseEnter: TNotifyEvent read FOnMouseEnter write FOnMouseEnter;
    property OnMouseLeave: TNotifyEvent read FOnMouseLeave write FOnMouseLeave;
{$ENDIF}
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('Additional', [TSpeedButtonEx]);
end;

{$IFNDEF FPC}
procedure TSpeedButtonEx.CMMouseEnter(var msg: TMessage);
begin
  DoMouseEnter;
end;

procedure TSpeedButtonEx.CMMouseLeave(var msg: TMessage);
begin
  DoMouseLeave;
end;

procedure TSpeedButtonEx.DoMouseEnter;
begin
  if Assigned(FOnMouseEnter) then FOnMouseEnter(Self);
end;

procedure TSpeedButtonEx.DoMouseLeave;
begin
  if Assigned(FOnMouseLeave) then FOnMouseLeave(Self);
end;
{$ENDIF}

end.
