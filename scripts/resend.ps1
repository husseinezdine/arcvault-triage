# Re-send specific sample ids:  .\scripts\resend.ps1 REQ-0005,REQ-0007
param([string[]]$ids)
$ids = ($ids -join ",") -split "," | ForEach-Object { $_.Trim() }
$url = "http://localhost:5678/webhook/intake"
$all = @{
  "REQ-0001" = @{ source="email";          message="Hi, I tried logging in this morning and keep getting a 403 error. My account is arcvault.io/user/jsmith. This started after your update last Tuesday." }
  "REQ-0002" = @{ source="web_form";       message="We'd love to see a bulk export feature for our audit logs. We're a compliance-heavy org and this would save us hours every month." }
  "REQ-0003" = @{ source="support_portal"; message="Invoice #8821 shows a charge of `$1,240 but our contract rate is `$980/month. Can someone look into this?" }
  "REQ-0004" = @{ source="email";          message="I'm not sure if this is the right place to ask, but is there a way to set up SSO with Okta? We're evaluating switching our auth provider." }
  "REQ-0005" = @{ source="web_form";       message="Your dashboard stopped loading for us around 2pm EST. Checked our end - it's definitely on yours. Multiple users affected." }
  "REQ-0006" = @{ source="email";          message="hey, stuff is not working, please help asap" }
  "REQ-0007" = @{ source="support_portal"; message="We were charged twice this month (`$2,100 extra) and also the CSV export button does nothing since yesterday." }
}
foreach ($id in $ids) {
  $s = $all[$id]; if (-not $s) { Write-Host "unknown id $id"; continue }
  $body = @{ id=$id; source=$s.source; message=$s.message } | ConvertTo-Json -Compress
  Write-Host "--> $id"
  Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Body $body | ConvertTo-Json -Compress
  Start-Sleep -Seconds 3
}
