# ============================================================================
# Script: Get-ADUserAudit-Fixed.ps1
# Purpose: Audit Active Directory for inactive users, stale passwords, disabled accounts
# Use Case: Compliance reporting, security hygiene, identifying accounts to deactivate
# Author: Jon
# ============================================================================

param(
    [Parameter(Mandatory=$false, HelpMessage="Number of days to consider account 'inactive'")]
    [int]$InactiveDays = 90,
    
    [Parameter(Mandatory=$false, HelpMessage="Number of days since last password change to flag as stale")]
    [int]$StalePasswordDays = 120,
    
    [Parameter(Mandatory=$false, HelpMessage="Organizational Unit to audit (defaults to entire forest)")]
    [string]$TargetOU = $null,
    
    [Parameter(Mandatory=$false, HelpMessage="Export results to CSV file")]
    [switch]$ExportToCSV
)

# Import Active Directory module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Host "ERROR: Active Directory module not found. Run as Administrator on a domain-joined computer." -ForegroundColor Red
    exit
}

Write-Host "Starting Active Directory Audit..." -ForegroundColor Cyan
Write-Host "Threshold: Inactive = $InactiveDays days, Stale Password = $StalePasswordDays days`n" -ForegroundColor Gray

# Build AD filter and query parameters
$getADUserParams = @{
    Filter = "Enabled -eq `$true"
    Properties = @(
        'SamAccountName',
        'DisplayName',
        'EmailAddress',
        'Department',
        'LastLogonDate',
        'PasswordLastSet',
        'AccountExpirationDate',
        'MemberOf',
        'Created'
    )
}

if ($TargetOU) {
    $getADUserParams['SearchBase'] = $TargetOU
}

# Retrieve all enabled user accounts
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "✓ Active Directory module loaded" -ForegroundColor Green
} 
catch {
    Write-Host "ERROR: Active Directory module not found" -ForegroundColor Red
    exit
}

# Calculate threshold dates
$inactiveThreshold = (Get-Date).AddDays(-$InactiveDays)
$stalePasswordThreshold = (Get-Date).AddDays(-$StalePasswordDays)

# Initialize results arrays
$inactiveUsers = @()
$stalePasswordUsers = @()
$auditResults = @()

# Analyze each user account
Write-Host "Analyzing accounts..." -ForegroundColor Cyan

foreach ($user in $adUsers) {
    $lastLogonDate = $user.LastLogonDate
    $passwordLastSet = $user.PasswordLastSet
    
    # Handle null LastLogonDate (never logged in)
    if ($null -eq $lastLogonDate) {
        $lastLogonDate = $user.Created
        $neverLoggedIn = $true
    } else {
        $neverLoggedIn = $false
    }
    
    # Determine if account is inactive
    $isInactive = $lastLogonDate -lt $inactiveThreshold
    $isStalePassword = $passwordLastSet -lt $stalePasswordThreshold
    $riskLevel = "Low"
    
    if ($isInactive -and $isStalePassword) {
        $riskLevel = "High"
    } elseif ($isInactive -or $isStalePassword) {
        $riskLevel = "Medium"
    }
    
    # Build audit record
    $auditRecord = [PSCustomObject]@{
        Username = $user.SamAccountName
        DisplayName = $user.DisplayName
        Email = $user.EmailAddress
        Department = $user.Department
        LastLogonDate = if ($lastLogonDate) { $lastLogonDate.ToString("yyyy-MM-dd") } else { "Never" }
        DaysInactive = if ($lastLogonDate) { [math]::Floor(((Get-Date) - $lastLogonDate).TotalDays) } else { "N/A" }
        PasswordLastSet = if ($passwordLastSet) { $passwordLastSet.ToString("yyyy-MM-dd") } else { "Never" }
        DaysSincePasswordChange = if ($passwordLastSet) { [math]::Floor(((Get-Date) - $passwordLastSet).TotalDays) } else { "N/A" }
        NeverLoggedIn = $neverLoggedIn
        IsInactive = $isInactive
        IsStalePassword = $isStalePassword
        RiskLevel = $riskLevel
    }
    
    $auditResults += $auditRecord
    
    # Categorize findings
    if ($isInactive) {
        $inactiveUsers += $auditRecord
    }
    if ($isStalePassword) {
        $stalePasswordUsers += $auditRecord
    }
}

# Generate summary report
Write-Host "`n========== ACTIVE DIRECTORY AUDIT SUMMARY ==========" -ForegroundColor Cyan
Write-Host "Total User Accounts Audited: $($adUsers.Count)"
Write-Host "Inactive Accounts (>$InactiveDays days): $($inactiveUsers.Count)" -ForegroundColor Yellow
Write-Host "Stale Passwords (>$StalePasswordDays days): $($stalePasswordUsers.Count)" -ForegroundColor Yellow
Write-Host "High Risk (Inactive + Stale Password): $($auditResults | Where-Object RiskLevel -eq 'High' | Measure-Object | Select-Object -ExpandProperty Count)" -ForegroundColor Red
Write-Host "==================================================`n" -ForegroundColor Cyan

# Display top findings
Write-Host "Top 10 Inactive Accounts:" -ForegroundColor Yellow
$inactiveUsers | Sort-Object DaysInactive -Descending | Select-Object Username, DisplayName, DaysInactive, RiskLevel -First 10 | Format-Table -AutoSize

Write-Host "`nTop 10 Stale Password Accounts:" -ForegroundColor Yellow
$stalePasswordUsers | Sort-Object DaysSincePasswordChange -Descending | Select-Object Username, DisplayName, DaysSincePasswordChange, RiskLevel -First 10 | Format-Table -AutoSize

# Export to CSV if requested
if ($ExportToCSV) {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $csvPath = ".\ADUserAudit_$timestamp.csv"
    
    $auditResults | Sort-Object RiskLevel -Descending | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "✓ Full audit report exported: $csvPath" -ForegroundColor Green
    Write-Host "`nRecommended Actions:" -ForegroundColor Cyan
    Write-Host "1. Review and contact owners of High Risk accounts"
    Write-Host "2. Disable inactive accounts after 180+ days"
    Write-Host "3. Enforce password changes for accounts >120 days"
    Write-Host "4. Implement MFA for sensitive roles"
}
