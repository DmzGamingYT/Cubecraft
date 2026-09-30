; Installeur Windows de Cubecraft, compile par Inno Setup 6 (gratuit, open source).
;
; Godot produit un `.exe` autonome : le PCK du jeu est deja a l'interieur. Il
; n'y a donc rien a copier a cote, seulement a installer proprement — un
; dossier, un lanceur dans le menu Demarrer, une entree dans "Ajouter ou
; supprimer un programme" et un desinstalleur qui fonctionne.
;
; Ce qu'Inno Setup apporte, et que le `.exe` nu n'a pas :
;   - un assistant en francais, page par page ;
;   - la licence MIT affichee avant l'installation ;
;   - un dossier d'installation choisi par l'utilisateur ;
;   - une entree dans Parametres > Applications, avec version et editeur ;
;   - un desinstalleur qui ne laisse pas de trace.
;
; Compiler :  ISCC.exe packaging\installer.iss
; (ou `iscc packaging/installer.iss` si Inno Setup est dans le PATH)
;
; Le binaire a emballer et la version sont lus par des symboles passes sur la
; ligne de commande : `ISCC /DVer=1.1.0 /DSrcBin=... installer.iss`
; Cela evite d'avoir a editer ce fichier a chaque version.
;
; Le symbole s'appelle `Ver` et non `AppVersion` : `AppVersion` est deja une
; cle de la section [Setup] plus bas, et le preprocesseur ne fait pas la
; difference entre les deux espaces de noms.

#ifndef SrcBin
  #define SrcBin "..\build\windows\Cubecraft.exe"
#endif
#ifndef Ver
  #define Ver "1.0.0"
#endif
#ifndef OutExe
  #define OutExe "..\build\windows\Cubecraft-Setup.exe"
#endif

[Setup]
; L'AppId identifie l'installation aupres de Windows. Il ne doit jamais
; changer entre deux versions : c'est lui qui reconnait une mise a jour et
; qui fait propositions de desinstaller l'ancien programme. Utiliser un GUID
; fixe, ici celui du projet.
AppId={{7B2C9F41-6A3D-4E58-9C1B-2D5F8A7E4B30}
AppName=Cubecraft
AppVersion={#Ver}
AppVerName=Cubecraft {#Ver}
AppPublisher=DmzGamingYT
AppPublisherURL=https://github.com/DmzGamingYT
AppSupportURL=https://github.com/DmzGamingYT/Cubecraft/issues
AppUpdatesURL=https://github.com/DmzGamingYT/Cubecraft/releases
DefaultDirName={autopf}\Cubecraft
DefaultGroupName=Cubecraft
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
OutputDir=..\build\windows
OutputBaseFilename=Cubecraft-Setup-{#Ver}
SetupIconFile=..\assets\icons\cubecraft.ico
UninstallDisplayIcon={app}\Cubecraft.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Le jeu a une fenetre 3D : on refuse l'installation sur 32 bits plutot que de
; laisser un programme incapable de tourner.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Un jeu n'a rien a faire dans le dossier Systeme, ni dans une cle de registre
; partagee : on garde tout sous Program Files et HKCU.
PrivilegesRequiredOverridesAllowed=dialog
WizardSizePercent=110

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "{#SrcBin}"; DestDir: "{app}"; Flags: ignoreversion
; L'icone est copiee a part : c'est elle que l'assistant affiche dans
; "Ajouter ou supprimer un programme" apres l'installation.
Source: "..\assets\icons\cubecraft.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Cubecraft"; Filename: "{app}\Cubecraft.exe"; WorkingDir: "{app}"; IconFilename: "{app}\Cubecraft.ico"
Name: "{group}\Desinstaller Cubecraft"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Cubecraft"; Filename: "{app}\Cubecraft.exe"; WorkingDir: "{app}"; IconFilename: "{app}\Cubecraft.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\Cubecraft.exe"; Description: "{cm:LaunchProgram,Cubecraft}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Godot ecrit ses sauvegardes et ses reglages dans le dossier utilisateur, pas
; dans le programme : le desinstaller ne doit donc rien y toucher. Cette
; section vide est laissee explicitement, parce que c'est une question que
; tout le monde se pose.
