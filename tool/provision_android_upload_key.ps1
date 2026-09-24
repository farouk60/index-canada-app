param(
    [string]$KeytoolPath,
    [string]$CertificatePath = (Join-Path ([System.IO.Path]::GetTempPath()) 'index-canada-upload-certificate.pem')
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$androidDirectory = Join-Path $repositoryRoot 'android'
$keystorePath = Join-Path $androidDirectory 'upload-keystore.jks'
$propertiesPath = Join-Path $androidDirectory 'key.properties'

if (Test-Path -LiteralPath $keystorePath) {
    throw "Refus d'écraser le keystore existant : $keystorePath"
}

if (Test-Path -LiteralPath $propertiesPath) {
    throw "Refus d'écraser la configuration existante : $propertiesPath"
}

if ([string]::IsNullOrWhiteSpace($KeytoolPath)) {
    $keytoolCommand = Get-Command keytool.exe -ErrorAction SilentlyContinue
    if ($null -ne $keytoolCommand) {
        $KeytoolPath = $keytoolCommand.Source
    } else {
        $candidates = @(
            'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe',
            'C:\Program Files (x86)\Java\jre1.8.0_201\bin\keytool.exe'
        )
        $KeytoolPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
}

if ([string]::IsNullOrWhiteSpace($KeytoolPath) -or -not (Test-Path -LiteralPath $KeytoolPath)) {
    throw 'keytool.exe est introuvable. Fournissez son chemin avec -KeytoolPath.'
}

$randomBytes = New-Object byte[] 32
$randomGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $randomGenerator.GetBytes($randomBytes)
} finally {
    $randomGenerator.Dispose()
}
$password = [Convert]::ToBase64String($randomBytes).TrimEnd('=').Replace('+', 'A').Replace('/', 'B')

& $KeytoolPath `
    -genkeypair `
    -noprompt `
    -keystore $keystorePath `
    -storetype JKS `
    -alias upload `
    -keyalg RSA `
    -keysize 2048 `
    -validity 10000 `
    -dname 'CN=Index Canada, OU=Mobile, O=Immigrant Index Inc., L=Montreal, ST=Quebec, C=CA' `
    -storepass $password `
    -keypass $password
if ($LASTEXITCODE -ne 0) {
    throw "La génération du keystore a échoué avec le code $LASTEXITCODE."
}

& $KeytoolPath `
    -exportcert `
    -rfc `
    -keystore $keystorePath `
    -alias upload `
    -file $CertificatePath `
    -storepass $password
if ($LASTEXITCODE -ne 0) {
    throw "L'export du certificat a échoué avec le code $LASTEXITCODE."
}

$properties = @(
    "storePassword=$password",
    "keyPassword=$password",
    'keyAlias=upload',
    'storeFile=../upload-keystore.jks'
) -join [Environment]::NewLine
[System.IO.File]::WriteAllText(
    $propertiesPath,
    $properties + [Environment]::NewLine,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Output "Keystore créé : $keystorePath"
Write-Output "Configuration locale créée : $propertiesPath"
Write-Output "Certificat public créé : $CertificatePath"
