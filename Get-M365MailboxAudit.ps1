# ============================================================================
# Script: Get-M365MailboxAudit.ps1
# Purpose: Audit Exchange Online mailboxes and Microsoft 365 licenses
# Use Case: License compliance reporting, mailbox storage analysis, user activation audits
# Author: Jon
# ============================================================================

param(
    [Parameter(Mandatory=$false, HelpMessage="Filter by specific license type (e.g., 'E5', 'E3', 'F1')")]
    [string]$LicenseFilter = $null,
    
    [Parameter(Mandatory=$false, HelpMessage="Export results to CSV")]
    [switch]$ExportToCSV
)

# ============================================================================
# IMPORTANT: This script requires Microsoft.Graph PowerShell module
# Install with: Install-Module Microsoft.Graph -Scope CurrentUser
# Then authenticate: Connect-MgGraph -Scopes "Organization.Read.All", "User.Read.All"
# ============================================================================

Write-Host "Microsoft 365 Audit Script" -ForegroundColor Cyan
Write-Host "Note: Requires Microsoft.Graph PowerShell module and M365 admin permissions`n" -ForegroundColor Yellow

# Verify Microsoft.Graph module is installed
try {
    Import-Module Microsoft.Graph.Users -ErrorAction Stop
    Write-Host "✓ Microsoft.Graph module loaded" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Microsoft.Graph module not found." -ForegroundColor Red
    Write-Host "Install with: Install-Module Microsoft.Graph -Scope CurrentUser" -ForegroundColor Yellow
    exit
}

# Check if already authenticated
$context = Get-MgContext
if (-not $context) {
    Write-Host "Authenticating to Microsoft 365..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes "Organization.Read.All", "User.Read.All" | Out-Null
    Write-Host "✓ Successfully authenticated to Microsoft 365" -ForegroundColor Green
}

Write-Host "Retrieving users and licenses..." -ForegroundColor Cyan

# Get all users with license information
try {
    $users = Get-MgUser -All -Property "id,displayName,mail,userPrincipalName,assignedLicenses" -ErrorAction Stop
    Write-Host "✓ Retrieved $($users.Count) Microsoft 365 users" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Could not retrieve users - $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Get SKU information for license mapping
$skus = Get-MgSubscribedSku | Select-Object SkuPartNumber, SkuId

# Initialize results
$licenseResults = @()
$unlicensedUsers = @()
$licenseCount = @{}

# Process each user
Write-Host "Analyzing licenses..." -ForegroundColor Cyan

foreach ($user in $users) {
    $displayName = $user.DisplayName
    $userPrincipalName = $user.UserPrincipalName
    $mail = $user.Mail
    
    # Get assigned licenses
    $assignedLicenses = $user.AssignedLicenses
    
    if ($assignedLicenses.Count -eq 0) {
        # User has no licenses
        $unlicensedUsers += [PSCustomObject]@{
            DisplayName = $displayName
            Email = $mail
            UserPrincipalName = $userPrincipalName
            LicenseCount = 0
            LicenseTypes = "None"
        }
    } else {
        # Build license string from SkuIds
        $licenseNames = @()
        foreach ($license in $assignedLicenses) {
            $skuName = ($skus | Where-Object SkuId -eq $license.SkuId).SkuPartNumber
            $licenseNames += $skuName
            
            # Count licenses
            if (-not $licenseCount[$skuName]) {
                $licenseCount[$skuName] = 0
            }
            $licenseCount[$skuName]++
        }
        
        # Apply filter if specified
        if ($LicenseFilter -and -not ($licenseNames -join "," | Select-String $LicenseFilter)) {
            continue
        }
        
        $licenseResults += [PSCustomObject]@{
            DisplayName = $displayName
            Email = $mail
            UserPrincipalName = $userPrincipalName
            LicenseCount = $assignedLicenses.Count
            LicenseTypes = $licenseNames -join ", "
        }
    }
}

# Generate summary report
Write-Host "`n========== MICROSOFT 365 LICENSE AUDIT SUMMARY ==========" -ForegroundColor Cyan
Write-Host "Total Users: $($users.Count)"
Write-Host "Licensed Users: $($licenseResults.Count)" -ForegroundColor Green
Write-Host "Unlicensed Users: $($unlicensedUsers.Count)" -ForegroundColor Yellow
Write-Host "=========================================================`n" -ForegroundColor Cyan

# License breakdown
Write-Host "License Distribution:" -ForegroundColor Cyan
foreach ($license in ($licenseCount.GetEnumerator() | Sort-Object Value -Descending)) {
    Write-Host "  $($license.Name): $($license.Value) users" -ForegroundColor Green
}

# Show unlicensed users if any
if ($unlicensedUsers.Count -gt 0) {
    Write-Host "`nUnlicensed Users (Review for activation):" -ForegroundColor Yellow
    $unlicensedUsers | Select-Object DisplayName, Email -First 20 | Format-Table -AutoSize
    if ($unlicensedUsers.Count -gt 20) {
        Write-Host "... and $($unlicensedUsers.Count - 20) more unlicensed users (exported in full report)"
    }
}

# Export results if requested
if ($ExportToCSV) {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    
    # Export licensed users
    $licensedPath = ".\M365_LicensedUsers_$timestamp.csv"
    $licenseResults | Sort-Object LicenseTypes | Export-Csv -Path $licensedPath -NoTypeInformation -Encoding UTF8
    Write-Host "`n✓ Licensed users report: $licensedPath" -ForegroundColor Green
    
    # Export unlicensed users
    if ($unlicensedUsers.Count -gt 0) {
        $unlicensedPath = ".\M365_UnlicensedUsers_$timestamp.csv"
        $unlicensedUsers | Export-Csv -Path $unlicensedPath -NoTypeInformation -Encoding UTF8
        Write-Host "✓ Unlicensed users report: $unlicensedPath" -ForegroundColor Green
    }
    
    Write-Host "`nRecommendations:" -ForegroundColor Cyan
    Write-Host "1. Review unlicensed users - assign appropriate licenses or deactivate"
    Write-Host "2. Consolidate license types where possible (E3 vs E5 vs F1)"
    Write-Host "3. Monitor inactive users for license optimization"
}

Write-Host "`nScript completed successfully." -ForegroundColor Green
