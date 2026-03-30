<#
.SYNOPSIS
This script configures a Windows computer for Microsoft eCDN Local Network Access.

.DESCRIPTION
This script adds registry keys to a Windows computer for enabling Local Network Access solely for the domains required by Microsoft eCDN on the following browsers:
    - Microsoft Edge
    - Google Chrome

The LocalNetworkAccessAllowedForUrls policy allows specific websites to access resources on local network endpoints, which is essential for Microsoft eCDN's peer-to-peer functionality. Without this policy configuration, browser-based clients may be prevented from establishing peer-to-peer connections within your organizational network.

Note: Firefox support is not yet required as Firefox hasn't shipped Local Network Access restrictions to the release channel as of the creation of this script in March 2026.

.PARAMETER eCDN_domain
The domain to add to the registry keys. Default domains include *.ecdn.teams.microsoft.com, *.ecdn.teams.cloud.microsoft, https://teams.microsoft.com, https://teams.cloud.microsoft, and https://engage.cloud.microsoft/

.EXAMPLE
.\Enable-LNA-for-eCDN.ps1
# This will add the default eCDN domains to the relevant registry keys

.EXAMPLE
.\Enable-LNA-for-eCDN.ps1 -eCDN_domain "https://teams.cloud.microsoft"
# This will add the specified domain to the relevant registry keys

.EXAMPLE
.\Enable-LNA-for-eCDN.ps1 -Enumerated
# This will enumerate all eCDN domains in the registry keys instead of using wildcards (*)

.NOTES
Must be run as an Administrator.
As of May 22nd 2025, the upcoming .cloud.microsoft domain migration targets were added to this script.
At some point in the future, the old domains will be deprecated.
This policy should be configured alongside the WebRtcLocalIpsAllowedUrls policy for full Microsoft eCDN peer-to-peer functionality.  For a sister script, see https://github.com/PeerDiego/Teams/blob/diego-review/eCDN/Disable-mDNS-for-eCDN.ps1
Author: Diego Reategui | Github username: PeerDiego

.OUTPUTS
None

.INPUTS
None

.LINK
See more regarding configuring Local Network Access Policy for Microsoft eCDN here: https://learn.microsoft.com/ecdn/how-to/configure-local-network-access-policy
This script complements the Disable-mDNS-for-eCDN.ps1 script found here: https://learn.microsoft.com/ecdn/how-to/disable-mdns
#>
[cmdletbinding(DefaultParameterSetName="Default")] 
param(
    [Parameter(
        Mandatory=$false, 
        ParameterSetName="Default", 
        HelpMessage="Specify the eCDN domain to add to the registry keys. Default domains include *.ecdn.teams.microsoft.com, *.ecdn.teams.cloud.microsoft, https://teams.microsoft.com, https://teams.cloud.microsoft, and https://engage.cloud.microsoft/")]
    [string]
    $eCDN_domain,
    [Parameter(
        ParameterSetName="Add all", 
        HelpMessage="Enumerate all eCDN domains in the registry keys instead of using a wildcard (*)")]
    [switch]
    $Enumerated = $false
)

