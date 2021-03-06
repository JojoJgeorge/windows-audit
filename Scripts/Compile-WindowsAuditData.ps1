#requires -version 2
<#
    .SYNOPSIS
    Name: Compile-WindowsAuditData.ps1
    Parses the results from Get-WindowsAuditData.ps1
    
    .DESCRIPTION
    This script is a thin wrapper to provide ease of use for the filters in
    this solution. The filters provide a way to parse the same data repeatedly
    to create different views of the data, this will validate that the filter
    chosen is present and call the filter multiple times providing each file from
    the RawData directory.

    .EXAMPLE
    This script is not designed for standalone usage, please see the Invoke-WindowsAudit.ps1
    file in the root of this solution.
#>

[CmdletBinding()]
Param(
    # Name of the filter to use for parsing the results
    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [String]$Filter
)

#---------[ Global Declarations ]---------

# Get the execution policy value and set to unrestructed
$ExecutionPolicy = Get-ExecutionPolicy;
Set-ExecutionPolicy Unrestricted -Force;

# EAP to stop so we can trap errors in catch blocks
$ErrorActionPreference = "Stop";

# Trigger so we know something went wrong during the process
$WarningTrigger = $False;

#---------[ Imports ]---------

# Import our functions from the lib module
try {
    Import-Module ".\Scripts\Audit-Functions.psm1" -DisableNameChecking -Force;
}
catch {
    Write-ShellMessage -Message "There was a problem importing the functions library" -Type ERROR -ErrorRecord $_;
    Exit(1);
}

#---------[ Extended Validation ]---------

# Test whether the filter exists and get the path
try {
    $FilterPath = ".\Filters\$Filter.ps1";
    if (!(Test-Path $FilterPath)) {
        throw [System.IO.FileNotFoundException] "The file '$FilterPath' does not exist";
    }
}
catch {
    Write-ShellMessage -Message "There was a problem validating the selected filter" -Type ERROR -ErrorRecord $_;
    Exit(1);
}

#---------[ Main() ]---------

# Get a list of the CLI XML files to process
try {
    Write-ShellMessage -Message "Getting list of CLI XML files to process" -Type INFO;
    $CliXmlFilesToProcess = Get-ChildItem ".\Output\RawData\*cli.xml";
}
catch {
    Write-ShellMessage -Message "There was a problem getting the list of CLI XML files to process" -Type ERROR -ErrorRecord $_;
    Exit(1);
}

# Enumerate the collection
$CliXmlFilesToProcess | %{
    # Get the filename and let the user know what we're doing
    $FileName = $_.Name;
    Write-ShellMessage -Message "Processing file '$FileName'" -Type INFO;

    # Get the CLI XML back into a PSCustomObject
    $HostInformation = Import-Clixml -Path $_.FullName;
    
    # And pass the result on to the correct filter for execution
    & $FilterPath -HostInformation $HostInformation;
}

#---------[ Set the exec policy back to what it was ]---------
Set-ExecutionPolicy $ExecutionPolicy -Force;

#---------[ Fin ]---------
Exit;