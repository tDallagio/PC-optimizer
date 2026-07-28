; ----------------------------------------------------------------
; WinBoost (C#/WPF) - Inno Setup 6 Script
; ----------------------------------------------------------------
; Instalador para la version C# self-contained single-file. NO reemplaza
; installer\WinBoost.iss (ese sigue siendo el instalador de la version PS1
; distribuida hasta el corte, ver docs/PENDIENTES.md item 6.3).
;
; Como usar:
;   1. Ejecutar src-csharp\Publish-CSharp.ps1 primero (genera
;      src-csharp\WinBoost\bin\publish\win-x64\WinBoost.exe)
;   2. iscc.exe src-csharp\installer\WinBoost.iss /DAppVersion=4.1
;      (Publish-CSharp.ps1 ya hace este paso automaticamente)
;   3. El instalador se genera en src-csharp\installer\Output\
;
; Mismo AppId que installer\WinBoost.iss (PS1): a proposito, para que cuando
; el auto-updater (UpdateService.ApplyUpdate) instale esta version sobre una
; instalacion previa de WinBoost (PS1 o C#), Inno Setup lo reconozca como
; upgrade del mismo producto -> misma carpeta de instalacion, mismo registro
; de Add/Remove Programs, sin entradas duplicadas.
; ----------------------------------------------------------------

#define AppName      "WinBoost"
#define AppPublisher "WinBoost"
#define AppExeName   "WinBoost.exe"

; AppVersion se pasa desde afuera con /DAppVersion=X.Y (Publish-CSharp.ps1 lo
; hace leyendo App.Version de App.xaml.cs). Default solo para compilar suelto
; a mano sin olvidarse del /D.
#ifndef AppVersion
  #define AppVersion "0.0-dev"
#endif

[Setup]
AppId={{B8E4F2A1-7C3D-4E5F-A9B2-1D6E8F3C7A04}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=
AppSupportURL=
AppUpdatesURL=
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=WinBoost_Setup_{#AppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
UsePreviousAppDir=yes
SetupIconFile=..\..\WinBoost.ico
UninstallDisplayIcon={app}\{#AppExeName}

; Firma del instalador (opcional - requiere Inno Setup + signtool)
; SignTool=...

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Files]
; Single-file self-contained: un solo ejecutable, sin XAML ni DLLs sueltas.
Source: "..\WinBoost\bin\publish\win-x64\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}";                    Filename: "{app}\{#AppExeName}"
Name: "{group}\Desinstalar {#AppName}";        Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";              Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Crear acceso directo en el escritorio"; \
    GroupDescription: "Opciones adicionales:"; Flags: unchecked

[Run]
Filename: "{app}\{#AppExeName}"; \
    Description: "Ejecutar {#AppName} ahora"; \
    Flags: nowait postinstall shellexec skipifsilent

[UninstallDelete]
; Limpia el WinBoost.exe legacy (PS1/ps2exe) y el XAML suelto que dejaba el
; instalador viejo si esta instalacion pisa una instalada con installer\WinBoost.iss.
Type: files; Name: "{app}\OptimizarPC_UI.xaml"

[Code]
// Verificar que el sistema operativo sea Windows 10 o superior
function InitializeSetup(): Boolean;
var
  Version: TWindowsVersion;
begin
  GetWindowsVersionEx(Version);
  Result := True;
  if (Version.Major < 10) then begin
    MsgBox('WinBoost requiere Windows 10 o superior.', mbError, MB_OK);
    Result := False;
  end;
end;

// Si esta instalacion pisa una instalacion previa hecha con el instalador
// PS1 (installer\WinBoost.iss), ese dejaba WinBoost.exe + OptimizarPC_UI.xaml
// en la misma carpeta ({app}, mismo AppId). El [Files] de aca solo declara
// el .exe nuevo, asi que el .xaml viejo quedaria huerfano; se borra apenas
// termina de copiar los archivos nuevos.
procedure CurStepChanged(CurStep: TSetupStep);
var
  OrphanXaml: String;
begin
  if CurStep = ssPostInstall then begin
    OrphanXaml := ExpandConstant('{app}\OptimizarPC_UI.xaml');
    if FileExists(OrphanXaml) then
      DeleteFile(OrphanXaml);
  end;
end;
