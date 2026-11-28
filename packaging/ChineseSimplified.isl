; *** Inno Setup version 6.5.0+ 中文消息 ***
;
; 要下载用户提供的该文件的翻译，请访问:
;   https://jrsoftware.org/files/istrans/
;
; 请注意：在翻译该文本时，请不要在没有句号的信息末尾添加句号 (.) ，
; 因为 Inno Setup 会自动在这些信息中添加句号(添加句号会导致显示两个句号)。
;
;

[LangOptions]
; 以下三个条目非常重要。确保阅读和
; 以下三个条目非常重要。请务必在帮助文件中阅读和理解 "[LangOptions] 区段" 主题。
LanguageName=<7B80><4F53><4E2D><6587>
LanguageID=$0804
; 即使此文件是 Unicode，也应始终设置 LanguageCodepage
; 对于英语，无论如何它都设置为零，因为英语仅使用 ASCII 字符
LanguageCodePage=936
;
; 如果你要翻译成的语言需要特殊的字体或大小，请取消以下任何条目注释 (;)，并进行相应更改。
DialogFontName=Tahoma
DialogFontSize=9
DialogFontBaseScaleWidth=7
DialogFontBaseScaleHeight=15
WelcomeFontName=Segoe UI
WelcomeFontSize=14

[Messages]

; *** Application titles
SetupAppTitle=安装程序
SetupWindowTitle=安装程序 - %1
UninstallAppTitle=卸载
UninstallAppFullTitle=%1 卸载

; *** Misc. common
InformationTitle=信息
ConfirmTitle=确认
ErrorTitle=错误

; *** SetupLdr messages
SetupLdrStartupMessage=这将安装 %1。是否要继续？
LdrCannotCreateTemp=无法创建临时文件。安装程序已中止
LdrCannotExecTemp=无法执行临时目录中的文件。安装程序已中止
HelpTextNote=

; *** Startup error messages
LastErrorMessage=%1。%n%n错误 %2: %3
SetupFileMissing=安装目录中缺少文件 %1。请更正问题或获取程序的新副本。
SetupFileCorrupt=安装文件已损坏。请获取该程序的新副本。
SetupFileCorruptOrWrongVer=安装文件已损坏，或与此版本的安装程序不兼容。请更正问题或获取程序的新副本。
InvalidParameter=在命令行上传递了无效参数:%n%n%1
SetupAlreadyRunning=安装程序已在运行。
WindowsVersionNotSupported=此程序不支持你的计算机正在运行的 Windows 版本。
WindowsServicePackRequired=此程序需要 %1 Service Pack %2 或更高版本。
NotOnThisPlatform=此程序不会在 %1 上运行。
OnlyOnThisPlatform=此程序必须在 %1 上运行。
OnlyOnTheseArchitectures=此程序只能安装在专为以下处理器体系结构设计的 Windows 版本上:%n%n%1
WinVersionTooLowError=此程序需要 %1 版本 %2 或更高版本。
WinVersionTooHighError=此应用程序不能安装在 %1 版本 %2 或更高版本上。
AdminPrivilegesRequired=安装此程序时，你必须以管理员身份登录。
PowerUserPrivilegesRequired=安装此程序时，你必须以管理员或高级用户组成员的身份登录。
SetupAppRunningError=安装程序检测到 %1 当前正在运行。%n%n请立即关闭它的所有实例，然后单击“确定”继续，或单击“取消”退出。
UninstallAppRunningError=卸载检测到 %1 当前正在运行。%n%n请立即关闭它的所有实例，然后单击“确定”继续，或单击“取消”退出。

