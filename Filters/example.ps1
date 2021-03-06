<#
    .SYNOPSIS
    Name: Example.ps1
    Data filter to parse and write the output from Get-WindowsAuditData.ps1
    
    .DESCRIPTION
    This script will take a $HostInformation object from the Get-WindowsAuditData.ps1
    script and parse it using a defined filter, then write the information to an excel
    file.

    You do not need to call this file directly, as it's used in conjunction with the
    Compile-WindowsAuditData.ps1 script.

    The filter needs to be defined as a single PSCustomObject, with named key/value
    pairs indicating the name (key) of the section you wish to create, along with the
    actual content (value) of that section. Each section will become a worksheet in
    the final output file.

    .PARAMETER HostInformation [PSCustomObject]
    The PSCustomObject that contains the audit data output you wish to compile and write
    to disk.
    
    .EXAMPLE
    .\Example.ps1 -HostInformation $HostInformation
    This will apply the filter to the $HostInformation object supplied, and write the
    formatted output data to an excel file.

    #requires -version 2
#>

[Cmdletbinding()]
Param(
    [Parameter(Mandatory=$True,ValueFromPipeline=$True)]
    [ValidateNotNullOrEmpty()]
    [PSCustomObject]$HostInformation
)

#---------[ Global Declarations ]---------

# EAP to stop so we can trap errors in catch blocks
$ErrorActionPreference = "Stop";

# Trigger so we know something went wrong during the process
$WarningTrigger = $False;

#---------[ Imports ]---------

# Import our functions from the lib module
try {
    Write-ShellMessage -Message "Importing functions library" -Type INFO;
    Import-Module ".\Scripts\Audit-Functions.psm1" -DisableNameChecking;
}
catch {
    Write-ShellMessage -Message "There was a problem importing the functions library" -Type ERROR -ErrorRecord $_;
    Exit(1);
}

#---------[ Main() ]---------

