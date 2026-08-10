; ----------------------------------------------------------------
; WinBoost v4.0 - Inno Setup 6 Script
; ----------------------------------------------------------------
; Como usar:
;   1. Ejecutar Build.ps1 primero para generar la carpeta dist\
;   2. Abrir este archivo con Inno Setup 6 y compilar
;      (o: iscc.exe installer\WinBoost.iss desde la raiz)
;   3. El instalador se genera en installer\Output\
; ----------------------------------------------------------------

#define AppName      "WinBoost"
#define AppVersion   "4.1"
#define AppPublisher "WinBoost"
#define AppExeName   "WinBoost.exe"
#define AppXamlName  "OptimizarPC_UI.xaml"

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
ArchitecturesInstallIn64BitMode=x64
CloseApplications=yes
RestartApplications=no
UsePreviousAppDir=yes

; Icono del instalador (opcional - descomenta si tenes WinBoost.ico)
; SetupIconFile=..\WinBoost.ico

; Firma del instalador (opcional - requiere Inno Setup + signtool)
; SignTool=...

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Files]
; Ejecutable principal
Source: "..\dist\{#AppExeName}";  DestDir: "{app}"; Flags: ignoreversion
; Interfaz XAML (debe estar junto al exe)
Source: "..\dist\{#AppXamlName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Menu inicio
Name: "{group}\{#AppName}";                    Filename: "{app}\{#AppExeName}"
Name: "{group}\Desinstalar {#AppName}";        Filename: "{uninstallexe}"
; Escritorio (solo si el usuario lo elige)
Name: "{autodesktop}\{#AppName}";              Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Crear acceso directo en el escritorio"; \
    GroupDescription: "Opciones adicionales:"; Flags: unchecked

[Run]
Filename: "{app}\{#AppExeName}"; \
    Description: "Ejecutar {#AppName} ahora"; \
    Flags: nowait postinstall shellexec skipifsilent

[UninstallRun]
; Nada especial al desinstalar

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
