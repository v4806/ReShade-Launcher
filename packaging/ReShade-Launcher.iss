; ReShade Launcher installer.

#define MyAppName "ReShade Launcher"
#ifndef MyAppVersion
#define MyAppVersion "3.0.0"
#endif
#define MyAppURL "https://github.com/v4806/ReShade-Launcher/tree/main"
#define MyAppExeName "ReShade Launcher Build.exe"
#define MyProjectDir AddBackslash(SourcePath) + ".."
#define MySourceDir AddBackslash(MyProjectDir) + "dist\ReShade Launcher"
#define MyDefaultsDir AddBackslash(MyProjectDir) + "dist\ReShade Launcher Defaults"
#define MyOutputDir AddBackslash(MyProjectDir) + "dist\release"

[Setup]
AppId={{6243EE4E-D17B-43B7-A096-99C7B567A61A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName=C:\{#MyAppName}
UsePreviousAppDir=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
PrivilegesRequiredOverridesAllowed=commandline
OutputDir={#MyOutputDir}
OutputBaseFilename=ReShade-Launcher-installer-v{#MyAppVersion}
SetupIconFile={#MySourceDir}\icon.ico
VersionInfoVersion={#MyAppVersion}.0
VersionInfoProductVersion={#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern dark
CloseApplications=no
DisableFinishedPage=no
CreateUninstallRegKey=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Languages\English.isl"
Name: "chinesesimp"; MessagesFile: "ChineseSimplified.isl"
Name: "chinesetraditional"; MessagesFile: "compiler:Languages\ChineseTraditional.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "portuguese"; MessagesFile: "compiler:Languages\Portuguese.isl"

[CustomMessages]
chinesesimp.InstallInstructions=安装说明
chinesetraditional.InstallInstructions=安裝說明
english.InstallInstructions=Installation Instructions
japanese.InstallInstructions=インストール説明
korean.InstallInstructions=설치 안내
russian.InstallInstructions=Инструкции по установке
german.InstallInstructions=Installationsanleitung
french.InstallInstructions=Instructions d'installation
spanish.InstallInstructions=Instrucciones de instalación
portuguese.InstallInstructions=Instruções de instalação
brazilianportuguese.InstallInstructions=Instruções de instalação

chinesesimp.ShortcutInstructions=快捷键说明
chinesetraditional.ShortcutInstructions=快捷鍵說明
english.ShortcutInstructions=Shortcut Instructions
japanese.ShortcutInstructions=ショートカット説明
korean.ShortcutInstructions=단축키 안내
russian.ShortcutInstructions=Инструкции по сочетаниям клавиш
german.ShortcutInstructions=Kurzbefehle Anweisungen
french.ShortcutInstructions=Instructions des raccourcis
spanish.ShortcutInstructions=Instrucciones de atajos
portuguese.ShortcutInstructions=Instruções de atalhos
brazilianportuguese.ShortcutInstructions=Instruções de atalhos

chinesesimp.UninstallProgram=卸载 {#MyAppName}
chinesetraditional.UninstallProgram=卸載 {#MyAppName}
english.UninstallProgram=Uninstall {#MyAppName}
japanese.UninstallProgram={#MyAppName} をアンインストール
korean.UninstallProgram={#MyAppName} 제거
russian.UninstallProgram=Деинсталлировать {#MyAppName}
german.UninstallProgram={#MyAppName} deinstallieren
french.UninstallProgram=Désinstaller {#MyAppName}
spanish.UninstallProgram=Desinstalar {#MyAppName}
portuguese.UninstallProgram=Desinstalar {#MyAppName}
brazilianportuguese.UninstallProgram=Desinstalar {#MyAppName}

[InstallDelete]
Type: files; Name: "{commondesktop}\ReShade Build.lnk"
Type: files; Name: "{commondesktop}\ReShade debug.lnk"
Type: files; Name: "{group}\*.lnk"
; Remove the old Python runtime and obsolete top-level shader copies on upgrade.
; User data under launch_config, custom_data, Presets, Mods and reshade_shaders is untouched.
Type: filesandordirs; Name: "{app}\_internal"
Type: filesandordirs; Name: "{app}\ReShade\Shaders"
Type: filesandordirs; Name: "{app}\ReShade\Textures"
Type: files; Name: "{app}\ReShade\full.zip"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Dirs]
Name: "{app}\MOD_loader"

[Files]
; Program payload: these files are always replaced on upgrade.
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; Preserved content: only seed defaults when a user copy does not already exist.
Source: "{#MyDefaultsDir}\ReShade\Presets\*"; DestDir: "{app}\ReShade\Presets"; Flags: onlyifdoesntexist uninsneveruninstall recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "{#MyDefaultsDir}\ReShade\reshade_shaders\*"; DestDir: "{app}\ReShade\reshade_shaders"; Flags: onlyifdoesntexist uninsneveruninstall recursesubdirs createallsubdirs skipifsourcedoesntexist

; Installation help is selected by the setup language.
Source: "{#MySourceDir}\README\instructions_chs.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: chinesesimp; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_chs.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: chinesesimp; Flags: ignoreversion
Source: "{#MySourceDir}\README\instructions_cht.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: chinesetraditional; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_cht.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: chinesetraditional; Flags: ignoreversion
Source: "{#MySourceDir}\README\instructions_en.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: english; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_en.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: english; Flags: ignoreversion
Source: "{#MySourceDir}\README\instructions_jp.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: japanese; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_jp.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: japanese; Flags: ignoreversion
Source: "{#MySourceDir}\README\instructions_kr.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: korean; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_kr.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: korean; Flags: ignoreversion
Source: "{#MySourceDir}\README\instructions_ru.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: russian; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_ru.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: russian; Flags: ignoreversion
Source: "{#MySourceDir}\README\instructions_de.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: german; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_de.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: german; Flags: ignoreversion
Source: "{#MySourceDir}\README\instructions_fr.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: french; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_fr.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: french; Flags: ignoreversion
Source: "{#MySourceDir}\README\instructions_es.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: spanish; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_es.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: spanish; Flags: ignoreversion
Source: "{#MySourceDir}\README\instructions_pt.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: portuguese; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_pt.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: portuguese; Flags: ignoreversion
Source: "{#MySourceDir}\README\instructions_pt.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: brazilianportuguese; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_pt.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: brazilianportuguese; Flags: ignoreversion

Source: "{#MySourceDir}\README\instructions_chs.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\shortcuts_chs.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\instructions_cht.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\shortcuts_cht.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\instructions_en.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\shortcuts_en.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\instructions_jp.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\shortcuts_jp.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\instructions_kr.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\shortcuts_kr.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\instructions_ru.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\shortcuts_ru.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\instructions_de.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\shortcuts_de.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\instructions_fr.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\shortcuts_fr.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\instructions_es.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\shortcuts_es.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\instructions_pt.txt"; Flags: dontcopy ignoreversion
Source: "{#MySourceDir}\README\shortcuts_pt.txt"; Flags: dontcopy ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\ReShade Debug"; Filename: "{app}\ReShade Debug.exe"
Name: "{group}\{cm:ProgramOnTheWeb,{#MyAppName}}"; Filename: "{#MyAppURL}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\ReShade Build"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent runascurrentuser

[Code]
var
  InfoBeforePage: TWizardPage;
  InfoAfterPage: TWizardPage;

function GetLanguageSuffix(LangCode: string): string;
begin
  case LangCode of
    'chinesesimp': Result := 'chs';
    'chinesetraditional': Result := 'cht';
    'english': Result := 'en';
    'japanese': Result := 'jp';
    'korean': Result := 'kr';
    'russian': Result := 'ru';
    'german': Result := 'de';
    'french': Result := 'fr';
    'spanish': Result := 'es';
    'brazilianportuguese': Result := 'pt';
    'portuguese': Result := 'pt';
  else
    Result := 'en';
  end;
end;
function ReadInternalFile(const FileName: string): string;
var
  TempFile: string;
  Lines: TArrayOfString;
  Index: Integer;
begin
  TempFile := ExpandConstant('{tmp}\' + FileName);
  ExtractTemporaryFile(FileName);
  Result := '';
  if LoadStringsFromFile(TempFile, Lines) then
  begin
    for Index := 0 to GetArrayLength(Lines) - 1 do
    begin
      if Index > 0 then
        Result := Result + #13#10;
      Result := Result + Lines[Index];
    end;
  end
  else
    Result := '无法加载文件: ' + FileName;
  DeleteFile(TempFile);
end;

procedure InitializeWizard;
var
  Memo: TMemo;
  InfoFile: string;
begin
  InfoFile := 'instructions_' + GetLanguageSuffix(ActiveLanguage) + '.txt';
  InfoBeforePage := CreateCustomPage(wpWelcome, CustomMessage('InstallInstructions'), '');
  Memo := TMemo.Create(InfoBeforePage);
  with Memo do
  begin
    Parent := InfoBeforePage.Surface;
    ScrollBars := ssVertical;
    ReadOnly := True;
    Left := ScaleX(0);
    Top := ScaleY(0);
    Width := InfoBeforePage.SurfaceWidth;
    Height := InfoBeforePage.SurfaceHeight;
    Text := ReadInternalFile(InfoFile);
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
var
  Memo: TMemo;
  InfoFile: string;
begin
  if (CurPageID = wpInstalling) and (InfoAfterPage = nil) then
  begin
    InfoFile := 'shortcuts_' + GetLanguageSuffix(ActiveLanguage) + '.txt';
    InfoAfterPage := CreateCustomPage(wpInstalling, CustomMessage('ShortcutInstructions'), '');
    Memo := TMemo.Create(InfoAfterPage);
    with Memo do
    begin
      Parent := InfoAfterPage.Surface;
      ScrollBars := ssVertical;
      ReadOnly := True;
      Left := ScaleX(0);
      Top := ScaleY(0);
      Width := InfoAfterPage.SurfaceWidth;
      Height := InfoAfterPage.SurfaceHeight;
      Text := ReadInternalFile(InfoFile);
    end;
  end;
end;
