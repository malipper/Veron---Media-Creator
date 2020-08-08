$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"
$Host.UI.RawUI.BackgroundColor = ($bckgrnd = 'Black')
[console]::BufferWidth = [console]::WindowWidth
[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
$host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(8192,50)
$maxWS = $host.UI.RawUI.Get_MaxWindowSize()
$ws = $host.ui.RawUI.WindowSize
IF($maxws.width -ge 100)
{ $ws.width = 100 }
ELSE { $ws.width = $maxws.width }
IF($maxws.height -ge 20)
{ $ws.height = 20 }
ELSE { $ws.height = $maxws.height }
$host.ui.RawUI.Set_WindowSize($ws)

$checkPolicy = Get-ExecutionPolicy LocalMachine

$currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
$testadmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if ($testadmin -eq $false) {
  Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}" -elevated' -f ($myinvocation.MyCommand.Definition))
  exit $LASTEXITCODE
}
Get-Volume | % { Get-DiskImage -DevicePath $($_.Path -replace "\\$")} | Dismount-DiskImage | OUT-NULL

$Path_Modul = Split-Path $script:MyInvocation.MyCommand.Path
$Path_ISO = -join($Path_Modul, "\ISO\efisys.bin")
$Path_IntuneJoin = -join($Path_Modul, "\INTUNE\*")
$Path_Auto = -join($Path_Modul, "\AUTOPILOT\AutoPilotConfigurationFile.json")
$srcfolder = $null
$destfolder = $null

