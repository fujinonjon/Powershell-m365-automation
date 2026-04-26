# ============================================================================
# Script: Create-BulkADUsers.ps1
# Purpose: Bulk create Active Directory user accounts from CSV file
# Use Case: Onboarding multiple new employees, batch user provisioning
# Author: Jon
# ============================================================================

param(
    [Parameter(Mandatory=$true, HelpMessage="Path to CSV file with user data")]
    [ValidateScript({Test-Path $_})]
    [string]$CSVPath,
    
    [Parameter(Mandatory=$false, HelpMessage="Organizational Unit where users will be created")]
    [string]$TargetOU = "OU=Users,DC=contoso,DC=com"
)

# Import Active Directory module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Host "ERROR: Active Directory module not found. Run as Administrator on a domain-joined computer." -ForegroundColor Red
    exit
}

# Read CSV and validate structure
try {
    $users = Import-Csv -Path $CSVPath
    Write-Host "✓ Loaded $($users.Count) user records from CSV" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Could not read CSV file. Ensure it has columns: FirstName, LastName, Department, Email, Manager" -ForegroundColor Red
    exit
}

# Verify target OU exists
try {
    Get-ADOrganizationalUnit -Identity $TargetOU | Out-Null
    Write-Host "✓ Target OU verified: $TargetOU" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Target OU does not exist: $TargetOU" -ForegroundColor Red
    exit
}

# Initialize tracking
$successCount = 0
$failureCount = 0
$results = @()

# Process each user
foreach ($user in $users) {
    # Build variables from CSV columns
    $firstName = $user.FirstName.Trim()
    $lastName = $user.LastName.Trim()
    $email = $user.Email.Trim()
    $department = $user.Department.Trim()
    $manager = $user.Manager.Trim()
    
    # Generate username (first initial + last name, max 20 chars)
    $username = "$($firstName[0])$lastName".ToLower() -replace '[^a-z0-9]', ''
    $username = $username.Substring(0, [Math]::Min(20, $username.Length))
    
    # Generate temporary password
    $tempPassword = [System.Web.Security.Membership]::GeneratePassword(12, 2) | ConvertTo-SecureString -AsPlainText -Force
    
    # Build user display name
    $displayName = "$firstName $lastName"
    
    try {
        # Check if user already exists
        $existingUser = Get-ADUser -Filter "SamAccountName -eq '$username'" -ErrorAction SilentlyContinue
        if ($existingUser) {
            Write-Host "⚠ SKIPPED: User '$username' already exists" -ForegroundColor Yellow
            $results += [PSCustomObject]@{
                Status = "SKIPPED"
                Username = $username
                FirstName = $firstName
                LastName = $lastName
                Reason = "User already exists"
            }
            continue
        }
        
        # Create new AD user
        New-ADUser `
            -SamAccountName $username `
            -UserPrincipalName "$username@contoso.com" `
            -Name $displayName `
            -GivenName $firstName `
            -Surname $lastName `
            -DisplayName $displayName `
            -EmailAddress $email `
            -Department $department `
            -Path $TargetOU `
            -AccountPassword $tempPassword `
            -Enabled $true `
            -ChangePasswordAtLogon $true `
            -OtherAttributes @{
                'proxyAddresses' = "SMTP:$email"
            }
        
        Write-Host "✓ CREATED: $username ($displayName)" -ForegroundColor Green
        $successCount++
        
        $results += [PSCustomObject]@{
            Status = "CREATED"
            Username = $username
            FirstName = $firstName
            LastName = $lastName
            Email = $email
            Department = $department
            Password = $tempPassword
            Reason = "Success"
        }
        
    } catch {
        Write-Host "✗ FAILED: $username - $($_.Exception.Message)" -ForegroundColor Red
        $failureCount++
        
        $results += [PSCustomObject]@{
            Status = "FAILED"
            Username = $username
            FirstName = $firstName
            LastName = $lastName
            Email = $email
            Reason = $_.Exception.Message
        }
    }
}

# Summary report
Write-Host "`n========== BULK USER CREATION SUMMARY ==========" -ForegroundColor Cyan
Write-Host "Total Processed: $($users.Count)"
Write-Host "Successfully Created: $successCount" -ForegroundColor Green
Write-Host "Failed: $failureCount" -ForegroundColor Red
Write-Host "Skipped (Existing): $($results | Where-Object Status -eq 'SKIPPED' | Measure-Object | Select-Object -ExpandProperty Count)"
Write-Host "============================================`n" -ForegroundColor Cyan

# Export detailed report
$reportPath = "$(Split-Path $CSVPath)\BulkUserCreation_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$results | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8

Write-Host "✓ Detailed report saved: $reportPath" -ForegroundColor Green
Write-Host "`nNOTE: Users created with temporary password and 'Change Password at Logon' enabled." -ForegroundColor Yellow