# Build the filter object
try {
    Write-ShellMessage -Message "Building output object" -Type INFO;
    $Filter = New-Object PSCustomObject -Property @{
        "00_System Information" = $([PSCustomObject]@{
            "HostName"                  = $HostInformation.OS.CSName;
            "Domain Name"               = $HostInformation.SystemInfo.SystemInfo.Domain;
            "IPv4 Address"              = $((($HostInformation.Networking.AdapterInformation | ?{$_.IPAddress} | select IPAddress).IPAddress|?{$_| Is-Ipv4Address}) -Join ", ");
            "OS"                        = $HostInformation.OS.Caption;
            "Uptime"                    = $(Get-DateTimeDifference -CompareDateTime $([Management.ManagementDateTimeConverter]::ToDateTime($HostInformation.OS.LastBootUpTime)));
            "Region/Locale"             = $(Get-LocaleFromWMICode -WMILocaleCode $HostInformation.OS.Locale);
            "Timezone"                  = $(Get-TimeZoneDisplayName -UTCOffsetMinutes $HostInformation.OS.CurrentTimeZone);
            "System Type"               = $(if($HostInformation.SystemInfo.IsVirtualMachine){"Virtual Machine"}else{"Physical Machine"});
            "Location"                  = $HostInformation.SystemInfo.Location;
            "WSUS Server"               = $HostInformation.WindowsUpdates.WSUSServer;
            "PowerShell Version"        = $HostInformation.Management.PowerShellVersion;
            ".NET Version"              = $HostInformation.Management.DotNetVersion;
            "CPU"                       = $(($HostInformation.Compute.Name | Select -First 1) + " x$($HostInformation.Compute.Name.Count)");
            "CPU Use % (Total)"         = $HostInformation.SystemInfo.CPUPercentInUse;
            "Total Physical Memory"     = $HostInformation.Memory.WindowsMemory.TotalPhysicalMemory;
            "Available Physical Memory" = $HostInformation.Memory.WindowsMemory.AvailablePhysicalMemory;
            "Virtual Memory Max Size"   = $HostInformation.Memory.WindowsMemory.VirtualMemoryMaxSize;
            "Virtual Memory Available"  = $HostInformation.Memory.WindowsMemory.VirtualMemoryAvailable;
            "Virtual Memory InUse"      = $HostInformation.Memory.WindowsMemory.VirtualMemoryInUse;    
        });
        "01_Network Interfaces" = $($HostInformation.Networking.AdapterInformation | %{
            [PSCustomObject]@{
                "HostName"      = $HostInformation.OS.CSName;
                "Description"   = $_.Description
                "Adapter Index" = $_.Index;
                "IPv4 Address"  = $(($_.IPAddress | ?{Is-Ipv4Address $_}) -Join  ", ");
                "IPv6 Address"  = $(($_.IPAddress | ?{Is-Ipv6Address $_}) -Join  ", ");
                "Domain Name"   = $_.DNSDomain;
                "Subnet Mask"   = $($_.IPSubnet | Select -First 1);
                "Gateway"       = $($_.DefaultIPGateway -join ", ");
                "DNS Servers"   = $($_.DNSServerSearchOrder -join ", ");
            }
        });
        "02_Firewall Rules" = $($HostInformation.Networking.FirewallRules | %{
            [PSCustomObject]@{
                "HostName"      = $HostInformation.OS.CSName;
                "Name" = $_.Name
                "Description" = $_.Description
                "Local Ports" = $_.LocalPorts
                "Remote Ports" = $_.RemotePorts
                "Local Addresses" = $_.LocalAddresses
                "Remote Addresses" = $_.RemoteAddresses
                "Direction" = $(Switch($_.Direction){1{"Inbound"};2{"Outbound"};default{$_.Direction}});
            }
        });
        "03_TLS Certificates" = $($HostInformation.TLSCertificates | ?{!$_.PSIsContainer} | %{
            [PSCustomObject]@{
                "HostName"        = $HostInformation.OS.CSName;
                "Friendly Name"   = $_.FriendlyName;
                "Expires"         = $_.NotAfter;
                "Thumbprint"      = $_.Thumbprint;
                "Has Private Key" = $_.HasPrivateKey;
                "Issuer"          = $_.Issuer;
            }
        });
        "04_Storage Disks" = $($HostInformation.Storage.PhysicalDisks | %{
            [PSCustomObject]@{
                "HostName"       = $HostInformation.OS.CSName;
                "Disk Type"      = $_.Caption;
                "Interface Type" = $_.InterfaceType;
                "Media Type"     = $_.MediaType;
                "Size"           = $([Math]::Round(($_.Size / 1GB)).ToString() + " GB");
            }
        });
        "05_Storage Volumes" = $($HostInformation.Storage.Volumes | %{
            [PSCustomObject]@{
                "HostName"          = $HostInformation.OS.CSName;
                "Caption"           = $_.Caption;
                "Mount Point"       = $_.DriveLetter;
                "Type"              = $(ConvertTo-DiskDriveTypeString -DriveTypeEnum $_.DriveType);
                "Filesystem"        = $_.FileSystem;
                "Boot Volume"       = $_.BootVolume;
                "System Volume"     = $_.SystemVolume;
                "Indexing Enabled"  = $_.IndexingEnabled;
                "Page file present" = $_.PageFilePresent;
                "Compressed"        = $_.Compressed;
                "Free Space"        = $([Math]::Round(($_.FreeSpace / 1GB),2).ToString() +" GB");
                "Used Space"        = $([Math]::Round((($_.Capacity - $_.Freespace) / 1GB),2).ToString() +" GB");
                "Total Size"        = $([Math]::Round(($_.Capacity / 1GB),2).ToString() +" GB");
            }
        });
        "06_Shared Folders and Drives" = $(
            # Shared folders
            $HostInformation.Storage.SharedFolders | %{
                [PSCustomObject]@{
                    "HostName"                  = $HostInformation.OS.CSName;
                    "Shared Folder Path"        = $_.Path;
                    "Shared Folder Name"        = $_.Name;
                    "Shared Folder Description" = $_.Description;
                    "Shared Folder Permissions" = $_.SharePermissions;
                    "Mounted Drive Path"        = "N/A";
                    "Mounted Drive Letter"      = "N/A";
                }
            };
            # Mounted drives
            $HostInformation.Storage.MountedDrives | %{
                [PSCustomObject]@{
                    "HostName"                  = $HostInformation.OS.CSName;
                    "Shared Folder Path"        = "N/A";
                    "Shared Folder Name"        = "N/A";
                    "Shared Folder Description" = "N/A";
                    "Shared Folder Permissions" = "N/A";
                    "Mounted Drive Path"        = $_.ProviderName;
                    "Mounted Drive Letter"      = $_.Name;
                }
            };
        );
        "07_Applications" = $(
            # 32 Bit
            $HostInformation.Applications.x32 | %{
                [PSCustomObject]@{
                    "HostName"        = $HostInformation.OS.CSName;
                    "Display Name"    = $_.DisplayName;
                    "Display Version" = $_.DisplayVersion;
                    "Publisher"       = $_.Publisher;
                    "Install Date"    = $_.InstallDate;
                    "Install Type"    = "32-Bit";
                }
            };
            # 64 Bit
            $HostInformation.Applications.x64 | %{
                [PSCustomObject]@{
                    "HostName"        = $HostInformation.OS.CSName;
                    "Display Name"    = $_.DisplayName;
                    "Display Version" = $_.DisplayVersion;
                    "Publisher"       = $_.Publisher;
                    "Install Date"    = $_.InstallDate;
                    "Install Type"    = "64-Bit";
                }
            };
        );
        "08_Windows Features" = $($HostInformation.RolesAndFeatures | ?{$_.Installed} | Sort -Property Path | %{
            [PSCustomObject]@{
                "HostName"     = $HostInformation.OS.CSName;
                "Display Name" = $_.DisplayName;
                "Name"         = $_.Name;
                "Feature Type" = $_.FeatureType;
                "Path"         = $_.Path;
                "Subfeatures"  = $_.Subfeatures;
            }
        });
        "09_Scheduled Tasks" = $($HostInformation.ScheduledTasks | %{
            [PSCustomObject]@{
                "HostName"      = $HostInformation.OS.CSName;
                "Name"          = $_.Name;
                "Enabled"       = $_.Enabled;
                "Actions"       = $_.Actions;
                "Last Run Time" = $_.LastRunTime;
                "Last Result"   = $_.LastResult;
            }
        });
    }
}
catch {
    Write-ShellMessage -Message "There was a problem building the output object" -Type ERROR -ErrorRecord $_;
    Exit(1);
}