function New_Entry ([int]$xposi,[int]$yposi,[string]$Text,[System.ConsoleColor]$Color) 
{
    $position=$Host.ui.RawUI.CursorPosition
    $position.x = $xposi
    $position.y = $yposi
    $Host.ui.RawUI.CursorPosition=$position
    Write-Host $Text -ForegroundColor $Color
}
#>-----------------------------------------------------------------------------
function USBCreator()
{
  Get-Volume | % { Get-DiskImage -DevicePath $($_.Path -replace "\\$")} | Dismount-DiskImage | OUT-NULL
  cls
  Write-Host "Veron - Bootable USB-Creator"
  Write-Host "----------------------------"
  Write-Host ""
  Write-Host ""
  Write-Host ""
  Write-Host "___________________"
  Write-Host "ISO-File         = "
  Write-Host "USB-Stick        = "
  Write-Host "Deleting Stick   = "
  Write-Host "Preparing Stick  = "
  Write-Host "Copy Intune-Tool = "
  Write-Host "Copy Setup-Files = "
  Write-Host "Copy Install.WMI = "
  Write-Host "___________________"
  New_Entry 0 3 "Press Enter to start..." Yellow
  Read-Host
  
  ###'ISO-File abfragen'#########################################
  New_Entry 0 3 "Please select the ISO-File." Yellow
  $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog
  $FileBrowser.Reset()
  $FileBrowser.Filter = "iso files (*.iso)|*.iso"
  New_Entry 19 6 "<-" Yellow
  $FileBrowser.Description = "Please select the ISO-File"
  $FileBrowser.ShowDialog() | Out-Null
  $iso = $FileBrowser.FileName
  New_Entry 19 6 "$iso" green

  ###'USB-STICK abfragen'#########################################
  New_Entry 0 3 "Please select the USB-Stick." Yellow  
  $Stick = Get-Disk | Where BusType -eq 'USB' | Select-Object BusType, FriendlyName, Size | Out-GridView -Title "Please select the USB-Stick" -OutputMode Single
  If ($Stick -eq $null) {  New_Entry 19 7 "No USB-Stick found." red}
  Stop-Service -Name ShellHWDetection
  New_Entry 19 7 $Stick.FriendlyName green
  ###############################################################
    #==================================================================================================
  If (!($Stick.FriendlyName.Length -le 1 -or $iso.Length -le 4))
  {
    New_Entry 0 3 "Press Enter to start the bootable USB-Stick creation." Yellow
    Read-Host
    New_Entry 0 3 "Please wait, the USB-Stick is being created.         " Red
    #==================================================================================================
    # DELETE DISK
    New_Entry 19 8 "<-" Yellow
    Get-Disk -FriendlyName $Stick.FriendlyName | Clear-Disk -RemoveData -Confirm:$false
    # DELETE ALL PARTIONS (important by RAW-Partitions)
    Get-Disk -FriendlyName $Stick.FriendlyName | Get-Partition | Remove-Partition -Confirm:$false
    New_Entry 19 8 "ok" green
     #==================================================================================================
    New_Entry 19 9 "<-" Yellow
    
    # Convert GPT
    $Stick | Initialize-Disk -PartitionStyle GPT
    $Stick | Where-Object {$_.PartitionStyle -eq "RAW" -and $_.BusType -eq "USB"} | Initialize-Disk -PartitionStyle GPT
    if ((Get-Disk -FriendlyName $Stick.FriendlyName).PartitionStyle -ne 'GPT') {Get-Disk -FriendlyName $Stick.FriendlyName | Set-Disk -PartitionStyle GPT}
    # Create partition primary and format to FAT32
    $fatvolume = Get-Disk -FriendlyName $Stick.FriendlyName | New-Partition -UseMaximumSize -AssignDriveLetter | Format-Volume -FileSystem FAT32 -NewFileSystemLabel "Bootstick"
    New_Entry 19 9 "ok" green
    
    # Mount iso
    $miso = Mount-DiskImage -ImagePath $iso -StorageType ISO -PassThru
    # Driver letter
    $dl = ($miso | Get-Volume).DriveLetter
        
    New_Entry 19 10 "<-" Yellow
    #==================================================================================================
    Get-ChildItem -Path $Path_IntuneJoin | Copy-Item -Destination "$($fatvolume.DriveLetter):\" | Out-Null    
    #==================================================================================================
    New_Entry 19 10 "ok                                                                                 " green 
    
    
    New_Entry 19 11 "<-" Yellow
    #==================================================================================================
    #region FILESTREAM-FAT32
                
      $local = "$($dl):\"
      $net = "$($fatvolume.DriveLetter):\"
      $AutoPilot_Path = -join("$net", 'sources\$OEM$\$$\provisioning\Autopilot')
      If (!(Test-Path $AutoPilot_Path)) {New-Item -ItemType Directory -Path $AutoPilot_Path | Out-Null}
      
      Get-ChildItem -Path $Path_Auto | Copy-Item -Destination $AutoPilot_Path -Force
      
      if (!(Test-Path -Path $net)) { New-Item -Path $net -ItemType Directory | Out-Null }
      $Folder = Get-ChildItem -Path $local -Directory -Recurse                        
      Foreach ($Item in $Folder) {
          $ConvFolderTarget = $Item.FullName.Replace($local, $net)  
          if (!(Test-Path -Path $ConvFolderTarget)) {
              New-Item -Path $ConvFolderTarget -ItemType Directory | Out-Null
          }
      }

      $Filer = Get-ChildItem -Path $local -File -Recurse -Exclude "install.wim"
      [int]$Itemrem_value = 0

      Foreach ($Item in $Filer)
      {   
          $ConvItemrem = -join("[Items remaining: ", $Itemrem_value, "/",$Filer.Length, "]", " - ", $Item.Name , "                                             ")
          New_Entry 19 11 "<- $ConvItemrem" Yellow
          
          $ConvFilerTarget = $Item.FullName.Replace($local, $net)

          #TRANSFER CHILDITEMS
          $BufferSize = 524288
          $Buffer = [System.Byte[]]::new($BufferSize)

          [System.IO.FileStream]$SourceStream = [System.IO.File]::Open($Item.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
          [System.IO.FileStream]$DestinationStream = [System.IO.File]::OpenWrite($ConvFilerTarget)
          [long]$len = $SourceStream.Length - 1
          
          While($SourceStream.Position -le $len)
          {
              $bytesRead = $SourceStream.Read($Buffer, 0, $Buffer.Length)
              $DestinationStream.Write($Buffer, 0, $bytesRead)
          }

          $SourceStream.Close()
          $DestinationStream.Flush()
          $DestinationStream.Close()

          $Itemrem_value += 1
          $ConvItemrem = -join("[Items remaining: ", $Itemrem_value, "/",$Filer.Length, ")", " - ", $Item.Name , "                                             ")
          New_Entry 19 11 "<- $ConvItemrem" Yellow
      }
       
    #endregion
    #==================================================================================================
    New_Entry 19 11 "ok                                                                                 " green
        
         
    New_Entry 19 12 "<-" Yellow
    #==================================================================================================
    #region SPLITT INSTALL-WIM
    
      $local = "$($dl):\"
      $net = "$($fatvolume.DriveLetter):\"

    & (Get-Command "$($env:systemroot)\system32\dism.exe") @(
        '/split-image',
        "/imagefile:$($local)sources\install.wim",
        "/SWMFile:$($net)sources\install.swm",
        '/FileSize:3000'        
    )| Out-Null

    #endregion
    #==================================================================================================
    New_Entry 19 12 "ok                                                                                 " green
    
    
  }
  else{New_Entry 0 3 "A Source/Destionation-Path is not selected." red}

  #########################################################################
  Get-Volume | % { Get-DiskImage -DevicePath $($_.Path -replace "\\$")} | Dismount-DiskImage | OUT-NULL

  New_Entry 0 3 "Creation completed.                        " green
  $HOST.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
  $HOST.UI.RawUI.Flushinputbuffer()
}

function ISOCreator()
{
  function New-IsoFile  
  {  
    [CmdletBinding(DefaultParameterSetName='Source')]Param( 
      [parameter(Position=1,Mandatory=$true,ValueFromPipeline=$true, ParameterSetName='Source')]$Source,  
      [parameter(Position=2)][string]$Path = "$env:temp\$((Get-Date).ToString('yyyyMMdd-HHmmss.ffff')).iso",  
      [ValidateScript({Test-Path -LiteralPath $_ -PathType Leaf})][string]$BootFile = $null, 
      [ValidateSet('CDR','CDRW','DVDRAM','DVDPLUSR','DVDPLUSRW','DVDPLUSR_DUALLAYER','DVDDASHR','DVDDASHRW','DVDDASHR_DUALLAYER','DISK','DVDPLUSRW_DUALLAYER','BDR','BDRE')][string] $Media = 'DVDPLUSRW_DUALLAYER', 
      [string]$Title = (Get-Date).ToString("yyyyMMdd-HHmmss.ffff"),  
      [switch]$Force, 
      [parameter(ParameterSetName='Clipboard')][switch]$FromClipboard 
    ) 
 
    Begin {  
      ($cp = new-object System.CodeDom.Compiler.CompilerParameters).CompilerOptions = '/unsafe' 
      if (!('ISOFile' -as [type])) {  
        Add-Type -CompilerParameters $cp -TypeDefinition @' 
public class ISOFile  
{ 
  public unsafe static void Create(string Path, object Stream, int BlockSize, int TotalBlocks)  
  {  
    int bytes = 0;  
    byte[] buf = new byte[BlockSize];  
    var ptr = (System.IntPtr)(&bytes);  
    var o = System.IO.File.OpenWrite(Path);  
    var i = Stream as System.Runtime.InteropServices.ComTypes.IStream;  
  
    if (o != null) { 
      while (TotalBlocks-- > 0) {  
        i.Read(buf, BlockSize, ptr); o.Write(buf, 0, bytes);  
      }  
      o.Flush(); o.Close();  
    } 
  } 
}  
'@  
      } 
  
      if ($BootFile) { 
        if('BDR','BDRE' -contains $Media) { Write-Warning "Bootable image doesn't seem to work with media type $Media" } 
        ($Stream = New-Object -ComObject ADODB.Stream -Property @{Type=1}).Open()  # adFileTypeBinary 
        $Stream.LoadFromFile((Get-Item -LiteralPath $BootFile).Fullname) 
        ($Boot = New-Object -ComObject IMAPI2FS.BootOptions).AssignBootImage($Stream) 
      } 
 
      $MediaType = @('UNKNOWN','CDROM','CDR','CDRW','DVDROM','DVDRAM','DVDPLUSR','DVDPLUSRW','DVDPLUSR_DUALLAYER','DVDDASHR','DVDDASHRW','DVDDASHR_DUALLAYER','DISK','DVDPLUSRW_DUALLAYER','HDDVDROM','HDDVDR','HDDVDRAM','BDROM','BDR','BDRE') 
 
      ($Image = New-Object -com IMAPI2FS.MsftFileSystemImage -Property @{VolumeName=$Title}).ChooseImageDefaultsForMediaType($MediaType.IndexOf($Media)) 
  
      if (!($Target = New-Item -Path $Path -ItemType File -Force:$Force -ErrorAction SilentlyContinue)) { Write-Error -Message "Cannot create file $Path. Use -Force parameter to overwrite if the target file already exists."; break } 
    }  
 
    Process { 
      if($FromClipboard) { 
        if($PSVersionTable.PSVersion.Major -lt 5) { Write-Error -Message 'The -FromClipboard parameter is only supported on PowerShell v5 or higher'; break } 
        $Source = Get-Clipboard -Format FileDropList 
      } 
 
      foreach($item in $Source) { 
        if($item -isnot [System.IO.FileInfo] -and $item -isnot [System.IO.DirectoryInfo]) { 
          $item = Get-Item -LiteralPath $item 
        } 
 
        if($item) { 
          Write-Verbose -Message "Adding item to the target image: $($item.FullName)" 
          try { $Image.Root.AddTree($item.FullName, $true) } catch { Write-Error -Message ($_.Exception.Message.Trim() + ' Try a different media type.') } 
        } 
      } 
    } 
 
    End {  
      if ($Boot) { $Image.BootImageOptions=$Boot }  
      $Result = $Image.CreateResultImage()  
      [ISOFile]::Create($Target.FullName,$Result.ImageStream,$Result.BlockSize,$Result.TotalBlocks) 
      Write-Verbose -Message "Target image ($($Target.FullName)) has been created" 
      $Target 
    } 
  }

  cls
  Write-Host "Veron - Bootable ISO-Creator"
  Write-Host "----------------------------"
  Write-Host ""
  Write-Host ""
  Write-Host ""
  Write-Host "___________________"
  Write-Host "Source-Path      = "
  Write-Host "Destination-Path = "
  Write-Host "Creation...      = "
  Write-Host "___________________"
  New_Entry 0 3 "Press Enter to start..." Yellow
  Read-Host

  New_Entry 0 3 "Please select the Path." Yellow
  Add-Type -AssemblyName System.Windows.Forms
  $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog

  $FolderBrowser.Reset()
  New_Entry 19 6 "<-" Yellow
  $FolderBrowser.Description = "Please select the Source-Path"
  [void]$FolderBrowser.ShowDialog()
  $srcfolder = $FolderBrowser.SelectedPath
  New_Entry 19 6 "$srcfolder" green

  $FolderBrowser.Reset()
  New_Entry 19 7 "<-" Yellow 
  $FolderBrowser.Description = "Please select the ISO-Destination-Path"
  [void]$FolderBrowser.ShowDialog()
  $destfolder = $FolderBrowser.SelectedPath
  New_Entry 19 7 "$destfolder\WinPE.iso" green

  If (!($srcfolder.Length -le 4 -or $destfolder.Length -le 4))
  {
    New_Entry 0 3 "Press Enter to start the ISO-File creation." Yellow
    Read-Host
    New_Entry 19 8 "<-" Yellow
    New_Entry 0 3 "Please wait, the ISO file is being created." Red
    
    Get-ChildItem $Path_IntuneJoin | Copy-Item -Destination $srcfolder -Force
    
    $AutoPilot_Path = -join("$srcfolder", '\sources\$OEM$\$$\provisioning\Autopilot')
    If (!(Test-Path $AutoPilot_Path)) {New-Item -ItemType Directory -Path $AutoPilot_Path | Out-Null}
    Get-ChildItem -Path $Path_Auto | Copy-Item -Destination $AutoPilot_Path -Force
    
    get-childitem $srcfolder -Force | New-IsoFile -Path "$destfolder\WinPE.iso" -BootFile $Path_ISO -Media DVDPLUSR_DUALLAYER -Title "WinPE" | Out-Null
    New_Entry 19 8 "ok" green
    New_Entry 0 3 "Creation completed.                        " green
  }
  else{New_Entry 0 3 "A Source/Destionation-Path is not selected." red}

}

function Autopilot()
{
  #>--------------------------------------------------------------------------------------------------------
  function Install()
  {
    #Install-Module
    If (!(Get-InstalledModule AzureAD -ErrorAction SilentlyContinue))
    {
      New_Entry 0 3 "Install-Modul - AzureAD" Yellow
      Install-Module -Name AzureAD -AllowClobber -Scope AllUsers -Confirm:$false -Force
      New_Entry 0 3 "                       " Yellow
    }
    If (!(Get-InstalledModule WindowsAutopilotIntune -ErrorAction SilentlyContinue))
    {
      New_Entry 0 3 "Install-Modul - WindowsAutopilotIntune" Yellow
      Install-Module -Name WindowsAutopilotIntune -AllowClobber -Scope AllUsers -Confirm:$false -Force
      New_Entry 0 3 "                                      " Yellow
    }
    If (!(Get-InstalledModule Microsoft.Graph.Intune -ErrorAction SilentlyContinue))
    {
      New_Entry 0 3 "Install-Modul - Microsoft.Graph.Intune" Yellow
      Install-Module -Name Microsoft.Graph.Intune -AllowClobber -Scope AllUsers -Confirm:$false -Force
      New_Entry 0 3 "                                      " Yellow
    }
  }
  function Login()
  {
    New_Entry 0 10 "" White
    #Azure-Login
    Do {
      $User = Read-Host "Please enter your Azure-Username"
    }while($User -eq "")

    Do {
      $PWord = Read-Host "Please enter your Azure-Password" -AsSecureString
    }while($PWord -eq "")
    $cred = New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList $User,$PWord
    Connect-MSGraph -Credential $cred -Quiet
  }  
  function Creation()
  {
    New_Entry 0 3 "Please wait, creation started..." Red
    If (Test-Path -Path $Path_Auto) {Remove-Item -Path $Path_Auto -Force}    
    Get-AutoPilotProfile | ConvertTo-AutoPilotConfigurationJSON | Out-File -FilePath "$Path_Auto" -Encoding ASCII
    New_Entry 0 3 "Creation solved                 " Green
  }

  cls
  Write-Host "Veron - Autopilotfile-Creator"
  Write-Host "-----------------------------"
  Write-Host ""
  Write-Host ""
  Write-Host ""
  Write-Host "_____________________"
  Write-Host "Check-Modules      = "
  Write-Host "Login Azure Tenant = "
  Write-Host "Creation JSON-File = "
  Write-Host "JSON-File Path     = "
  Write-Host "_____________________"
  New_Entry 0 3 "Press Enter to start..." Yellow
  Read-Host

  New_Entry 0 3 "Checking needed Modules" Yellow
  New_Entry 21 6 "<-" Yellow
  Install
  New_Entry 21 6 "ok" Green
  
  New_Entry 0 3 "Please enter your Azure-Credentials" Yellow
  New_Entry 21 7 "<-" Yellow
  Login
  New_Entry 21 7 "ok" Green
  
  New_Entry 0 3 "                                   " Yellow
  New_Entry 21 8 "<-" Yellow
  Creation
  New_Entry 21 8 "ok" Green
  New_Entry 21 9 "$Path_Auto" Green  
}

clear-Host
Write-Host ""
Write-Host " -------------------------------"
Write-Host "[ " -NoNewline
Write-Host "Veron - Windows Media-Creator" -NoNewline
Write-Host " ]"
Write-Host " -------------------------------"
Write-Host
Write-Host "Powershell-Policy for Adminscripts is " -NoNewline
IF ($checkPolicy -eq "Unrestricted")
{Write-Host "Unrestricted" -ForegroundColor Green}
else {Write-Host "is not unrestricted" -ForegroundColor red}
Write-Host ""
Write-Host "[" -NoNewline
Write-Host "TOOLS" -NoNewline -ForegroundColor Yellow
Write-Host "]"
Write-Host "[ " -NoNewline
Write-Host "1" -NoNewline -ForegroundColor Green
Write-Host " ]>---- USB-Creator"
Write-Host "[ " -NoNewline
Write-Host "2" -NoNewline -ForegroundColor Green
Write-Host " ]>---- ISO-Creator"
Write-Host "[ " -NoNewline
Write-Host "3" -NoNewline -ForegroundColor Green
Write-Host " ]>---- Autopilot(json)-Creator"
Write-Host "_______________________________________________________"
[int]$selectMenu = Read-Host "Select Nr"
cls
###########################################################################################################################################

Switch ($selectMenu) {
  "1" {
    USBCreator
  }

  "2" {
    ISOCreator
  }
  "3" {
    Autopilot
  }
}

$HOST.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | OUT-NULL
$HOST.UI.RawUI.Flushinputbuffer()