; *** Startup questions
PrivilegesRequiredOverrideTitle=选择安装程序安装模式
PrivilegesRequiredOverrideInstruction=选择安装模式
PrivilegesRequiredOverrideText1=%1 可以为所有用户安装(需要管理权限)，也可以仅为你安装。
PrivilegesRequiredOverrideText2=%1 只能为你安装，也可以为所有用户安装(需要管理权限)。
PrivilegesRequiredOverrideAllUsers=为所有用户安装(&A)
PrivilegesRequiredOverrideAllUsersRecommended=为所有用户安装(推荐)(&A)
PrivilegesRequiredOverrideCurrentUser=仅为我安装(&M)
PrivilegesRequiredOverrideCurrentUserRecommended=仅为我安装(推荐)(&M)

; *** Misc. errors
ErrorCreatingDir=安装程序无法创建目录“%1”
ErrorTooManyFilesInDir=无法在目录“%1”中创建文件，因为它包含太多文件

; *** Setup common messages
ExitSetupTitle=退出设置
ExitSetupMessage=安装未完成。如果现在退出，则不会安装该程序。%n%n你可以在其他时间再次运行安装程序以完成安装。%n%n退出安装程序？
AboutSetupMenuItem=关于安装程序(&A)...
AboutSetupTitle=关于安装程序
AboutSetupMessage=%1 版本  %2%n%3%n%n%1  主页:%n%4
AboutSetupNote=
TranslatorNote=

; *** Buttons
ButtonBack=< 返回(&B)
ButtonNext=下一步(&N) >
ButtonInstall=安装(&I)
ButtonOK=确定
ButtonCancel=取消
ButtonYes=是(&Y)
ButtonYesToAll=全是(&A)
ButtonNo=否(&N)
ButtonNoToAll=全否(&O)
ButtonFinish=完成(&F)
ButtonBrowse=浏览(&B)...
ButtonWizardBrowse=浏览(&R)...
ButtonNewFolder=创建新文件夹(&M)

; *** "Select Language" dialog messages
SelectLanguageTitle=选择安装语言
SelectLanguageLabel=选择要在安装过程中使用的语言。

; *** Common wizard text
ClickNext=单击“下一步”继续，或单击“取消”退出安装程序。
BeveledLabel=
BrowseDialogTitle=浏览文件夹
BrowseDialogLabel=在下面的列表中选择一个文件夹，然后单击“确定”。
NewFolderName=新建文件夹

; *** "Welcome" wizard page
WelcomeLabel1=欢迎使用 [name] 安装向导
WelcomeLabel2=这将在你的计算机上安装 [name/ver]。%n%n建议你先关闭所有其他应用程序，然后再继续。

; *** "Password" wizard page
WizardPassword=密码
PasswordLabel1=此安装受密码保护。
PasswordLabel3=请提供密码，然后单击“下一步”继续。密码区分大小写。
PasswordEditLabel=密码(&P):
IncorrectPassword=你输入的密码不正确。请再试一次。

; *** "License Agreement" wizard page
WizardLicense=许可协议
LicenseLabel=在继续之前，请阅读以下重要信息。
LicenseLabel3=请阅读以下许可协议。在继续安装之前，你必须接受本协议的条款。
LicenseAccepted=我接受协议(&A)
LicenseNotAccepted=我不接受该协议(&D)

; *** "Information" wizard pages
WizardInfoBefore=信息
InfoBeforeLabel=在继续之前，请阅读以下重要信息。
InfoBeforeClickLabel=当你准备好继续安装时，请单击“下一步”。
WizardInfoAfter=信息
InfoAfterLabel=在继续之前，请阅读以下重要信息。
InfoAfterClickLabel=当你准备好继续安装时，请单击“下一步”。

; *** "User Information" wizard page
WizardUserInfo=用户信息
UserInfoDesc=请输入你的信息。
UserInfoName=用户名(&U):
UserInfoOrg=组织(&O):
UserInfoSerial=序列号(&S):
UserInfoNameRequired=你必须输入名称。

