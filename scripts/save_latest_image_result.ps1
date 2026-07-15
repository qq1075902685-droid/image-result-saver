param(
  [string]$Cwd = ".",
  [string]$OutDir = "",
  [string]$Prefix = "generated-image",
  [string]$Rollout = "",
  [string]$SessionsRoot = ""
)

$ErrorActionPreference = "Stop"
$PngSignature = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)

function Get-DefaultCodexHome {
  if ($env:CODEX_HOME) {
    return (Resolve-Path -LiteralPath $env:CODEX_HOME).Path
  }

  $current = Get-Item -LiteralPath $PSScriptRoot
  while ($null -ne $current) {
    if ((Test-Path -LiteralPath (Join-Path $current.FullName "sessions")) -and
        (Test-Path -LiteralPath (Join-Path $current.FullName "skills"))) {
      return $current.FullName
    }
    $current = $current.Parent
  }

  $homeDefault = Join-Path $HOME ".codex"
  if (Test-Path -LiteralPath (Join-Path $homeDefault "sessions")) {
    return $homeDefault
  }

  $gDefault = "G:\codex\codex-home"
  if (Test-Path -LiteralPath (Join-Path $gDefault "sessions")) {
    return $gDefault
  }

  return $homeDefault
}

function Get-LatestRollout {
  param([string]$Root)
  if (-not (Test-Path -LiteralPath $Root)) {
    throw "No sessions root found at $Root"
  }
  $file = Get-ChildItem -LiteralPath $Root -Recurse -Filter "rollout-*.jsonl" -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($null -eq $file) {
    throw "No rollout JSONL files found under $Root"
  }
  return $file.FullName
}

function Walk-JsonValue {
  param($Value)

  $Value

  if ($null -eq $Value) {
    return
  }

  if ($Value -is [string]) {
    return
  }

  if ($Value -is [System.Collections.IDictionary]) {
    foreach ($key in $Value.Keys) {
      Walk-JsonValue $Value[$key]
    }
    return
  }

  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
    foreach ($item in $Value) {
      Walk-JsonValue $item
    }
    return
  }

  if ($Value.PSObject -and $Value.PSObject.Properties) {
    foreach ($prop in $Value.PSObject.Properties) {
      Walk-JsonValue $prop.Value
    }
  }
}

function Get-PropValue {
  param($Object, [string]$Name)
  if ($null -eq $Object) {
    return $null
  }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) {
    return $null
  }
  return $prop.Value
}

function Test-HasProp {
  param($Object, [string]$Name)
  if ($null -eq $Object) {
    return $false
  }
  return $null -ne $Object.PSObject.Properties[$Name]
}

function Get-ImageCallResults {
  param($Object)
  $results = @()
  foreach ($value in Walk-JsonValue $Object) {
    if ($null -eq $value -or $value -is [string]) {
      continue
    }
    $typeValue = [string](Get-PropValue $value "type")
    $nameValue = [string](Get-PropValue $value "name")
    if ((Test-HasProp $value "result") -and (($typeValue -like "*image_generation_call*") -or ($nameValue -eq "image_generation_call"))) {
      $results += ,(Get-PropValue $value "result")
    }
  }
  return $results
}

function Remove-DataUrlPrefix {
  param([string]$Text)
  $raw = $Text.Trim()
  if ($raw.ToLowerInvariant().StartsWith("data:image/png;base64,") -and $raw.Contains(",")) {
    return $raw.Split(",", 2)[1].Trim()
  }
  return $raw
}

function Test-PngSignature {
  param([byte[]]$Data)
  if ($Data.Length -lt $PngSignature.Length) {
    return $false
  }
  for ($i = 0; $i -lt $PngSignature.Length; $i++) {
    if ($Data[$i] -ne $PngSignature[$i]) {
      return $false
    }
  }
  return $true
}

function ConvertFrom-PossiblePngBase64 {
  param([string]$Text)
  $raw = Remove-DataUrlPrefix $Text
  if ($raw.Length -lt 32 -or $raw -notmatch "^[A-Za-z0-9+/=\s_-]+$") {
    return $null
  }
  $raw = [regex]::Replace($raw, "\s+", "")
  $candidates = @($raw, $raw.Replace("-", "+").Replace("_", "/"))
  foreach ($candidate in $candidates) {
    $padded = $candidate + ("=" * ((4 - ($candidate.Length % 4)) % 4))
    try {
      $data = [Convert]::FromBase64String($padded)
      if (Test-PngSignature $data) {
        return $data
      }
    } catch {
      continue
    }
  }
  return $null
}