if (-not [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")) {
    Write-Host "This script must be run as an Administrator" -ForegroundColor Red
    return
}

$all_eCDN_Domains = @{
    "Default" = @(
        "[*.]ecdn.teams.microsoft.com",
        "[*.]ecdn.teams.cloud.microsoft"
    )
    "Enumerated" = @(
        "https://sdk.ecdn.teams.microsoft.com",
        "https://sdk.ecdn.teams.cloud.microsoft",
        "https://sdk.msit.ecdn.teams.microsoft.com",
        "https://sdk.msit.ecdn.teams.cloud.microsoft"
    )
    "Constant" = @(
        "https://teams.microsoft.com",
        "https://teams.cloud.microsoft",
        "https://engage.cloud.microsoft/"
    )
}

$Domains_to_add = switch ($eCDN_domain) {
    ({-not $eCDN_domain -and -not $Enumerated}) {
        $all_eCDN_Domains["Constant"] + $all_eCDN_Domains["Default"]
    }
    ({$Enumerated}) {
        $all_eCDN_Domains["Constant"] + $all_eCDN_Domains["Enumerated"]
    }
    default { @($eCDN_domain) }
}

$HKLM_SW_Policies_Path = "HKLM:\SOFTWARE\Policies"

# Firefox is not yet supported as they haven't shipped Local Network Access restrictions
$browser_list = @(
    @{
        name = "Microsoft Edge";
        executable = "msedge.exe"; 
        reg_path = "$HKLM_SW_Policies_Path\Microsoft\Edge";
        LocalNetworkAccessKey = "LocalNetworkAccessAllowedForUrls"
    },
    @{
        name = "Google Chrome";
        executable = "chrome.exe"; 
        reg_path = "$HKLM_SW_Policies_Path\Google\Chrome";
        LocalNetworkAccessKey = "LocalNetworkAccessAllowedForUrls"
    }
)

function _create_RegKey_if_not_exists($key_path) {
    $key = Get-Item -Path $key_path -ErrorAction SilentlyContinue
    if (!$key) {
        New-Item -Path $key_path -ErrorAction SilentlyContinue -Force | Out-Null
        Write-Verbose "Created key: $key_path"
    }
    else {
        Write-Verbose "Key already exists: $key_path"
    }
}

function Add-LocalNetworkAccessAllowedUrl {
    param (
        [Parameter(Mandatory=$true, HelpMessage="URL is required")]
        [string] $URL,

        [Parameter(Mandatory=$true, HelpMessage="Browser is required")]
        $Browser
    )
    Write-Verbose "Adding to $($Browser.name)'s Local Network Access Allowed URLs list $URL"
    $browser_path = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$($Browser.executable)" -ErrorAction SilentlyContinue).'(Default)'
    if ($browser_path) {
        $browser_version = (Get-Item -Path $browser_path -ErrorAction SilentlyContinue).VersionInfo
        if ($browser_version) {
            Write-Host " $($Browser.name) v.$($browser_version.FileVersion) found " -ForegroundColor DarkGray
        }
        else {
            Write-Host " $($Browser.name) purportedly installed but unable to determine version info." -BackgroundColor Red -ForegroundColor White
            Write-Host "Proceeding with adding registry key(s) to enable Local Network Access for $($Browser.name) Browser" -ForegroundColor Yellow
        }

        # create the registry keys if they don't exist
        $Browser_Company, $Browser_Name = $Browser.name.Split()
        $Company_KeyPath = Join-Path $HKLM_SW_Policies_Path $Browser_Company
        _create_RegKey_if_not_exists $Company_KeyPath

        $Browser_KeyPath = Join-Path $Company_KeyPath $Browser_Name
        _create_RegKey_if_not_exists $Browser_KeyPath

        $LocalNetworkAccessAllowedUrls_KeyPath = Join-Path $Browser_KeyPath $Browser.LocalNetworkAccessKey
        _create_RegKey_if_not_exists $LocalNetworkAccessAllowedUrls_KeyPath

        $LocalNetworkAccessAllowedUrls = Get-Item -Path $LocalNetworkAccessAllowedUrls_KeyPath -ErrorAction SilentlyContinue
        if (!$LocalNetworkAccessAllowedUrls) {
            Write-Host "Failed to create key(s) >_>" -ForegroundColor Red
            return
        }
        $value_names = $LocalNetworkAccessAllowedUrls.GetValueNames()
        foreach ($value_name in $value_names) {
            $value = $LocalNetworkAccessAllowedUrls.GetValue($value_name)
            Write-Verbose "Found $($LocalNetworkAccessAllowedUrls.GetValueKind($value_name)) $value_name with value $value"
            if ($value -eq $URL) {
                Write-Host "eCDN domain already exists in $($LocalNetworkAccessAllowedUrls.GetValueKind($value_name)) $value_name" -ForegroundColor DarkGreen
                return
            }
        }
        # create new value
        $value_name = $value_names.Count + 1
        while ($value_name -in $value_names) {
            $value_name++
        }
        try {
            New-ItemProperty -Path $LocalNetworkAccessAllowedUrls_KeyPath -Name $value_name -PropertyType String -Value $URL -ErrorAction Stop -Force | Out-Null
            Write-Verbose "eCDN domain added to $($LocalNetworkAccessAllowedUrls.GetValueKind($value_name)) $value_name"
            Write-Host "Registry key to enable Local Network Access for $Browser_Name Browser was created" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to create registry key to enable Local Network Access for $Browser_Name Browser" -ForegroundColor Red
        }
    }
    else {
        Write-Host " $($browser.name) not found" -BackgroundColor DarkGray -ForegroundColor Black
        return
    }
}

foreach ($domain in $Domains_to_add) {
    Write-Host "Adding to Local Network Access allowed eCDN domains lists $domain" -ForegroundColor Yellow
    foreach ($browser in $browser_list) {
        . Add-LocalNetworkAccessAllowedUrl -URL $domain -Browser $browser
        Write-Host ""
    }
    Write-Host ""
}