; *** "Select Destination Location" wizard page
WizardSelectDir=选择目标位置
SelectDirDesc=[name] 应该安装在哪里？
SelectDirLabel3=安装程序会将 [name] 安装到以下文件夹中。
SelectDirBrowseLabel=若要继续，请单击“下一步”。如果要选择其他文件夹，请单击“浏览”。
DiskSpaceGBLabel=至少需要 [gb] GB 的可用磁盘空间。
DiskSpaceMBLabel=至少需要 [mb] MB 的可用磁盘空间。
CannotInstallToNetworkDrive=安装程序无法安装到网络驱动器。
CannotInstallToUNCPath=安装程序无法安装到 UNC 路径。
InvalidPath=你必须输入带有驱动器号的完整路径; 例如:%n%nC:\APP%n%nor 是格式为 %n%n\\server\\share 的 UNC 路径
InvalidDrive=你选择的驱动器或 UNC 共享不存在或无法访问。请选择其他。
DiskSpaceWarningTitle=磁盘空间不足
DiskSpaceWarning=安装程序至少需要 %1 KB 的可用空间才能安装，但所选驱动器只有 %2 KB 可用。%n%n是否仍要继续？
DirNameTooLong=文件夹名称或路径太长。
InvalidDirName=文件夹名称无效。
BadDirName32=文件夹名称不能包含以下任何字符:%n%n%1
DirExistsTitle=文件夹存在
DirExists=文件夹:%n%n%1%n%n已存在。是否仍要安装到该文件夹？
DirDoesntExistTitle=文件夹不存在
DirDoesntExist=文件夹:%n%n%1%n%n不存在。是否要创建文件夹？

; *** "Select Components" wizard page
WizardSelectComponents=选择组件
SelectComponentsDesc=应安装哪些组件？
SelectComponentsLabel2=选择要安装的组件; 清除不想安装的组件。当你准备好继续时，单击“下一步”。
FullInstallation=完整安装
;如果可能，不要将 "Compact" 翻译成 "Minimal" (我的意思是你们语言中的 "Minimal")。
CompactInstallation=精简安装
CustomInstallation=自定义安装
NoUninstallWarningTitle=组件存在
NoUninstallWarning=安装程序检测到你的计算机上已安装以下组件:%n%n%1%n%n取消选择这些组件不会卸载它们。%n%n是否仍要继续？
ComponentSize1=%1 KB
ComponentSize2=%1 MB
ComponentsDiskSpaceGBLabel=当前选择至少需要 [gb] GB 的磁盘空间。
ComponentsDiskSpaceMBLabel=当前选择至少需要 [mb] MB 的磁盘空间。

; *** "Select Additional Tasks" wizard page
WizardSelectTasks=选择“其他任务”
SelectTasksDesc=应执行哪些附加任务？
SelectTasksLabel2=选择你希望安装程序在安装 [name] 时执行的其他任务，然后单击下一步。

; *** "Select Start Menu Folder" wizard page
WizardSelectProgramGroup=选择“开始”菜单文件夹
SelectStartMenuFolderDesc=安装程序应将程序的快捷方式放在哪里？
SelectStartMenuFolderLabel3=安装程序将在以下“开始”菜单文件夹中创建程序的快捷方式。
SelectStartMenuFolderBrowseLabel=若要继续，请单击“下一步”。如果要选择其他文件夹，请单击“浏览”。
MustEnterGroupName=你必须输入文件夹名称。
GroupNameTooLong=文件夹名称或路径太长。
InvalidGroupName=文件夹名称无效。
BadGroupName=文件夹名称不能包含以下任何字符：%n%n%1
NoProgramGroupCheck2=不要创建“开始”菜单文件夹(&D)

; *** "Ready to Install" wizard page
WizardReady=准备安装
ReadyLabel1=安装程序现在已准备好开始在计算机上安装 [name]。
ReadyLabel2a=单击“安装”继续安装，如果要查看或更改任何设置，请单击“返回”。
ReadyLabel2b=单击“安装”继续安装。
ReadyMemoUserInfo=用户信息:
ReadyMemoDir=目标位置:
ReadyMemoType=安装程序类型:
ReadyMemoComponents=选定组件:
ReadyMemoGroup="开始菜单" 文件夹:
ReadyMemoTasks=附加任务：

