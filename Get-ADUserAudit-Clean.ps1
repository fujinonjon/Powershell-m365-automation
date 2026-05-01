# ============================================================================
# Script: Get-ADUserAudit.ps1
# Purpose: Audit Active Directory for inactive users
# Author: Jon
# ============================================================================

param(
    [Parameter(Mandatory=$false)]
    [int]$InactiveDays = 90,
    
    [Parameter(Mandatory=$false)]
    [switch]$ExportToCSV
)

# Import Active Directory module
Import-Module ActiveDirectory -ErrorAction SilentlyContinue

Write-Host "Starting Active Directory Audit..." -ForegroundColor Cyan

# Get all enabled users
$adUsers = Get-ADUser -Filter "Enabled -eq `$true" -Properties LastLogonDate, PasswordLastSet, Created

Write-Host "✓ Retrieved $($adUsers.Count) enabled user accounts" -ForegroundColor Green

# Calculate threshold
$inactiveThreshold = (Get-Date).AddDays(-$InactiveDays)

# Initialize results
$inactiveUsers = @()
$auditResults = @()

# Analyze each user
Write-Host "Analyzing accounts..." -ForegroundColor Cyan

foreach ($user in $adUsers) {
    $lastLogonDate = $user.LastLogonDate
    
    if ($null -eq $lastLogonDate) {
        $lastLogonDate = $user.Created
    }
    
    $isInactive = $lastLogonDate -lt $inactiveThreshold
    
    $auditRecord = [PSCustomObject]@{
        Username = $user.SamAccountName
        DisplayName = $user.DisplayName
        LastLogonDate = $lastLogonDate.ToString("yyyy-MM-dd")
        DaysInactive = [math]::Floor(((Get-Date) - $lastLogonDate).TotalDays)
        IsInactive = $isInactive
    }
    
    $auditResults += $auditRecord
    
    if ($isInactive) {
        $inactiveUsers += $auditRecord
    }
}

# Display summary
Write-Host "`n========== AUDIT SUMMARY ==========" -ForegroundColor Cyan
Write-Host "Total Users Audited: $($adUsers.Count)"
Write-Host "Inactive Users (>$InactiveDays days): $($inactiveUsers.Count)" -ForegroundColor Yellow
Write-Host "===================================`n" -ForegroundColor Cyan

# Display inactive users
if ($inactiveUsers.Count -gt 0) {
    Write-Host "Inactive Users:" -ForegroundColor Yellow
    $inactiveUsers | Sort-Object DaysInactive -Descending | Format-Table -AutoSize
}

# Export to CSV if requested
if ($ExportToCSV) {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $csvPath = ".\ADUserAudit_$timestamp.csv"
    $auditResults | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "✓ Report exported: $csvPath" -ForegroundColor Green
}

Write-Host "Audit complete." -ForegroundColor Green