function Get-Sha256Hex {
  param([byte[]]$Data)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($Data)
    return (($hash | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $sha.Dispose()
  }
}

function Get-UInt32BE {
  param([byte[]]$Data, [int]$Offset)
  return ([uint32]$Data[$Offset] -shl 24) -bor
    ([uint32]$Data[$Offset + 1] -shl 16) -bor
    ([uint32]$Data[$Offset + 2] -shl 8) -bor
    ([uint32]$Data[$Offset + 3])
}

function New-Crc32Table {
  [uint32]$poly = [Convert]::ToUInt32("EDB88320", 16)
  $table = New-Object "uint32[]" 256
  for ($n = 0; $n -lt 256; $n++) {
    [uint32]$c = $n
    for ($k = 0; $k -lt 8; $k++) {
      if (($c -band 1) -ne 0) {
        $c = ($poly -bxor ($c -shr 1))
      } else {
        $c = ($c -shr 1)
      }
    }
    $table[$n] = $c
  }
  return $table
}

$Script:Crc32Table = New-Crc32Table

function Get-Crc32 {
  param([byte[]]$Data)
  [uint32]$xorMask = [Convert]::ToUInt32("FFFFFFFF", 16)
  [uint32]$crc = $xorMask
  foreach ($b in $Data) {
    $idx = ($crc -bxor [uint32]$b) -band 0xFF
    $crc = $Script:Crc32Table[$idx] -bxor ($crc -shr 8)
  }
  return ($crc -bxor $xorMask)
}

function Join-Bytes {
  param([byte[]]$A, [byte[]]$B)
  $joined = New-Object byte[] ($A.Length + $B.Length)
  [Array]::Copy($A, 0, $joined, 0, $A.Length)
  [Array]::Copy($B, 0, $joined, $A.Length, $B.Length)
  return $joined
}

function Read-PngInfo {
  param([byte[]]$Data)

  if (-not (Test-PngSignature $Data)) {
    throw "PNG signature mismatch"
  }

  $offset = 8
  $width = $null
  $height = $null
  $sawIhdr = $false
  $sawIend = $false

  while ($offset + 8 -le $Data.Length) {
    $length = [int](Get-UInt32BE $Data $offset)
    $typeOffset = $offset + 4
    $chunkType = [byte[]]($Data[$typeOffset..($typeOffset + 3)])
    $chunkStart = $offset + 8
    $chunkEnd = $chunkStart + $length
    $crcEnd = $chunkEnd + 4
    if ($crcEnd -gt $Data.Length) {
      throw "Truncated PNG chunk"
    }

    if ($length -gt 0) {
      $chunkData = [byte[]]($Data[$chunkStart..($chunkEnd - 1)])
    } else {
      $chunkData = [byte[]]@()
    }
    $expectedCrc = Get-UInt32BE $Data $chunkEnd
    $actualCrc = Get-Crc32 (Join-Bytes $chunkType $chunkData)
    $chunkName = [System.Text.Encoding]::ASCII.GetString($chunkType)
    if ($expectedCrc -ne $actualCrc) {
      throw "CRC mismatch in $chunkName"
    }

    if ($chunkName -eq "IHDR") {
      if ($length -ne 13) {
        throw "Invalid IHDR length"
      }
      $width = [int](Get-UInt32BE $chunkData 0)
      $height = [int](Get-UInt32BE $chunkData 4)
      $sawIhdr = $true
    }

    if ($chunkName -eq "IEND") {
      $sawIend = $true
      break
    }

    $offset = $crcEnd
  }

  if (-not $sawIhdr -or $null -eq $width -or $null -eq $height) {
    throw "Missing IHDR"
  }
  if ($width -le 0 -or $height -le 0) {
    throw "Invalid IHDR dimensions"
  }
  if (-not $sawIend) {
    throw "Missing IEND"
  }

  return [pscustomobject]@{
    Width = $width
    Height = $height
  }
}

function Get-LatestImageResults {
  param([string]$RolloutPath)
  $latestResults = @()
  foreach ($line in [System.IO.File]::ReadLines($RolloutPath, [System.Text.Encoding]::UTF8)) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    try {
      $obj = $line | ConvertFrom-Json
    } catch {
      continue
    }
    $results = @(Get-ImageCallResults $obj)
    if ($results.Count -gt 0) {
      $latestResults = $results
    }
  }
  if ($latestResults.Count -eq 0) {
    throw "No image_generation_call.result found in $RolloutPath"
  }
  return $latestResults
}

