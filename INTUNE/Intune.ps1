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
$currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
$testadmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if ($testadmin -eq $false) {
  Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}" -elevated' -f ($myinvocation.MyCommand.Definition))
  exit $LASTEXITCODE
}

function New_Entry ([int]$xposi,[int]$yposi,[string]$Text,[System.ConsoleColor]$Color) 
{
    $position=$Host.ui.RawUI.CursorPosition
    $position.x = $xposi
    $position.y = $yposi
    $Host.ui.RawUI.CursorPosition=$position
    Write-Host $Text -ForegroundColor $Color
}
#>-----------------------------------------------------------------------------
function WindowsUpdate()
{
    # Get Nuget module (and dependencies)
    $module = Import-Module NuGet -PassThru -ErrorAction Ignore
    if (-not $module) 
    {
      Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Confirm:$false -Force | Out-Null
    }
    Import-Module NuGet -Scope Global | Out-Null

  # Get pswindowsupdate module (and dependencies)
  $module = Import-Module pswindowsupdate -PassThru -ErrorAction Ignore
  if (-not $module) {
    Write-Host "Installing module pswindowsupdate"
    Install-Module pswindowsupdate -Confirm:$false -Force
  }
  Import-Module pswindowsupdate -Scope Global
  cls
  New_Entry 0 0 "Please wait, checking available updates." Red
  Get-WindowsUpdate -UpdateType Driver -Install -AcceptAll
  cls
  New_Entry 0 0 "Check finished." Green
}
function IntuneJoin()
{
  function fu-Install()
  {  
    # Get Nuget module (and dependencies)
    $module = Import-Module NuGet -PassThru -ErrorAction Ignore
    if (-not $module) 
    {
      Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Confirm:$false -Force | Out-Null
    }
    Import-Module NuGet -Scope Global | Out-Null
    #>---------------------------------------------------------------
    # Get AzureADPreview module (and dependencies)
    $module = Import-Module AzureAD -PassThru -ErrorAction Ignore
    if (-not $module) 
    {
       Install-Module AzureAD -Confirm:$false -AllowClobber -Force | Out-Null
    }
    Import-Module AzureAD -Scope Global | Out-Null
    #>---------------------------------------------------------------
    # Get Microsoft.Graph.Intune module (and dependencies)
    $module = Import-Module Microsoft.Graph.Intune -PassThru -ErrorAction Ignore
    if (-not $module) 
    {
       Install-Module Microsoft.Graph.Intune -Confirm:$false -AllowClobber -Force | Out-Null
    }
    Import-Module Microsoft.Graph.Intune -Scope Global | Out-Null
    #>---------------------------------------------------------------
    # Get WindowsAutopilotIntune module (and dependencies)
    $module = Import-Module WindowsAutopilotIntune -PassThru -ErrorAction Ignore
    if (-not $module) 
    {
       Install-Module WindowsAutopilotIntune -Confirm:$false -AllowClobber -Force | Out-Null
    }
    Import-Module WindowsAutopilotIntune -Scope Global | Out-Null
    #>-----------------------------------------------------------
  
  }
  function fu-Login()
  {
    New_Entry 0 10 "" White

    Connect-MSGraph -Quiet
  }
  function fu-AutopilotProfiJSON()
  {
   
    $AutoPilot_Path = 'C:\Windows\Provisioning\Autopilot'
    $AutoPilot_Full = -join($AutoPilot_Path, '\', 'AutoPilotConfigurationFile.json')
    If (!(Test-Path $AutoPilot_Path)) {New-Item -ItemType Directory -Path $AutoPilot_Path | Out-Null}
       
    Get-AutoPilotProfile | ConvertTo-AutoPilotConfigurationJSON | Out-File -FilePath $AutoPilot_Full -Encoding ASCII | Out-Null
  }
  function fu-WindowsAutoPilotInfo()
  {
    [CmdletBinding()]
    param(
      [Parameter(Mandatory=$False,ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Position=0)][alias("DNSHostName","ComputerName","Computer")] [String[]] $Name = @("localhost"),
      [Parameter(Mandatory=$False)] [String] $OutputFile = "", 
      [Parameter(Mandatory=$False)] [String] $GroupTag = "",
      [Parameter(Mandatory=$False)] [Switch] $Append = $false,
      [Parameter(Mandatory=$False)] [System.Management.Automation.PSCredential] $Credential = $null,
      [Parameter(Mandatory=$False)] [Switch] $Partner = $false,
      [Parameter(Mandatory=$False)] [Switch] $Force = $false,
      [Parameter(Mandatory=$False)] [Switch] $Online = $false,
      [Parameter(Mandatory=$False)] [String] $AddToGroup = "",
      [Parameter(Mandatory=$False)] [Switch] $Assign = $false
    )

    Begin
    {
      # Initialize empty list
      $computers = @()

      # If online, make sure we are able to authenticate
      if ($Online) {
    
        # Connect
        $graph = Connect-MSGraph
        if ($AddToGroup)
        {
          $aadId = Connect-AzureAD -AccountId $graph.UPN
        }

        # Force the output to a file
        if ($OutputFile -eq "")
        {
          $OutputFile = "$($env:TEMP)\autopilot.csv"
        } 
      }
    }

    Process
    {
      foreach ($comp in $Name)
      {
        $bad = $false

        # Get a CIM session
        if ($comp -eq "localhost") {
          $session = New-CimSession
        }
        else
        {
          $session = New-CimSession -ComputerName $comp -Credential $Credential
        }

        # Get the common properties.
        Write-Verbose "Checking $comp"
        $serial = (Get-CimInstance -CimSession $session -Class Win32_BIOS).SerialNumber

        # Get the hash (if available)
        $devDetail = (Get-CimInstance -CimSession $session -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'")
        if ($devDetail -and (-not $Force))
        {
          $hash = $devDetail.DeviceHardwareData
        }
        else
        {
          $bad = $true
          $hash = ""
        }

        # If the hash isn't available, get the make and model
        if ($bad -or $Force)
        {
          $cs = Get-CimInstance -CimSession $session -Class Win32_ComputerSystem
          $make = $cs.Manufacturer.Trim()
          $model = $cs.Model.Trim()
          if ($Partner)
          {
            $bad = $false
          }
        }
        else
        {
          $make = ""
          $model = ""
        }

        # Getting the PKID is generally problematic for anyone other than OEMs, so let's skip it here
        $product = ""

        # Depending on the format requested, create the necessary object
        if ($Partner)
        {
          # Create a pipeline object
          $c = New-Object psobject -Property @{
            "Device Serial Number" = $serial
            "Windows Product ID" = $product
            "Hardware Hash" = $hash
            "Manufacturer name" = $make
            "Device model" = $model
          }
          # From spec:
          #	"Manufacturer Name" = $make
          #	"Device Name" = $model

        }
        elseif ($GroupTag -ne "")
        {
          # Create a pipeline object
          $c = New-Object psobject -Property @{
            "Device Serial Number" = $serial
            "Windows Product ID" = $product
            "Hardware Hash" = $hash
            "Group Tag" = $GroupTag
          }
        }
        else
        {
          # Create a pipeline object
          $c = New-Object psobject -Property @{
            "Device Serial Number" = $serial
            "Windows Product ID" = $product
            "Hardware Hash" = $hash
          }
        }

        # Write the object to the pipeline or array
        if ($bad)
        {
          # Report an error when the hash isn't available
          Write-Error -Message "Unable to retrieve device hardware data (hash) from computer $comp" -Category DeviceError
        }
        elseif ($OutputFile -eq "")
        {
          $c
        }
        else
        {
          $computers += $c
        }

        Remove-CimSession $session
      }
    }

    End
    {
      if ($OutputFile -ne "")
      {
        if ($Append)
        {
          if (Test-Path $OutputFile)
          {
            $computers += Import-CSV -Path $OutputFile
          }
        }
        if ($Partner)
        {
          $computers | Select "Device Serial Number", "Windows Product ID", "Hardware Hash", "Manufacturer name", "Device model" | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''} | Out-File $OutputFile
        }
        elseif ($GroupTag -ne "")
        {
          $computers | Select "Device Serial Number", "Windows Product ID", "Hardware Hash", "Group Tag" | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''} | Out-File $OutputFile
        }
        else
        {
          $computers | Select "Device Serial Number", "Windows Product ID", "Hardware Hash" | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''} | Out-File $OutputFile
        }
      }
      if ($Online)
      {
        # Add the devices
        $importStart = Get-Date
        $imported = @()
        $computers | % {
          $imported += Add-AutopilotImportedDevice -serialNumber $_.'Device Serial Number' -hardwareIdentifier $_.'Hardware Hash' -groupTag $_.'Group Tag'
        }

        # Wait until the devices have been imported
        $processingCount = 1
        while ($processingCount -gt 0)
        {
          $current = @()
          $processingCount = 0
          $imported | % {
            $device = Get-AutopilotImportedDevice -id $_.id
                if ($device.state.deviceImportStatus -eq "unknown") {
                    $processingCount = $processingCount + 1
            }
            $current += $device
          }
            $deviceCount = $imported.Length
            Write-Host "Waiting for $processingCount of $deviceCount to be imported"
            if ($processingCount -gt 0){
                Start-Sleep 30
            }
        }
        $importDuration = (Get-Date) - $importStart
        $importSeconds = [Math]::Ceiling($importDuration.TotalSeconds)
        Write-Host "All devices imported.  Elapsed time to complete import: $importSeconds seconds"
		
        # Wait until the devices can be found in Intune (should sync automatically)
        $syncStart = Get-Date
        $processingCount = 1
        while ($processingCount -gt 0)
        {
          $autopilotDevices = @()
          $processingCount = 0
          $current | % {
            $device = Get-AutopilotDevice -id $_.state.deviceRegistrationId
                if (-not $device) {
                    $processingCount = $processingCount + 1
            }
            $autopilotDevices += $device					
          }
            $deviceCount = $autopilotDevices.Length
            Write-Host "Waiting for $processingCount of $deviceCount to be synced"
            if ($processingCount -gt 0){
                Start-Sleep 30
            }
        }
        $syncDuration = (Get-Date) - $syncStart
        $syncSeconds = [Math]::Ceiling($syncDuration.TotalSeconds)
        Write-Host "All devices synced.  Elapsed time to complete sync: $syncSeconds seconds"

        # Add the device to the specified AAD group
        if ($AddToGroup)
        {
          $aadGroup = Get-AzureADGroup -Filter "DisplayName eq '$AddToGroup'"
          $autopilotDevices | % {
            $aadDevice = Get-AzureADDevice -ObjectId "deviceid_$($_.azureActiveDirectoryDeviceId)"
            Add-AzureADGroupMember -ObjectId $aadGroup.ObjectId -RefObjectId $aadDevice.ObjectId
          }
          Write-Host "Added devices to group '$AddToGroup' ($($aadGroup.ObjectId))"
        }

        # Wait for assignment (if specified)
        if ($Assign)
        {
          $assignStart = Get-Date
          $processingCount = 1
          while ($processingCount -gt 0)
          {
            $processingCount = 0
            $autopilotDevices | % {
              $device = Get-AutopilotDevice -id $_.id -Expand
              if (-not ($device.deploymentProfileAssignmentStatus.StartsWith("assigned"))) {
                $processingCount = $processingCount + 1
              }
            }
            $deviceCount = $autopilotDevices.Length
            Write-Host "Waiting for $processingCount of $deviceCount to be assigned"
            if ($processingCount -gt 0){
              Start-Sleep 30
            }	
          }
          $assignDuration = (Get-Date) - $assignStart
          $assignSeconds = [Math]::Ceiling($assignDuration.TotalSeconds)
          Write-Host "Profiles assigned to all devices.  Elapsed time to complete assignment: $assignSeconds seconds"	
        }
      }
    }

  }

  #>--------------------------------------------------------------------------------------------------------
  $CSVTool = Split-Path $script:MyInvocation.MyCommand.Path
  $Path_Tools = -join($CSVTool, "\CSV\")
  $path = -join("$Path_Tools", "$env:COMPUTERNAME.csv")
  If (!(Test-Path -Path $Path_Tools)) {New-Item -ItemType Directory -Path $Path_Tools | Out-Null}

  cls
  Write-Host "INTUNE JOIN"
  Write-Host "-----------"
  Write-Host ""
  Write-Host ""
  Write-Host ""
  Write-Host "________________________"
  Write-Host "Check Modules         = "
  Write-Host "Login Azure Tenant    = "
  Write-Host "Creation JSON-File    = "
  Write-Host "Creation 4kHashfile   = "
  Write-Host "Destination Path      = "
  Write-Host "Intune AutoJoin       = "
  
  New_Entry 0 3 "Check Modules" Yellow
  New_Entry 24 6 "<-" Yellow
  fu-Install
  New_Entry 24 6 "ok" Green
  
  New_Entry 0 3 "Please enter your Azure-Credentials" Yellow
  New_Entry 24 7 "<-" Yellow
  fu-Login
  New_Entry 24 7 "ok" Green
  
  New_Entry 0 3 "                                   " Yellow
  New_Entry 24 8 "<-" Yellow
  fu-AutopilotProfiJSON
  New_Entry 24 8 "ok" Green

  New_Entry 24 9 "<-" Yellow
  fu-WindowsAutoPilotInfo -OutputFile $path
  New_Entry 24 9 "ok" Green
  New_Entry 24 10 $path Green

  New_Entry 24 11 "<-" Yellow
  fu-WindowsAutoPilotInfo -Online
  New_Entry 24 11 "ok" Green
  
  New_Entry 24 12 "" White
}

clear-Host
Write-Host ""
Write-Host " -------------------------------"
Write-Host "[ " -NoNewline
Write-Host "Intune - Deployment" -NoNewline
Write-Host " ]"
Write-Host " -------------------------------"
Write-Host ""
Write-Host "[" -NoNewline
Write-Host "TOOLS" -NoNewline -ForegroundColor Yellow
Write-Host "]"
Write-Host "[ " -NoNewline
Write-Host "1" -NoNewline -ForegroundColor Green
Write-Host " ]>---- Windows-Driverupdate"
Write-Host "[ " -NoNewline
Write-Host "2" -NoNewline -ForegroundColor Green
Write-Host " ]>---- Intune Join"
Write-Host "_______________________________________________________"
[int]$selectMenu = Read-Host "Select Nr"
cls
###########################################################################################################################################

Switch ($selectMenu) {
  "1" {
    WindowsUpdate
  }
  
  "2" {
    IntuneJoin
  }
}