# Now we need to eumerate the $Filter object's properties and write out
Write-ShellMessage -Message "Begining data write to disk" -Type INFO;
$Filter.PSObject.Properties | Sort -Property Name | %{
    
    try {
        # Get the section name and value
        $SectionName = $_.Name;
        $SectionValue = $_.Value | Select -Property *;

        # Get the hostname for error writing and define the output file
        $HostName = $HostInformation.OS.CSName;
        $FilePath = (Resolve-Path $($MyInvocation.PSScriptRoot + "\..\")).Path + "Windows-Audit-Data.xlsx";

        # Export to File
        if ($SectionValue) {
            Write-ShellMessage -Message "Exporting '$SectionName' to '$FilePath' for host '$HostName'" -Type INFO;
            $SectionValue | .\Scripts\Export-XLSX.ps1 -Path $FilePath -WorksheetName $SectionName -Append;
        }
        else {
            Write-ShellMessage -Message "Section '$SectionName' for host '$HostName' is null; skipping" -Type WARNING;
        }
    }
    catch {
        # Write out and set our warning trigger
        Write-ShellMessage -Message "There was an error attempting to compile data for '$Hostname' and write it to disk" -Type ERROR -ErrorRecord $_;
        $WarningTrigger = $True;

        # Write to error log file
        Write-ErrorLog -HostName $HostName -EventName "Compilation" -Exception $($_.Exception.Message);
    }
}

#---------[ Fin ]---------

if ($WarningTrigger) {
    $FinalMessage = "Audit data compilation has completed with warnings";
    Write-ShellMessage -Message $FinalMessage -Type WARNING;
}
else {
    $FinalMessage = "Audit data compilation has completed successfully";
    Write-ShellMessage -Message $FinalMessage -Type SUCCESS;
}

Exit;