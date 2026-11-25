<#
.SYNOPSIS
    100% offline, zero-login CLI sanity check for MSP billing (Pax8 vs. PSA/Accounting).
.DESCRIPTION
    Compares a local Pax8 distributor invoice CSV against a local PSA or accounting
    billing export (HaloPSA, ConnectWise, Autotask, QuickBooks, Xero) to quickly
    flag exact-match seat discrepancies, NCE price creep, and unmatched line items
    in your terminal. Zero Azure logins, zero PSA API keys, and zero external modules.
.EXAMPLE
    .\Audit-MspBillingCsv.ps1 -Pax8Csv ".\pax8_invoice.csv" -PsaCsv ".\psa_billing.csv"
.LICENSE
    MIT License - Provided AS IS, without warranty of any kind.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Path to your Pax8 Invoice CSV file")]
    [ValidateScript({ Test-Path $_ })]
    [string]$Pax8Csv,

    [Parameter(Mandatory = $true, HelpMessage = "Path to your PSA / Accounting Billing CSV file")]
    [ValidateScript({ Test-Path $_ })]
    [string]$PsaCsv
)

function Get-CsvColValue {
    param(
        [PSObject]$Row,
        [string[]]$Candidates
    )
    foreach ($candidate in $Candidates) {
        $target = ($candidate -replace '[^a-zA-Z0-9]', '').ToLower()
        foreach ($prop in $Row.PSObject.Properties) {
            $propNorm = ($prop.Name -replace '[^a-zA-Z0-9]', '').ToLower()
            if ($propNorm -eq $target -and $null -ne $prop.Value) {
                return ([string]$prop.Value).Trim()
            }
        }
    }
    return ""
}

function ConvertTo-CleanDouble {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return 0.0 }
    $cleaned = $Value -replace '[^0-9.\-]', ''
    $parsed = 0.0
    if ([double]::TryParse($cleaned, [ref]$parsed)) {
        return $parsed
    }
    return 0.0
}

Write-Host "Running 100% offline CSV sanity check (zero cloud or Azure connections)..." -ForegroundColor Cyan

$Pax8Rows = @(Import-Csv -Path $Pax8Csv)
$PsaRows  = @(Import-Csv -Path $PsaCsv)

# 1. Pre-aggregate Pax8 rows by exact normalized Client + Item
$Pax8Agg = @{}
foreach ($r in $Pax8Rows) {
    $client = Get-CsvColValue -Row $r -Candidates @('Company Name', 'CompanyName', 'Client Name', 'Customer', 'Account', 'Company')
    $item   = Get-CsvColValue -Row $r -Candidates @('Product Name', 'ProductName', 'SKU', 'Description', 'Item', 'Item Name', 'Service')
    if ([string]::IsNullOrWhiteSpace($client) -or [string]::IsNullOrWhiteSpace($item)) { continue }

    $qty   = ConvertTo-CleanDouble (Get-CsvColValue -Row $r -Candidates @('Quantity', 'Qty', 'Units', 'Seats', 'Billed Qty'))
    $price = ConvertTo-CleanDouble (Get-CsvColValue -Row $r -Candidates @('Unit Price', 'UnitPrice', 'Price', 'Unit Cost', 'Rate', 'Cost'))
    $key   = "$($client.ToLower())|$($item.ToLower())"

    if (-not $Pax8Agg.ContainsKey($key)) {
        $Pax8Agg[$key] = [PSCustomObject]@{
            Client   = $client
            Item     = $item
            Qty      = $qty
            UnitCost = $price
        }
    } else {
        $Pax8Agg[$key].Qty += $qty
        if ($price -gt $Pax8Agg[$key].UnitCost) {
            $Pax8Agg[$key].UnitCost = $price
        }
    }
}

