param([string]$KeytoolPath = '')
$ErrorActionPreference = 'Stop'
$mobilePath = Split-Path $PSScriptRoot -Parent
$repositoryPath = Split-Path $mobilePath -Parent
$signingPath = Join-Path $mobilePath 'android'
$keyPath = Join-Path $signingPath 'upload-key.jks'
$propertiesPath = Join-Path $signingPath 'key.properties'
if ((Test-Path -LiteralPath $keyPath) -or (Test-Path -LiteralPath $propertiesPath)) {
    if ((Test-Path -LiteralPath $keyPath) -and (Test-Path -LiteralPath $propertiesPath)) {
        Write-Output 'Existing Android upload signing files preserved.'
        exit 0
    }
    throw 'Only one signing file exists. Restore its matching pair before building.'
}
if (-not $KeytoolPath) {
    $bundledKeytool = Join-Path $repositoryPath '.tools\java\jdk-17.0.20.1+1\bin\keytool.exe'
    if (Test-Path -LiteralPath $bundledKeytool) { $KeytoolPath = $bundledKeytool }
    else { $KeytoolPath = (Get-Command keytool -ErrorAction Stop).Source }
}
$randomBytes = New-Object byte[] 32
$randomGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$randomGenerator.GetBytes($randomBytes)
$randomGenerator.Dispose()
$uploadPassword = [BitConverter]::ToString($randomBytes).Replace('-', '')
$env:HANGE_UPLOAD_KEY_PASSWORD = $uploadPassword
try {
    & $KeytoolPath -genkeypair -keystore $keyPath -storetype JKS -alias upload -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=Hangeoreum Upload Key, OU=Mobile, O=Hangeoreum, C=KR' -storepass:env HANGE_UPLOAD_KEY_PASSWORD -keypass:env HANGE_UPLOAD_KEY_PASSWORD
    if ($LASTEXITCODE -ne 0) { throw 'Android upload-key generation failed.' }
    $properties = @('storeFile=../upload-key.jks', "storePassword=$uploadPassword", 'keyAlias=upload', "keyPassword=$uploadPassword") -join "`n"
    [System.IO.File]::WriteAllText($propertiesPath, $properties, [System.Text.UTF8Encoding]::new($false))
    Write-Output 'Android upload signing files generated locally. Back up android/upload-key.jks and android/key.properties together; both are ignored by Git.'
} finally {
    Remove-Item Env:\HANGE_UPLOAD_KEY_PASSWORD -ErrorAction SilentlyContinue
    $uploadPassword = $null
}
