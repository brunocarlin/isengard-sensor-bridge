param(
    [Parameter(Mandatory = $true)][string]$Archive,
    [Parameter(Mandatory = $true)][string]$Replacement,
    [Parameter(Mandatory = $true)][string]$OutputArchive
)
$ErrorActionPreference = 'Stop'
if ([IO.Path]::GetFullPath($Archive) -eq [IO.Path]::GetFullPath($OutputArchive)) {
    throw 'OutputArchive must differ from Archive.'
}
$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Archive).Path)
$payloadOffset = 8 + [BitConverter]::ToUInt32($bytes, 4)
$jsonLength = [BitConverter]::ToUInt32($bytes, 12)
$header = [Text.Encoding]::UTF8.GetString($bytes, 16, $jsonLength) | ConvertFrom-Json
$entry = $header.files.out.files.main.files.'index.js'
if (-not $entry -or $entry.unpacked) { throw 'Packed main entry not found.' }
# Keep the pinned archive hash stable across Git's Windows CRLF checkouts.
$replacementText = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Replacement).Path)
$replacementBytes = [Text.Encoding]::UTF8.GetBytes($replacementText.Replace("`r`n", "`n"))
$entry.offset = [string]($bytes.Length - $payloadOffset)
$entry.size = $replacementBytes.Length
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $hash = ([BitConverter]::ToString($sha.ComputeHash($replacementBytes))).Replace('-', '').ToLowerInvariant()
} finally { $sha.Dispose() }
# The small replacement occupies a single integrity block.
$entry | Add-Member -Force NoteProperty integrity ([pscustomobject]@{
    algorithm = 'SHA256'; hash = $hash; blockSize = 4194304; blocks = @($hash)
})
$json = [Text.Encoding]::UTF8.GetBytes(($header | ConvertTo-Json -Depth 100 -Compress))
$paddedLength = [int]([Math]::Ceiling($json.Length / 4.0) * 4)
$stream = [IO.File]::Open($OutputArchive, [IO.FileMode]::Create, [IO.FileAccess]::Write)
$writer = [IO.BinaryWriter]::new($stream)
try {
    $writer.Write([uint32]4)
    $writer.Write([uint32]($paddedLength + 8))
    $writer.Write([uint32]($paddedLength + 4))
    $writer.Write([uint32]$json.Length)
    $writer.Write($json)
    $writer.Write([byte[]]::new($paddedLength - $json.Length))
    $writer.Write($bytes, $payloadOffset, $bytes.Length - $payloadOffset)
    $writer.Write($replacementBytes)
} finally { $writer.Dispose() }
