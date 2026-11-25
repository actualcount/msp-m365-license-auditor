# MSP Pax8 vs. PSA Offline CSV Billing Sanity Checker

A lightweight, **100% offline PowerShell CLI sanity checker** for Managed Service Providers (MSPs) to quickly cross-check monthly **Pax8 / distributor invoice CSVs** against **PSA or accounting billing exports** (HaloPSA, ConnectWise Manage, Autotask, QuickBooks, or Xero).

**Zero Azure logins. Zero Microsoft Graph permissions. Zero PSA API admin keys. Zero external modules.**

## What It Checks

Run it in 10 seconds before your monthly invoice run to see a terminal summary of:

* **`UNBILLED_SEATS`:** Exact-match subscriptions where Pax8 is billing you for more seats than your PSA agreement bills the client.
* **`NCE_PRICE_CREEP`:** Exact-match subscriptions where Pax8's wholesale unit cost rose above the unit price on your PSA agreement.
* **`UNMATCHED_PSA_ITEM`:** Paid distributor line items with no exact matching client/SKU row in your PSA export (flags naming drift, NCE tags, forgotten offboarded clients, or bundled PSA seats).

## Security & Zero-Friction Design

* **100% Local & Offline:** Uses native PowerShell `Import-Csv` only. No `Install-Module` calls, no Entra/Azure App Registrations, no GDAP tokens, and zero outbound network traffic.
* **Flexible Column Detection:** Automatically reads standard header variations across Pax8, HaloPSA, ConnectWise, Autotask, QuickBooks, and Xero (`Company Name` / `Client Name`, `Product Name` / `Item Name`, `Quantity` / `Billed Qty`, `Unit Price` / `Rate`).
* **Read-Only Terminal Output:** Prints a clean summary and mismatch table directly in your console without writing sensitive client files to disk.

## Quick Start

1. **Clone the repository:**

~~~powershell
git clone https://github.com/actualcount/msp-m365-license-auditor.git
cd msp-m365-license-auditor
~~~

2. **Export two CSVs:**
   * Your monthly **Pax8 / distributor invoice CSV**
   * Your **PSA or accounting billing CSV**

3. **Run the sanity check locally:**

~~~powershell
.\Audit-MspBillingCsv.ps1 -Pax8Csv ".\pax8_invoice.csv" -PsaCsv ".\psa_billing.csv"
~~~

## Seeing False `UNMATCHED_PSA_ITEM` Misses?

Because this lightweight CLI script uses strict exact-name matching, normal distributor formatting differences—like Pax8 appending `[New Commerce Experience - Annual/Monthly]` or `"Acme Manufacturing LLC"` vs. `"Acme Corp"`—will flag as unmatched.

If you need **fuzzy client & SKU matching**, automatic NCE bracket/term aggregation, M365 blocked-user offboarding hygiene checks, per-line dollar math, and import-ready `PSA_Agreement_Deltas.csv` + `Pax8_Credit_Disputes.csv` exports—still **100% browser-local via DuckDB-Wasm with zero cloud uploads**—run your CSVs at [**actualcount.com**](https://actualcount.com).

## License

MIT License — Provided "AS IS", without warranty of any kind. See [LICENSE](LICENSE) for details.