; *** TDownloadWizardPage wizard page and DownloadTemporaryFile
DownloadingLabel2=下载文件...
ButtonStopDownload=停止下载(&S)
StopDownload=你确定要停止下载吗？
ErrorDownloadAborted=下载已中止
ErrorDownloadFailed=下载失败: %1%2
ErrorDownloadSizeFailed=获取大小失败: %1%2
ErrorProgress=无效的进度: %2 的 %1
ErrorFileSize=文件大小无效: 预期的 %1，找到的 %2

; *** TExtractionWizardPage wizard page and ExtractArchive
ExtractingLabel=正在提取文件...
ButtonStopExtraction=停止提取(&S)
StopExtraction=你确定要停止提取吗？
ErrorExtractionAborted=提取中止
ErrorExtractionFailed=提取失败：%1

; *** Archive extraction failure details
ArchiveIncorrectPassword=密码不正确
ArchiveIsCorrupted=档案被损坏
ArchiveUnsupportedFormat=档案格式不支持

; *** "Preparing to Install" wizard page
WizardPreparing=准备安装
PreparingDesc=安装程序正准备在计算机上安装 [name]。
PreviousInstallNotCompleted=未完成先前程序的安装/删除。你将需要重新启动计算机才能完成该安装。%n%n重新启动计算机后，再次运行安装程序以完成 [name] 的安装。
CannotContinue=安装程序无法继续。请点击取消退出。
ApplicationsFound=以下应用程序正在使用需要通过安装程序更新的文件。建议你允许安装程序自动关闭这些应用程序。
ApplicationsFound2=以下应用程序正在使用需要通过安装程序更新的文件。建议你允许安装程序自动关闭这些应用程序。安装完成后，安装程序将尝试重新启动应用程序。
CloseApplications=自动关闭应用程序(&A)
DontCloseApplications=不要关闭应用程序(&D)
ErrorCloseApplications=安装程序无法自动关闭所有应用程序。建议你先使用需要由安装程序更新的文件关闭所有应用程序，然后再继续。
PrepareToInstallNeedsRestart=安装程序必须重新启动计算机。重新启动计算机后，再次运行安装程序以完成 [name] 的安装。%n%n是否要立即重新启动？

; *** "Installing" wizard page
WizardInstalling=安装
InstallingLabel=安装程序在计算机上安装 [name] 时，请稍候。

; *** "Setup Completed" wizard page
FinishedHeadingLabel=结束 [name] 安装向导
FinishedLabelNoIcons=安装程序在计算机上已完成 [name] 的安装。
FinishedLabel=安装程序在计算机上已完成 [name] 的安装。可以通过选择已安装的快捷方式来启动应用程序。
ClickFinish=单击“完成”退出安装程序。
FinishedRestartLabel=若要完成 [name] 的安装，安装程序必须重新启动计算机。是否要立即重新启动？
FinishedRestartMessage=若要完成 [name] 的安装，安装程序必须重新启动计算机。%n%n是否要立即重新启动？
ShowReadmeCheck=是的，我想查看 README 文件
YesRadio=是的，立即重新启动计算机(&Y)
NoRadio=不，我稍后会重新启动计算机(&N)
; 例如用作 'Run MyProg.exe'
RunEntryExec=运行 %1
; 例如用作“查看 readme.txt”
RunEntryShellExec=查看 %1

; *** "Setup Needs the Next Disk" stuff
ChangeDiskTitle=安装程序需要下一个磁盘
SelectDiskLabel2=请插入磁盘 %1 并单击确定。%n%n如果此磁盘上的文件位于下面显示的文件夹以外的文件夹中，请输入正确的路径或单击“浏览”。
PathLabel=路径(&P):
FileNotInDir2=文件“%1”不能位于“%2”中。请插入正确的磁盘或选择其他文件夹。
SelectDirectoryLabel=请指定下一个磁盘的位置。

