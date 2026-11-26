; 脚本由 Inno Setup 脚本向导生成。
; 有关创建 Inno Setup 脚本文件的详细信息，请参阅帮助文档！
; 仅供非商业使用

#define MyAppName "ReShade Launcher"
#define MyAppVersion "2.6.3"
#define MyAppURL "https://github.com/v4806/ReShade-Launcher/tree/main"
#define MyAppExeName "ReShade Launcher Build.exe"
#define MyProjectDir AddBackslash(SourcePath) + ".."
#define MySourceDir AddBackslash(MyProjectDir) + "dist\ReShade Launcher"
#define MyBundledLoaderDir AddBackslash(MyProjectDir) + "MOD_loader\AzurPromilia"

[Setup]
AppId={{6243EE4E-D17B-43B7-A096-99C7B567A61A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName=C:\{#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
PrivilegesRequiredOverridesAllowed=commandline
OutputDir=D:\inno打包\ReShade
OutputBaseFilename=ReShade-Launcher-installer-v2.6.3
SetupIconFile={#MySourceDir}\icon.ico
SolidCompression=yes
WizardStyle=modern dark
DisableFinishedPage=no
CreateUninstallRegKey=yes

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Default.isl"
Name: "chinesetraditional"; MessagesFile: "compiler:Languages\ChineseTraditional.isl"
Name: "english"; MessagesFile: "compiler:Languages\English.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[CustomMessages]
; 安装说明页面标题
chinesesimp.InstallInstructions=安装说明
chinesetraditional.InstallInstructions=安裝說明
english.InstallInstructions=Installation Instructions
japanese.InstallInstructions=インストール説明
korean.InstallInstructions=설치 안내
russian.InstallInstructions=Инструкции по установке
german.InstallInstructions=Installationsanleitung
french.InstallInstructions=Instructions d'installation

; 快捷键说明页面标题
chinesesimp.ShortcutInstructions=快捷键说明
chinesetraditional.ShortcutInstructions=快捷鍵說明
english.ShortcutInstructions=Shortcut Instructions
japanese.ShortcutInstructions=ショートカット説明
korean.ShortcutInstructions=단축키 안내
russian.ShortcutInstructions=Инструкции по сочетаниям клавиш
german.ShortcutInstructions=Kurzbefehle Anweisungen
french.ShortcutInstructions=Instructions des raccourcis

; 卸载提示
chinesesimp.UninstallOldVersionPrompt=检测到已安装的旧版本 ReShade Launcher。是否先卸载旧版本？
chinesetraditional.UninstallOldVersionPrompt=偵測到已安裝的舊版本 ReShade Launcher。是否先卸載舊版本？
english.UninstallOldVersionPrompt=Detected an older version of ReShade Launcher. Do you want to uninstall the old version first?
japanese.UninstallOldVersionPrompt=古いバージョンの ReShade Launcher が検出されました。先に古いバージョンをアンインストールしますか？
korean.UninstallOldVersionPrompt=이전 버전의 ReShade Launcher이(가) 감지되었습니다. 먼저 이전 버전을 제거하시겠습니까?
russian.UninstallOldVersionPrompt=Обнаружена старая версия ReShade Launcher. Хотите сначала удалить старую версию?
german.UninstallOldVersionPrompt=Eine ältere Version von ReShade Launcher wurde erkannt. Möchten Sie zuerst die alte Version deinstallieren?
french.UninstallOldVersionPrompt=Une ancienne version de ReShade Launcher a été détectée. Voulez-vous d'abord désinstaller l'ancienne version?

chinesesimp.UninstallError=卸载旧版本时出错。请手动卸载旧版本后再继续安装。
chinesetraditional.UninstallError=卸載舊版本時出錯。請手動卸載舊版本後再繼續安裝。
english.UninstallError=Error while uninstalling the old version. Please uninstall the old version manually and then continue.
japanese.UninstallError=古いバージョンのアンインストール中にエラーが発生しました。手動で古いバージョンをアンインストールしてから続行してください。
korean.UninstallError=이전 버전 제거 중 오류가 발생했습니다. 수동으로 이전 버전을 제거한 후 계속하십시오.
russian.UninstallError=Ошибка при удалении старой версии. Пожалуйста, удалите старую версию вручную, а затем продолжите.
german.UninstallError=Fehler beim Deinstallieren der alten Version. Bitte deinstallieren Sie die alte Version manuell und fahren Sie dann fort.
french.UninstallError=Erreur lors de la désinstallation de l'ancienne version. Veuillez désinstaller l'ancienne version manuellement, puis continuer.

chinesesimp.UninstallSuccess=旧版本已成功卸载，继续安装新版本。
chinesetraditional.UninstallSuccess=舊版本已成功卸載，繼續安裝新版本。
english.UninstallSuccess=The old version has been successfully uninstalled. Continuing with the new installation.
japanese.UninstallSuccess=古いバージョンが正常にアンインストールされました。新しいインストールを続行します。
korean.UninstallSuccess=이전 버전이 성공적으로 제거되었습니다. 새 설치를 계속합니다.
russian.UninstallSuccess=Старая версия успешно удалена. Продолжаем установку новой версии.
german.UninstallSuccess=Die alte Version wurde erfolgreich deinstalliert. Die neue Installation wird fortgesetzt.
french.UninstallSuccess=L'ancienne version a été désinstallée avec succès. Poursuite de la nouvelle installation.

; 卸载快捷方式名称
chinesesimp.UninstallProgram=卸载 {#MyAppName}
chinesetraditional.UninstallProgram=卸載 {#MyAppName}
english.UninstallProgram=Uninstall {#MyAppName}
japanese.UninstallProgram={#MyAppName} をアンインストール
korean.UninstallProgram={#MyAppName} 제거
russian.UninstallProgram=Деинсталлировать {#MyAppName}
german.UninstallProgram={#MyAppName} deinstallieren
french.UninstallProgram=Désinstaller {#MyAppName}

; 清空安装目录选项
chinesesimp.TaskCleanInstall=安装前清空目标目录
chinesetraditional.TaskCleanInstall=安裝前清空目標目錄
english.TaskCleanInstall=Clean destination directory before installing
japanese.TaskCleanInstall=インストール前にディレクトリをクリア
korean.TaskCleanInstall=설치 전 대상 디렉터리 비우기
russian.TaskCleanInstall=Очистить папку установки перед установкой
german.TaskCleanInstall=Zielverzeichnis vor der Installation leeren
french.TaskCleanInstall=Nettoyer le répertoire de destination avant l'installation
chinesesimp.TaskCleanInstallGroup=安装选项
chinesetraditional.TaskCleanInstallGroup=安裝選項
english.TaskCleanInstallGroup=Installation options
japanese.TaskCleanInstallGroup=インストールオプション
korean.TaskCleanInstallGroup=설치 옵션
russian.TaskCleanInstallGroup=Параметры установки
german.TaskCleanInstallGroup=Installationsoptionen
french.TaskCleanInstallGroup=Options d'installation

[InstallDelete]
Type: files; Name: "{commondesktop}\ReShade Build.lnk"
Type: files; Name: "{commondesktop}\ReShade debug.lnk"  
Type: files; Name: "{group}\*.lnk"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "cleaninstall"; Description: "{cm:TaskCleanInstall}"; GroupDescription: "{cm:TaskCleanInstallGroup}"; Flags: unchecked

[Files]
; 主程序文件 - 完整打包 ReShade-Launcher 目录下的所有内容
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; 蓝色星原内置 Mod 加载器
Source: "{#MyBundledLoaderDir}\*"; DestDir: "{app}\MOD_loader\AzurPromilia"; Flags: ignoreversion recursesubdirs createallsubdirs

; 不同语言的说明文件 - 安装到目标目录
; 简体中文
Source: "{#MySourceDir}\README\instructions_chs.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: chinesesimp; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_chs.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: chinesesimp; Flags: ignoreversion

; 繁体中文
Source: "{#MySourceDir}\README\instructions_cht.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: chinesetraditional; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_cht.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: chinesetraditional; Flags: ignoreversion

; 英文
Source: "{#MySourceDir}\README\instructions_en.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: english; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_en.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: english; Flags: ignoreversion

; 日文
Source: "{#MySourceDir}\README\instructions_jp.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: japanese; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_jp.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: japanese; Flags: ignoreversion

; 韩文
Source: "{#MySourceDir}\README\instructions_kr.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: korean; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_kr.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: korean; Flags: ignoreversion

; 俄文
Source: "{#MySourceDir}\README\instructions_ru.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: russian; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_ru.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: russian; Flags: ignoreversion

; 德文
Source: "{#MySourceDir}\README\instructions_de.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: german; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_de.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: german; Flags: ignoreversion

; 法文
Source: "{#MySourceDir}\README\instructions_fr.txt"; DestDir: "{app}\README"; DestName: "instructions.txt"; Languages: french; Flags: ignoreversion
Source: "{#MySourceDir}\README\shortcuts_fr.txt"; DestDir: "{app}\README"; DestName: "shortcuts.txt"; Languages: french; Flags: ignoreversion

; 将说明文本文件打包到安装程序内部（不安装到目标目录，仅供安装过程使用）
; 简体中文
Source: "{#MySourceDir}\README\instructions_chs.txt"; Flags: dontcopy ignoreversion; 
Source: "{#MySourceDir}\README\shortcuts_chs.txt"; Flags: dontcopy ignoreversion; 

; 繁体中文
Source: "{#MySourceDir}\README\instructions_cht.txt"; Flags: dontcopy ignoreversion; 
Source: "{#MySourceDir}\README\shortcuts_cht.txt"; Flags: dontcopy ignoreversion; 

; 英文
Source: "{#MySourceDir}\README\instructions_en.txt"; Flags: dontcopy ignoreversion; 
Source: "{#MySourceDir}\README\shortcuts_en.txt"; Flags: dontcopy ignoreversion; 

; 日文
Source: "{#MySourceDir}\README\instructions_jp.txt"; Flags: dontcopy ignoreversion; 
Source: "{#MySourceDir}\README\shortcuts_jp.txt"; Flags: dontcopy ignoreversion; 

; 韩文
Source: "{#MySourceDir}\README\instructions_kr.txt"; Flags: dontcopy ignoreversion; 
Source: "{#MySourceDir}\README\shortcuts_kr.txt"; Flags: dontcopy ignoreversion; 

; 俄文
Source: "{#MySourceDir}\README\instructions_ru.txt"; Flags: dontcopy ignoreversion; 
Source: "{#MySourceDir}\README\shortcuts_ru.txt"; Flags: dontcopy ignoreversion; 

; 德文
Source: "{#MySourceDir}\README\instructions_de.txt"; Flags: dontcopy ignoreversion; 
Source: "{#MySourceDir}\README\shortcuts_de.txt"; Flags: dontcopy ignoreversion; 

; 法文
Source: "{#MySourceDir}\README\instructions_fr.txt"; Flags: dontcopy ignoreversion; 
Source: "{#MySourceDir}\README\shortcuts_fr.txt"; Flags: dontcopy ignoreversion; 

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:ProgramOnTheWeb,{#MyAppName}}"; Filename: "{#MyAppURL}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\ReShade Build"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent runascurrentuser

[Code]
var
  InfoBeforePage: TWizardPage;
  InfoAfterPage: TWizardPage;
  InfoBeforeMemo: TMemo;
  InfoAfterMemo: TMemo;

// 获取卸载字符串
function GetUninstallString(): String;
var
  sUnInstPath: String;
  sUnInstallString: String;
begin
  // 构建注册表路径
  sUnInstPath := ExpandConstant('Software\Microsoft\Windows\CurrentVersion\Uninstall\{#SetupSetting("AppId")}_is1');
  
  // 初始化
  sUnInstallString := '';
  
  // 首先尝试从HKLM64查找（64位系统）
  if not RegQueryStringValue(HKLM64, sUnInstPath, 'UninstallString', sUnInstallString) then
  begin
    // 尝试从HKLM32查找（32位系统或32位程序在64位系统上）
    if not RegQueryStringValue(HKLM32, sUnInstPath, 'UninstallString', sUnInstallString) then
    begin
      // 尝试从HKCU查找（当前用户安装）
      RegQueryStringValue(HKCU, sUnInstPath, 'UninstallString', sUnInstallString);
    end;
  end;
  
  Result := sUnInstallString;
end;

// 检查是否需要升级
function IsUpgrade(): Boolean;
begin
  Result := (GetUninstallString() <> '');
end;

// 卸载旧版本
function UnInstallOldVersion(): Integer;
var
  sUnInstallString: String;
  iResultCode: Integer;
begin
  // 返回值说明：
  // 1 - 没有找到旧版本
  // 2 - 卸载失败
  // 3 - 卸载成功
  
  Result := 1; // 默认没有旧版本
  
  // 获取卸载字符串
  sUnInstallString := GetUninstallString();
  
  if sUnInstallString <> '' then
  begin
    // 去除引号
    sUnInstallString := RemoveQuotes(sUnInstallString);
    
    // 执行卸载命令
    // 使用官方推荐的参数：/VERYSILENT /NORESTART /SUPPRESSMSGBOXES
    if Exec(sUnInstallString, '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES', '', SW_HIDE, ewWaitUntilTerminated, iResultCode) then
    begin
      Result := 3; // 卸载成功
      Sleep(3000); // 等待卸载完成
    end
    else
    begin
      Result := 2; // 卸载失败
    end;
  end;
end;

// 初始化安装程序
function InitializeSetup(): Boolean;
var
  iResult: Integer;
  sUnInstallString: String;
  MsgResult: Integer;
begin
  Result := True;
  
  // 检查是否有旧版本
  if IsUpgrade() then
  begin
    // 获取卸载字符串用于显示
    sUnInstallString := GetUninstallString();
    
    // 询问用户是否卸载旧版本
    MsgResult := MsgBox(CustomMessage('UninstallOldVersionPrompt'), mbConfirmation, MB_YESNO);
    
    if MsgResult = IDYES then
    begin
      // 卸载旧版本
      iResult := UnInstallOldVersion();
      
      case iResult of
        1: ; // 未找到旧版本，继续安装
        2: begin
             MsgBox(CustomMessage('UninstallError'), mbError, MB_OK);
             Result := False; // 终止安装
             Exit;
           end;
        3: MsgBox(CustomMessage('UninstallSuccess'), mbInformation, MB_OK);
      end;
    end;
  end;
end;

// 根据语言代码获取对应的文件后缀
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
  else
    Result := 'en'; // 默认英语
  end;
end;

// 从安装程序内部读取文件内容
function ReadInternalFile(const FileName: string): string;
var
  TempFile: string;
  Lines: TArrayOfString;
  i: Integer;
begin
  // 将文件提取到临时目录
  TempFile := ExpandConstant('{tmp}\' + FileName);
  ExtractTemporaryFile(FileName);
  
  // 读取文件内容
  Result := '';
  if LoadStringsFromFile(TempFile, Lines) then
  begin
    for i := 0 to GetArrayLength(Lines) - 1 do
    begin
      if i > 0 then
        Result := Result + #13#10;
      Result := Result + Lines[i];
    end;
  end
  else
  begin
    Result := '无法加载文件: ' + FileName;
  end;
  
  // 删除临时文件
  DeleteFile(TempFile);
end;

// 初始化安装程序
procedure InitializeWizard;
var
  LanguageSuffix: string;
  InfoBeforeFile: string;
begin
  // 获取当前语言对应的文件后缀
  LanguageSuffix := GetLanguageSuffix(ActiveLanguage);
  
  // 构建文件名
  InfoBeforeFile := 'instructions_' + LanguageSuffix + '.txt';
  
  // 创建安装前信息页面（在欢迎页面后，组件选择页面前）
  InfoBeforePage := CreateCustomPage(wpWelcome, CustomMessage('InstallInstructions'), '');
  InfoBeforeMemo := TMemo.Create(InfoBeforePage);
  with InfoBeforeMemo do
  begin
    Parent := InfoBeforePage.Surface;
    ScrollBars := ssVertical;
    ReadOnly := True;
    Left := ScaleX(0);
    Top := ScaleY(0);
    Width := InfoBeforePage.SurfaceWidth;
    Height := InfoBeforePage.SurfaceHeight;
    Text := ReadInternalFile(InfoBeforeFile);
  end;
end;

// 处理页面切换
procedure CurPageChanged(CurPageID: Integer);
var
  LanguageSuffix: string;
  InfoAfterFile: string;
begin
  // 在安装完成后，创建快捷键说明页面
  if CurPageID = wpInstalling then
  begin
    // 在安装完成后，创建快捷键说明页面
    if InfoAfterPage = nil then
    begin
      // 获取当前语言对应的文件后缀
      LanguageSuffix := GetLanguageSuffix(ActiveLanguage);
      InfoAfterFile := 'shortcuts_' + LanguageSuffix + '.txt';
      
      // 创建快捷键说明页面（在安装页面后，完成页面前）
      InfoAfterPage := CreateCustomPage(wpInstalling, CustomMessage('ShortcutInstructions'), '');
      InfoAfterMemo := TMemo.Create(InfoAfterPage);
      with InfoAfterMemo do
      begin
        Parent := InfoAfterPage.Surface;
        ScrollBars := ssVertical;
        ReadOnly := True;
        Left := ScaleX(0);
        Top := ScaleY(0);
        Width := InfoAfterPage.SurfaceWidth;
        Height := InfoAfterPage.SurfaceHeight;
        Text := ReadInternalFile(InfoAfterFile);
      end;
    end;
  end;
end;

// 安装步骤回调：勾选"清空目录"时在安装前删除旧文件
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssInstall) and WizardIsTaskSelected('cleaninstall') then
  begin
    if DirExists(ExpandConstant('{app}')) then
      DelTree(ExpandConstant('{app}'), True, True, True);
  end;
end;
