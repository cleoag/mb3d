unit FTGifAnimate;

{$mode delphi}
(******************************************************************************
Unit to make an animated GIF.
Author: Finn Tolderlund
        Denmark
Date: 14.07.2003

homepage:
http://www.tolderlund.eu/
e-mail:
finn@tolderlund.eu

This unit requires the GIFImage.pas unit from Anders Melander.
The GIFImage.pas unit can be obtained from my homepage above.

This unit can freely be used and distributed.

Disclaimer:
Use of this unit is on your own responsibility.
I will not under any circumstance be held responsible for anything
which may or may not happen as a result of using this unit.
******************************************************************************
History:
19.07.2003  Added GifAnimateEndGif function.
24.07.2003  Added link to an example Delphi project at Earl F. Glynn's website.
02.09.2003  Renamed function GifAnimateEnd to GifAnimateEndPicture.
            Added overloaded function GifAnimateAddImage where you can specify
            a specific TransparentColor.
22.08.2008  Added new overloaded function GifAnimateAddImage with Loops and Disposal parameter.
23.08.2008  Added new overloaded function GifAnimateAddImage with TGIFAppExtNSLoop and TGIFGraphicControlExtension parameter.
25.09.2008  Added new overloaded function GifAnimateBegin with Width and Height parameter.
19.10.2008  Posted this new version on my web site.
******************************************************************************)
(******************************************************************************
Example of use:

procedure TFormSphereMovie.MakeGifButtonClick(Sender: TObject);
// BitMapArray is an array of TBitmap.
var
  FrameIndex: Integer;
  Picture: TPicture;
begin
  Screen.Cursor := crHourGlass;
  try
    GifAnimateBegin;
    {Step through each frame in in-memory list}
    for FrameIndex := Low(BitMapArray) to High(BitMapArray) do
    begin
      // add frame to animated gif
      GifAnimateAddImage(BitMapArray[FrameIndex], False, MillisecondsPerFrame);
    end;
    // We are using a TPicture but we could have used a TGIFImage instead.
    // By not using TGIFImage directly we do not have to add GIFImage to the uses clause.
    // By using TPicture we only need to add GifAnimate to the uses clause.
    Picture := GifAnimateEndPicture;
    Picture.SaveToFile(ExtractFilePath(ParamStr(0)) + 'sphere.gif');  // save gif
    ImageMovieFrame.Picture.Assign(Picture);  // display gif
    Picture.Free;
  finally
    Screen.Cursor := crDefault;
  end;
end;
******************************************************************************)
(******************************************************************************
For a complete Delphi project with source, goto one of these pages:
http://homepages.borland.com/efg2lab/Graphics/SphereInCubeMovie.htm
http://www.efg2.com/Lab/Graphics/SphereInCubeMovie.htm
******************************************************************************)

interface

uses
  Windows, SysUtils, Graphics;

{ GIF animation export is disabled. Anders Melander's GIFImage is not available.
  Basic overloads are provided so that calling code compiles, but they produce no output. }
type
  TGIFImage = class(TGraphic)
  end;

procedure GifAnimateBegin; overload;

procedure GifAnimateBegin(Width, Height: Integer); overload;

function GifAnimateEndPicture: TPicture;

function GifAnimateEndGif: TGIFImage;

function GifAnimateAddImage(Source: TGraphic; Transparent: Boolean; DelayMS: Word): Integer; overload;
// Transparent=True uses lower left pixel as transparent color

function GifAnimateAddImage(Source: TGraphic; TransparentColor: TColor; DelayMS: Word): Integer; overload;
// TransparentColor<>-1 uses that color as the transparent.
// Note: There is no guaranteee that the color will actually be in the GIF's color palette.

implementation

{ Stub implementations - GIF animation not available }

procedure GifAnimateBegin;
begin
  // GIF animation not available in FPC build
end;

procedure GifAnimateBegin(Width, Height: Integer);
begin
  // GIF animation not available in FPC build
end;

function GifAnimateEndPicture: TPicture;
begin
  Result := TPicture.Create;
end;

function GifAnimateEndGif: TGIFImage;
begin
  Result := TGIFImage.Create;
end;

function GifAnimateAddImage(Source: TGraphic; Transparent: Boolean; DelayMS: Word): Integer;
begin
  Result := -1;
end;

function GifAnimateAddImage(Source: TGraphic; TransparentColor: TColor; DelayMS: Word): Integer;
begin
  Result := -1;
end;

end.