; *** Installation phase messages
SetupAborted=安装程序未完成。%n%n请更正问题并重新运行安装程序。
AbortRetryIgnoreSelectAction=选择操作
AbortRetryIgnoreRetry=再试一次(&T)
AbortRetryIgnoreIgnore=忽略错误并继续(&I)
AbortRetryIgnoreCancel=取消安装
RetryCancelSelectAction=选择操作
RetryCancelRetry=再试一次(&T)
RetryCancelCancel=取消

; *** Installation status messages
StatusClosingApplications=正在关闭应用程序...
StatusCreateDirs=正在创建目录...
StatusExtractFiles=提取文件...
StatusDownloadFiles=下载文件...
StatusCreateIcons=正在创建快捷方式...
StatusCreateIniEntries=正在创建 INI 条目...
StatusCreateRegistryEntries=正在创建注册表项...
StatusRegisterFiles=正在注册文件...
StatusSavingUninstall=正在保存卸载信息...
StatusRunProgram=完成安装...
StatusRestartingApplications=重新启动应用程序...
StatusRollback=回滚更改...

; *** Misc. errors
ErrorInternal2=内部错误: %1
ErrorFunctionFailedNoCode=%1 失败
ErrorFunctionFailed=%1 失败; 代码 %2
ErrorFunctionFailedWithMessage=%1 失败; 代码 %2.%n%3
ErrorExecutingProgram=无法执行文件:%n%1

; *** Registry errors
ErrorRegOpenKey=打开注册表项时出错:%n%1\%2
ErrorRegCreateKey=创建注册表项时出错:%n%1\%2
ErrorRegWriteKey=写入注册表项时出错:%n%1\%2

; *** INI errors
ErrorIniEntry=在文件“%1”中创建 INI 条目时出错。

; *** File copying errors
FileAbortRetryIgnoreSkipNotRecommended=跳过此文件(不推荐)(&S)
FileAbortRetryIgnoreIgnoreNotRecommended=忽略错误并继续(不推荐)(&I)
SourceIsCorrupted=源文件已损坏
SourceDoesntExist=源文件“%1”不存在
SourceVerificationFailed=源文件的验证失败：%1
VerificationSignatureDoesntExist=签名文件“%1”不存在
VerificationSignatureInvalid=签名文件“%1”无效
VerificationKeyNotFound=签名文件“%1”使用未知密钥
VerificationFileNameIncorrect=文件的名称不正确
VerificationFileTagIncorrect=文件的标签不正确
VerificationFileSizeIncorrect=文件的大小不正确
VerificationFileHashIncorrect=文件的哈希值不正确
ExistingFileReadOnly2=无法替换现有文件，因为它被标记为只读。
ExistingFileReadOnlyRetry=删除只读属性，然后重试(&R)
ExistingFileReadOnlyKeepExisting=保留现有文件(&K)
ErrorReadingExistingDest=尝试读取现有文件时出错:
FileExistsSelectAction=选择操作
FileExists2=该文件已存在。
FileExistsOverwriteExisting=覆盖现有文件(&O)
FileExistsKeepExisting=保留现有文件(&K)
FileExistsOverwriteOrKeepAll=对下一个冲突执行此操作(&D)
ExistingFileNewerSelectAction=选择动作
ExistingFileNewer2=现有文件比安装程序尝试安装的文件新。
ExistingFileNewerOverwriteExisting=覆盖现有文件(&O)
ExistingFileNewerKeepExisting=保留现有文件(推荐)(&K)
ExistingFileNewerOverwriteOrKeepAll=对下一个冲突执行此操作(&D)
ErrorChangingAttr=尝试更改现有文件的属性时出错:
ErrorCreatingTemp=尝试在目标目录中创建文件时出错:
ErrorReadingSource=尝试读取源文件时出错:
ErrorCopying=尝试复制文件时出错:
ErrorDownloading=尝试下载文件时发生了错误:
ErrorExtracting=试图提取存档时发生错误:
ErrorReplacingExistingFile=尝试替换现有文件时出错:
ErrorRestartReplace=RestartReplace 失败:
ErrorRenamingTemp=尝试重命名目标目录中的文件时出错:
ErrorRegisterServer=无法注册 DLL/OCX: %1
ErrorRegSvr32Failed=RegSvr32 失败，退出代码为 %1
ErrorRegisterTypeLib=无法注册类型库: %1

