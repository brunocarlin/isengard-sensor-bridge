param(
    [Parameter(Mandatory = $true)][string]$Archive,
    [Parameter(Mandatory = $true)][string]$InternalPath,
    [Parameter(Mandatory = $true)][string]$Replacement,
    [Parameter(Mandatory = $true)][string]$OutputArchive
)

$sourcePath = (Resolve-Path -LiteralPath $Archive).Path
$replacementPath = (Resolve-Path -LiteralPath $Replacement).Path
$outputPath = if ([IO.Path]::IsPathRooted($OutputArchive)) {
    [IO.Path]::GetFullPath($OutputArchive)
} else {
    [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutputArchive))
}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath)) | Out-Null
[IO.File]::Copy($sourcePath, $outputPath, $true)

$stream = [IO.File]::Open($outputPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    $reader = [IO.BinaryReader]::new($stream, [Text.Encoding]::UTF8, $true)
    [void]$reader.ReadUInt32()
    $headerPickleSize = $reader.ReadUInt32()
    [void]$reader.ReadUInt32()
    $jsonLength = $reader.ReadUInt32()
    $jsonBytes = $reader.ReadBytes($jsonLength)
    $jsonText = [Text.Encoding]::UTF8.GetString($jsonBytes).TrimEnd([char]0)
    $header = $jsonText | ConvertFrom-Json

    $entry = $header
    foreach ($part in ($InternalPath -split '/')) {
        $entry = $entry.files.PSObject.Properties[$part].Value
        if ($null -eq $entry) { throw "ASAR entry not found: $InternalPath" }
    }

    $originalSize = [int]$entry.size
    $replacementBytes = [IO.File]::ReadAllBytes($replacementPath)
    if ($replacementBytes.Length -gt $originalSize) {
        throw "Replacement is $($replacementBytes.Length) bytes; entry allows only $originalSize bytes."
    }

    $padded = [byte[]]::new($originalSize)
    for ($i = 0; $i -lt $padded.Length; $i++) { $padded[$i] = 0x20 }
    [Array]::Copy($replacementBytes, $padded, $replacementBytes.Length)

    $sha = [Security.Cryptography.SHA256]::Create()
    try { $newHash = ([BitConverter]::ToString($sha.ComputeHash($padded))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    $oldHash = [string]$entry.integrity.hash
    if ($oldHash.Length -ne $newHash.Length) { throw 'Unexpected ASAR integrity hash length.' }

    $payloadOffset = 8L + $headerPickleSize
    [void]$stream.Seek($payloadOffset + [int64]$entry.offset, [IO.SeekOrigin]::Begin)
    $stream.Write($padded, 0, $padded.Length)

    $oldBytes = [Text.Encoding]::ASCII.GetBytes($oldHash)
    $newBytes = [Text.Encoding]::ASCII.GetBytes($newHash)
    $replacements = 0
    for ($i = 0; $i -le $jsonBytes.Length - $oldBytes.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $oldBytes.Length; $j++) {
            if ($jsonBytes[$i + $j] -ne $oldBytes[$j]) { $match = $false; break }
        }
        if ($match) {
            [Array]::Copy($newBytes, 0, $jsonBytes, $i, $newBytes.Length)
            $replacements++
            $i += $oldBytes.Length - 1
        }
    }
    if ($replacements -lt 1) { throw 'Original integrity hash was not found in the ASAR header.' }
    [void]$stream.Seek(16, [IO.SeekOrigin]::Begin)
    $stream.Write($jsonBytes, 0, $jsonBytes.Length)
    $stream.Flush()
    Write-Output "Patched $InternalPath ($($replacementBytes.Length)/$originalSize bytes); updated $replacements integrity hashes to $newHash"
}
finally { $stream.Dispose() }