function Get-PngsFromResult {
  param($Result)
  $pngs = @()
  $seen = @{}
  foreach ($value in Walk-JsonValue $Result) {
    if ($value -isnot [string]) {
      continue
    }
    $data = ConvertFrom-PossiblePngBase64 $value
    if ($null -eq $data) {
      continue
    }
    $digest = Get-Sha256Hex $data
    if (-not $seen.ContainsKey($digest)) {
      $seen[$digest] = $true
      $pngs += ,$data
    }
  }
  return $pngs
}

function Get-SafePrefix {
  param([string]$Value)
  $cleaned = [regex]::Replace($Value.Trim(), "[^A-Za-z0-9._-]+", "-").Trim("-._")
  if ([string]::IsNullOrWhiteSpace($cleaned)) {
    return "generated-image"
  }
  return $cleaned
}

function Save-Pngs {
  param([object[]]$Pngs, [string]$TargetDir, [string]$NamePrefix)

  New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
  $safeName = Get-SafePrefix $NamePrefix
  $results = @()
  $total = $Pngs.Count
  for ($i = 0; $i -lt $Pngs.Count; $i++) {
    [byte[]]$data = $Pngs[$i]
    $info = Read-PngInfo $data
    $suffix = if ($total -gt 1) { "-$($i + 1)" } else { "" }
    $path = Join-Path $TargetDir "$safeName$suffix.png"
    $counter = 2
    while (Test-Path -LiteralPath $path) {
      $path = Join-Path $TargetDir "$safeName$suffix-$counter.png"
      $counter++
    }
    [System.IO.File]::WriteAllBytes($path, $data)
    [byte[]]$written = [System.IO.File]::ReadAllBytes($path)
    $readInfo = Read-PngInfo $written
    if ($readInfo.Width -ne $info.Width -or $readInfo.Height -ne $info.Height) {
      throw "Readback dimensions changed for $path"
    }
    $resolved = (Resolve-Path -LiteralPath $path).Path
    $results += [pscustomobject]@{
      path = $resolved
      png_header = (Test-PngSignature $written)
      ihdr_width = $readInfo.Width
      ihdr_height = $readInfo.Height
      readable = $true
      bytes = $written.Length
      sha256 = (Get-Sha256Hex $written)
    }
  }
  return $results
}

try {
  $resolvedCwd = (Resolve-Path -LiteralPath $Cwd).Path
  $targetOutDir = if ([string]::IsNullOrWhiteSpace($OutDir)) {
    Join-Path $resolvedCwd "outputs"
  } else {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)
  }

  $resolvedSessionsRoot = if ([string]::IsNullOrWhiteSpace($SessionsRoot)) {
    Join-Path (Get-DefaultCodexHome) "sessions"
  } else {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SessionsRoot)
  }

  $rolloutPath = if ([string]::IsNullOrWhiteSpace($Rollout)) {
    Get-LatestRollout $resolvedSessionsRoot
  } else {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Rollout)
  }

  $latestResults = @(Get-LatestImageResults $rolloutPath)
  $pngs = @()
  foreach ($result in $latestResults) {
    $pngs += @(Get-PngsFromResult $result)
  }

  if ($pngs.Count -eq 0) {
    throw "No Base64 PNG data found in latest image_generation_call.result in $rolloutPath"
  }

  $saved = Save-Pngs -Pngs $pngs -TargetDir $targetOutDir -NamePrefix $Prefix
  [pscustomobject]@{
    rollout = $rolloutPath
    outputs = @($saved)
  } | ConvertTo-Json -Depth 10
} catch {
  [pscustomobject]@{ error = $_.Exception.Message } | ConvertTo-Json -Compress | Write-Error
  exit 1
}
