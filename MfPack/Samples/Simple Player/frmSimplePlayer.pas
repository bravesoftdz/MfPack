

{Project searchpath:
 ..\MfPack\MediaFoundation;
 ..\MfPack\Shared;
 ..\MfPack\DirectX
}

unit frmSimplePlayer;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Variants,
  System.Classes,
  System.Win.ComObj,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.Menus,
  {MfPack}
  MfPack.MfApi,
  MfPack.MfPlay,
  MfPack.MfError,
  MfPack.ObjBase,
  MfPack.ComBaseApi,
  MfPack.MfpUtils,
  MfPack.MfpTypes;

type

////////////////////////////////////////////////////////////////////////////////
  TMediaPlayerCallback = class(TInterfacedPersistent, IMFPMediaPlayerCallback)
  private
    // IMFPMediaPlayerCallback methods
    procedure OnMediaPlayerEvent(var pEventHeader: MFP_EVENT_HEADER); stdcall;

  public
    constructor Create();  virtual;
    destructor Destroy(); override;

  end;

////////////////////////////////////////////////////////////////////////////////

  TForm1 = class(TForm)
    MainMenu1: TMainMenu;
    File1: TMenuItem;
    OpenFile1: TMenuItem;
    Exit1: TMenuItem;
    dlgOpenFile: TOpenDialog;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormPaint(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure OpenFile1Click(Sender: TObject);
    procedure Exit1Click(Sender: TObject);

  private
    { Private declarations }
    AppHandle: HWND;

    function PlayMediaFile(const hApp: HWND; const sURL: LPCWSTR): HResult;
    procedure WMSize(var Msg: TMessage); message WM_SIZE;

  public
    { Public declarations }


  end;

    procedure OnMediaItemCreated(pEvent: PMFP_MEDIAITEM_CREATED_EVENT);
    procedure OnMediaItemSet(pEvent: PMFP_MEDIAITEM_SET_EVENT);
    procedure ShowErrorMessage(fmt: string; hrErr: HResult);


var
  Form1: TForm1;

  // Global variables
  g_pPlayer: IMFPMediaPlayer;        // The MFPlay player object.
  g_pPlayerCB: IMFPMediaPlayerCallback; // Application callback object.
  g_bHasVideo: BOOL;

implementation

{$R *.dfm}

// TMediaPlayerCallback class //////////////////////////////////////////////////

constructor TMediaPlayerCallback.Create();
begin
  inherited Create();
end;

destructor TMediaPlayerCallback.Destroy();
begin
  inherited Destroy();
end;

//-------------------------------------------------------------------
// OnMediaPlayerEvent
//
// Implements IMFPMediaPlayerCallback.OnMediaPlayerEvent.
// This callback method handles events from the MFPlay object.
//-------------------------------------------------------------------
procedure TMediaPlayerCallback.OnMediaPlayerEvent(var pEventHeader: MFP_EVENT_HEADER);
begin
  if Failed(pEventHeader.hrEvent) then
    begin
      ShowErrorMessage('Playback error', pEventHeader.hrEvent);
      Exit;
    end;

  case (pEventHeader.eEventType) of
    MFP_EVENT_TYPE_MEDIAITEM_CREATED:
      begin
        OnMediaItemCreated(MFP_GET_MEDIAITEM_CREATED_EVENT(@pEventHeader));
      end;

    MFP_EVENT_TYPE_MEDIAITEM_SET:
      begin
        OnMediaItemSet(MFP_GET_MEDIAITEM_SET_EVENT(@pEventHeader));
      end;
  end;
end;


// Form class //////////////////////////////////////////////////////////////////

procedure TForm1.WMSize(var Msg: TMessage);
begin
  Inherited;  // OnResize method will be handled first
  if (Msg.wParam = SIZE_RESTORED) then
    if Assigned(g_pPlayer) then
      begin
        // Resize the video.
        g_pPlayer.UpdateVideo();
      end;
end;


procedure TForm1.Exit1Click(Sender: TObject);
begin
  Close;
end;


procedure TForm1.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := False;

  if Assigned(g_pPlayer) then
    begin
      g_pPlayer.Shutdown();
      SafeRelease(g_pPlayer);
    end;

  if Assigned(g_pPlayerCB) then
    begin
      SafeRelease(g_pPlayerCB);
    end;

  CanClose := True;
end;


procedure TForm1.FormCreate(Sender: TObject);
begin
  AppHandle := Handle;
  g_bHasVideo := False;
end;


procedure TForm1.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  hr: HResult;
  state: MFP_MEDIAPLAYER_STATE;

begin
  hr := S_OK;

  case Key of
    VK_SPACE:   // Toggle between playback and paused/stopped.
                begin
                  if Assigned(g_pPlayer) then
                    begin
                      state := MFP_MEDIAPLAYER_STATE_EMPTY;
                      hr := g_pPlayer.GetState(state);
                      if Succeeded(hr) then
                        begin
                          if (state = MFP_MEDIAPLAYER_STATE_PAUSED) or (state = MFP_MEDIAPLAYER_STATE_STOPPED) then
                            hr := g_pPlayer.Play();
                        end
                      else if (state = MFP_MEDIAPLAYER_STATE_PLAYING) then
                        begin
                          hr := g_pPlayer.Pause();
                        end;
                    end;
                end;
  end;

  if Failed(hr) then
    ShowErrorMessage('Playback Error', hr);
end;


procedure TForm1.FormPaint(Sender: TObject);
var
  ps: PAINTSTRUCT;
  hadc: HDC;

begin

  {todo}exit;

  hadc := BeginPaint(AppHandle, ps);
  if (Assigned(g_pPlayer) and g_bHasVideo) then
    begin
      // Playback has started and there is video.
      // Do not draw the window background, because the video
      // frame fills the entire client area.
      g_pPlayer.UpdateVideo();
    end
  else
    begin
      // There is no video stream, or playback has not started.
      // Paint the entire client area.
      FillRect(hadc,
               ps.rcPaint,
               HBRUSH(COLOR_WINDOW +1));
    end;

    EndPaint(hadc, ps);
end;


procedure TForm1.OpenFile1Click(Sender: TObject);
var
  hr: HResult;
  pwszFilePath: PWideChar;

begin
  hr := S_OK;
  if dlgOpenFile.Execute then
    begin
      pwszFilePath := PWideChar(dlgOpenFile.FileName);
      // Open the media file.
      hr := PlayMediaFile(AppHandle, pwszFilePath);
    end;

  if Failed(hr) then
    ShowErrorMessage('Could not open file.', hr);
end;


//-------------------------------------------------------------------
// PlayMediaFile
//
// Plays a media file, using the IMFPMediaPlayer interface.
//-------------------------------------------------------------------

function TForm1.PlayMediaFile(const hApp: HWND; const sURL: LPCWSTR): HResult;
var
  hr: HResult;
  pMediaItem: IMFPMediaItem;

label
  done;

begin

  // Create the MFPlayer object.
  if not Assigned(g_pPlayer) then
    begin
      g_pPlayerCB := TMediaPlayerCallback.Create();

      if not Assigned(g_pPlayerCB) then
        begin
          hr := E_OUTOFMEMORY;
          goto done;
        end;

      hr := MFPCreateMediaPlayer(Nil,            // Mediafile path
                                 False,          // Start playback automatically?
                                 0,              // Flags
                                 g_pPlayerCB,    // Callback pointer
                                 hApp,           // Video window
                                 g_pPlayer       // The player
                                 );

      if Failed(hr) then
        goto done;
    end;

  // Create a new media item for this URL.
 hr := g_pPlayer.CreateMediaItemFromURL(sURL,
                                        False,
                                        0,
                                        Nil);

  // The CreateMediaItemFromURL method completes asynchronously.
  // The application will receive an MFP_EVENT_TYPE_MEDIAITEM_CREATED
  // event. See MediaPlayerCallback.OnMediaPlayerEvent().

done:

  Result := hr;

end;

//-------------------------------------------------------------------
// OnMediaItemCreated
//
// Called when the IMFPMediaPlayer.CreateMediaItemFromURL method
// completes.
//-------------------------------------------------------------------
procedure OnMediaItemCreated(pEvent: PMFP_MEDIAITEM_CREATED_EVENT);
var
  hr: HResult;
  bHasVideo,
  bIsSelected: BOOL;

label
  done;

begin
  hr := S_OK;
  // The media item was created successfully.

  if Assigned(g_pPlayer) then
    begin
      bHasVideo := False;
      bIsSelected := False;

      // Check if the media item contains video.
      hr := pEvent.pMediaItem.HasVideo(bHasVideo, bIsSelected);

      if Failed(hr) then goto done;

      g_bHasVideo := bHasVideo and bIsSelected;

      // Set the media item on the player. This method completes asynchronously.
      hr := g_pPlayer.SetMediaItem(pEvent.pMediaItem);
    end;

done:
  if Failed(hr) then
    ShowErrorMessage('Error playing this file.', hr);

end;


//-------------------------------------------------------------------
// OnMediaItemSet
//
// Called when the IMFPMediaPlayer.SetMediaItem method completes.
//-------------------------------------------------------------------
procedure OnMediaItemSet(pEvent: PMFP_MEDIAITEM_SET_EVENT);
var
  hr: HResult;

begin
  hr := g_pPlayer.Play();

  if Failed(hr) then
    ShowErrorMessage('IMFPMediaPlayer.Play failed.', hr);
end;


procedure ShowErrorMessage(fmt: string; hrErr: HResult);
var
  msg: string;

begin
  msg := Format('%s Resultcode: (%d)', [fmt, hrErr]);

  MessageBox(0,
             LPCWSTR(msg),
             LPCWSTR('Error'),
             MB_ICONERROR);
end;


// initialization and finalization /////////////////////////////////////////////

initialization
begin
  // Initialize Media Foundation platform
  //if Succeeded(MFStartup(MF_VERSION)) then
    CoInitializeEx(Nil,
                   COINIT_APARTMENTTHREADED or COINIT_DISABLE_OLE1DDE)
  //else
  //  Abort();
end;


finalization
begin
  // Shutdown MF
  //MFShutdown();
  CoUninitialize();
end;

end.
