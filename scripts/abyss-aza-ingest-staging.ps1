#Requires -Version 5.1
<#
.SYNOPSIS
  Refresh staging abyss statistics cache via AZA fetch + ingest API.

.DESCRIPTION
  Same path as .github/workflows/abyss-aza-ingest-staging.yml:
  1) GET AZA public KV JSON
  2) POST to staging ingest with Bearer auth
  3) GET /api/abyss/statistics and print safe freshness fields

  Never prints secret values, Authorization headers, or full JSON bodies.

.NOTES
  Set in the current shell only (do not paste into chat / commit):
    $env:STAGING_ABYSS_INGEST_SECRET = '<staging-only-secret>'

  Optional override:
    $env:STAGING_ABYSS_INGEST_URL = 'https://staging-sable.vercel.app/api/abyss/statistics/ingest'
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ingestUrl = if ($env:STAGING_ABYSS_INGEST_URL) {
  $env:STAGING_ABYSS_INGEST_URL.Trim()
} else {
  "https://staging-sable.vercel.app/api/abyss/statistics/ingest"
}
$getUrl = "https://staging-sable.vercel.app/api/abyss/statistics"
$azaUrl = "https://c1-api.aza.gg/kv/read?key_id=genshin_abyss_statistics"
$secret = $env:STAGING_ABYSS_INGEST_SECRET

if ([string]::IsNullOrWhiteSpace($secret)) {
  Write-Error "STAGING_ABYSS_INGEST_SECRET is not set in this shell. Set it locally and retry (do not paste the value into chat)."
  exit 2
}
if ($secret.Trim() -ne $secret -or $secret -match "\s") {
  Write-Error "STAGING_ABYSS_INGEST_SECRET has leading/trailing or internal whitespace."
  exit 2
}

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("abyss-ingest-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tmpDir | Out-Null
$azaFile = Join-Path $tmpDir "aza-abyss.json"
$ingestFile = Join-Path $tmpDir "ingest-response.json"
$getFile = Join-Path $tmpDir "get-response.json"

try {
  Write-Output "fetching_aza=true"
  & curl.exe -fsSL --retry 2 --retry-delay 5 --max-time 30 `
    -H "Accept: application/json" `
    -H "User-Agent: Mozilla/5.0 (compatible; GenshinBuilder-Local/0.1; +https://github.com/ois-T-I-08/cursor-project)" `
    $azaUrl `
    -o $azaFile
  if ($LASTEXITCODE -ne 0) { throw "AZA fetch failed (curl exit $LASTEXITCODE)" }

  $bytes = (Get-Item -LiteralPath $azaFile).Length
  Write-Output "aza_bytes=$bytes"
  if ($bytes -lt 100 -or $bytes -gt 2097152) {
    throw "unexpected AZA payload size"
  }
  try {
    $null = Get-Content -LiteralPath $azaFile -Raw -Encoding utf8 | ConvertFrom-Json
  } catch {
    throw "AZA payload is not valid JSON"
  }

  Write-Output "posting_ingest=true"
  $code = & curl.exe -sS -o $ingestFile -w "%{http_code}" --max-time 60 `
    -X POST `
    -H "Authorization: Bearer $secret" `
    -H "Content-Type: application/json" `
    --data-binary "@$azaFile" `
    $ingestUrl
  Write-Output "ingest_http_status=$code"
  if ($code -ne "200") {
    try {
      $err = Get-Content -LiteralPath $ingestFile -Raw -Encoding utf8 | ConvertFrom-Json
      Write-Output ("ingest_ok=" + $err.ok)
      Write-Output ("ingest_error=" + $err.error.code)
    } catch {
      Write-Output "ingest_body_not_json=true"
    }
    throw "ingest failed"
  }

  $ing = Get-Content -LiteralPath $ingestFile -Raw -Encoding utf8 | ConvertFrom-Json
  if ($ing.ok -ne $true) { throw "ingest response ok!=true" }
  Write-Output ("ingest_ok=" + $ing.ok)
  Write-Output ("sampleSize=" + $ing.sampleSize)
  Write-Output ("expiresAt=" + $ing.expiresAt)

  $getCode = & curl.exe -sS -o $getFile -w "%{http_code}" --max-time 30 $getUrl
  Write-Output "get_http_status=$getCode"
  $get = Get-Content -LiteralPath $getFile -Raw -Encoding utf8 | ConvertFrom-Json
  if ($getCode -ne "200" -or $get.ok -ne $true) {
    Write-Output ("get_error=" + ($(if ($get.error) { $get.error.code } else { "unknown" })))
    throw "GET /api/abyss/statistics failed"
  }
  $meta = $get.data.metadata
  Write-Output ("get_source=" + $meta.source)
  Write-Output ("get_isStale=" + $meta.isStale)
  Write-Output ("get_sampleSize=" + $meta.sampleSize)
  Write-Output ("get_fetchedAt=" + $meta.fetchedAt)
  Write-Output ("get_expiresAt=" + $meta.expiresAt)
  if ($meta.isStale -eq $true) {
    Write-Warning "GET is still stale after ingest; investigate cache write / alias / deployment tip."
    exit 3
  }
  Write-Output "refresh_ok=true"
}
finally {
  Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