# 2. Pre-aggregate PSA / Accounting rows by exact normalized Client + Item
$PsaAgg = @{}
foreach ($r in $PsaRows) {
    $client = Get-CsvColValue -Row $r -Candidates @('Client Name', 'Company Name', 'CompanyName', 'Customer', 'Account', 'Company')
    $item   = Get-CsvColValue -Row $r -Candidates @('Item Name', 'ItemName', 'Product Name', 'Description', 'Service', 'Agreement Item', 'SKU', 'Item')
    if ([string]::IsNullOrWhiteSpace($client) -or [string]::IsNullOrWhiteSpace($item)) { continue }

    $qty   = ConvertTo-CleanDouble (Get-CsvColValue -Row $r -Candidates @('Billed Qty', 'BilledQty', 'Quantity', 'Qty', 'Units', 'Seats'))
    $price = ConvertTo-CleanDouble (Get-CsvColValue -Row $r -Candidates @('Unit Price', 'UnitPrice', 'Price', 'Rate', 'Amount'))
    $key   = "$($client.ToLower())|$($item.ToLower())"

    if (-not $PsaAgg.ContainsKey($key)) {
        $PsaAgg[$key] = [PSCustomObject]@{
            Client    = $client
            Item      = $item
            Qty       = $qty
            UnitPrice = $price
        }
    } else {
        $PsaAgg[$key].Qty += $qty
        if ($price -gt $PsaAgg[$key].UnitPrice) {
            $PsaAgg[$key].UnitPrice = $price
        }
    }
}

# 3. Reconcile Pax8 vs. PSA (Exact Match Only - Console Output Only)
$Findings = [System.Collections.Generic.List[PSObject]]::new()
$TotalLeak = 0.0

foreach ($key in $Pax8Agg.Keys) {
    $p = $Pax8Agg[$key]
    $a = if ($PsaAgg.ContainsKey($key)) { $PsaAgg[$key] } else { $null }

    $issueType = "OK"
    $lineLoss  = 0.0
    $psaQty    = if ($null -ne $a) { [int]$a.Qty } else { 0 }

    if ($null -eq $a) {
        $issueType = "UNMATCHED_PSA_ITEM"
        $lineLoss  = $p.Qty * $p.UnitCost
    } elseif ($p.Qty -gt $a.Qty) {
        $issueType = "UNBILLED_SEATS"
        $lineLoss  = ($p.Qty - $a.Qty) * $p.UnitCost
    } elseif ($p.UnitCost -gt ($a.UnitPrice + 0.009)) {
        $issueType = "NCE_PRICE_CREEP"
        $lineLoss  = $p.Qty * ($p.UnitCost - $a.UnitPrice)
    }

    if ($issueType -ne "OK") {
        $TotalLeak += $lineLoss
        $Findings.Add([PSCustomObject]@{
            Client    = $p.Client
            Item      = $p.Item
            IssueType = $issueType
            Pax8Qty   = [int]$p.Qty
            PsaQty    = $psaQty
        })
    }
}

$UnbilledCount  = @($Findings | Where-Object { $_.IssueType -eq "UNBILLED_SEATS" }).Count
$CreepCount     = @($Findings | Where-Object { $_.IssueType -eq "NCE_PRICE_CREEP" }).Count
$UnmatchedCount = @($Findings | Where-Object { $_.IssueType -eq "UNMATCHED_PSA_ITEM" }).Count

Write-Host "`n--- OFFLINE BILLING SANITY CHECK COMPLETE ---" -ForegroundColor Green
Write-Host ("Pax8 Line Groups Checked : {0}" -f $Pax8Agg.Count)
Write-Host ("Unbilled Seat Leaks      : {0}" -f $UnbilledCount) -ForegroundColor Yellow
Write-Host ("NCE Price Creep Rows     : {0}" -f $CreepCount) -ForegroundColor Magenta
Write-Host ("Unmatched PSA Items      : {0} (exact-match misses / NCE tags / bundles)" -f $UnmatchedCount) -ForegroundColor Cyan
Write-Host ("Estimated Monthly At Risk: `${0:N2}/mo" -f $TotalLeak) -ForegroundColor Red

if ($Findings.Count -gt 0) {
    Write-Host ""
    $Findings | Sort-Object -Property IssueType, Client | Format-Table -AutoSize
} else {
    Write-Host "`n100% Reconciled - Zero exact-match discrepancies found!" -ForegroundColor Green
}

Write-Host "Need fuzzy client/SKU matching, per-line dollar math, and import-ready PSA Delta / Pax8 Dispute CSVs?" -ForegroundColor DarkGray
Write-Host "Run it 100% locally in your browser (zero uploads) at https://actualcount.com" -ForegroundColor DarkGray