; *** Uninstall display name markings
; 例如用作“我的程序 (32 位)”
UninstallDisplayNameMark=%1 (%2)
; 例如，用作“我的程序 (32 位，所有用户)”
UninstallDisplayNameMarks=%1 (%2, %3)
UninstallDisplayNameMark32Bit=32 位
UninstallDisplayNameMark64Bit=64 位
UninstallDisplayNameMarkAllUsers=所有用户
UninstallDisplayNameMarkCurrentUser=当前用户

; *** Post-installation errors
ErrorOpeningReadme=尝试打开 README 文件时出错。
ErrorRestartingComputer=安装程序无法重新启动计算机。请手动执行此操作。

; *** Uninstaller messages
UninstallNotFound=文件 "%1" 不存在。无法卸载。
UninstallOpenError=无法打开文件 "%1"。无法卸载
UninstallUnsupportedVer=卸载日志文件 "%1" 的格式是此版本的卸载程序无法识别的格式。无法卸载
UninstallUnknownEntry=在卸载日志中遇到一个未知条目(%1)
ConfirmUninstall=是否确实要完全删除 %1 及其所有组件？
UninstallOnlyOnWin64=此安装只能在 64 位 Windows 上卸载。
OnlyAdminCanUninstall=此安装只能由具有管理权限的用户卸载。
UninstallStatusLabel=请稍候，直到从计算机中删除 %1。
UninstalledAll=%1 已成功从计算机中删除。
UninstalledMost=%1 卸载完成。%n%n无法删除某些元素。这些可以手动删除。
UninstalledAndNeedsRestart=若要完成 %1 的卸载，必须重新启动计算机。%n%n是否要立即重新启动？
UninstallDataCorrupted="%1" 文件已损坏。无法卸载

; *** Uninstallation phase messages
ConfirmDeleteSharedFileTitle=删除共享文件？
ConfirmDeleteSharedFile2=系统指示以下共享文件不再被任何程序使用。是否希望“卸载”删除此共享文件？%n%n如果任何程序仍在使用此文件，并且该文件已被删除，则这些程序可能无法正常运行。如果你不确定，请选择“否”。将文件留在你的系统上不会造成任何伤害。
SharedFileNameLabel=文件名:
SharedFileLocationLabel=位置:
WizardUninstalling=卸载状态
StatusUninstalling=正在卸载 %1...

; *** Shutdown block reasons
ShutdownBlockReasonInstallingApp=正在安装 %1。
ShutdownBlockReasonUninstallingApp=正在卸载 %1。

;
;安装程序本身并不使用下面的自定义信息，但如果您在脚本中使用这些信息，则需要对其进行翻译。

[CustomMessages]

NameAndVersion=%1 版本 %2
AdditionalIcons=附加快捷方式:
CreateDesktopIcon=创建桌面快捷方式(&D)
CreateQuickLaunchIcon=创建快速启动快捷方式(&Q)
ProgramOnTheWeb=网络上的 %1
UninstallProgram=卸载 %1
LaunchProgram=启动 %1
AssocFileExtension=将 %1 与 %2 文件扩展名相关联(&A)
AssocingFileExtension=正在关联 %1 和 %2 文件扩展名...
AutoStartProgramGroupDescription=启动:
AutoStartProgram=自动启动 %1
AddonHostProgramNotFound=%1 无法在你选择的文件夹中找到。%n%n是否仍要继续？
