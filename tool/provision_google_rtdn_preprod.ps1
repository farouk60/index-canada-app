[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$GcloudPath,

    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Constantes volontairement non parametrables : ce script ne doit jamais viser
# un autre projet, un autre site Wix ou des ressources de production.
$ProjectId = 'index-immigrant-index-2025'
$ExpectedProjectNumber = '762725959551'
$Endpoint = 'https://immigrantindex.wixsite.com/website-1/_functions/googlePlayRtdn'
$Audience = $Endpoint

$PlayVerifierAccountId = 'indexca-play-verifier-preprod'
$PushOidcAccountId = 'index-canada-rtdn-push-preprod'
$PlayVerifierEmail = "$PlayVerifierAccountId@$ProjectId.iam.gserviceaccount.com"
$PushOidcEmail = "$PushOidcAccountId@$ProjectId.iam.gserviceaccount.com"

$TopicId = 'index-canada-rtdn-preprod'
$TopicName = "projects/$ProjectId/topics/$TopicId"
$SubscriptionId = 'index-canada-rtdn-preprod-push'
$SubscriptionName = "projects/$ProjectId/subscriptions/$SubscriptionId"
$GooglePlayPublisher = 'serviceAccount:google-play-developer-notifications@system.gserviceaccount.com'
$PubSubServiceAgent = "serviceAccount:service-$ExpectedProjectNumber@gcp-sa-pubsub.iam.gserviceaccount.com"

$RequiredApis = @(
    'androidpublisher.googleapis.com',
    'iam.googleapis.com',
    'iamcredentials.googleapis.com',
    'pubsub.googleapis.com',
    'serviceusage.googleapis.com'
)

function Assert-ServiceAccountId {
    param(
        [Parameter(Mandatory = $true)][string]$AccountId,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($AccountId.Length -lt 6 -or
        $AccountId.Length -gt 30 -or
        $AccountId -cnotmatch '^[a-z][a-z0-9-]{4,28}[a-z0-9]$') {
        throw "$Label '$AccountId' n'est pas un identifiant de compte de service Google valide (6 a 30 caracteres)."
    }
}

Assert-ServiceAccountId -AccountId $PlayVerifierAccountId -Label 'Play verifier'
Assert-ServiceAccountId -AccountId $PushOidcAccountId -Label 'Push OIDC'

function Resolve-GcloudExecutable {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    $command = Get-Command -Name $Path -CommandType Application, ExternalScript -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw 'gcloud est introuvable. Fournissez le chemin de gcloud.exe, gcloud.cmd ou gcloud.'
    }

    return $command.Source
}

function Invoke-Gcloud {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    # stderr est volontairement supprime : un WARNING ne doit jamais corrompre
    # une sortie JSON/liste et un objet d'erreur authentifie ne doit jamais etre
    # imprime. En cas d'echec, seul le code de sortie est expose.
    $output = @(& $script:GcloudExecutable @Arguments 2>$null)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$Operation a echoue (gcloud, code $exitCode). Aucun detail authentifie n'a ete affiche."
    }

    return @($output | ForEach-Object { $_.ToString() })
}

function Get-GcloudLines {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    return @(
        Invoke-Gcloud -Operation $Operation -Arguments $Arguments |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-GcloudJson {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $raw = (Invoke-Gcloud -Operation $Operation -Arguments $Arguments) -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "$Operation n'a retourne aucune donnee de validation."
    }

    try {
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        throw "$Operation a retourne une reponse illisible. Aucun contenu authentifie n'a ete affiche."
    }
}

function Get-JsonProperty {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-ServiceAccountDetailsWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Email,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    for ($attempt = 1; $attempt -le 19; $attempt++) {
        try {
            return Get-GcloudJson -Operation $Operation -Arguments @(
                'iam', 'service-accounts', 'describe', $Email,
                "--project=$ProjectId",
                '--format=json(email,displayName,description,disabled)'
            )
        } catch {
            if ($attempt -eq 19) {
                throw "$Operation a echoue apres une attente bornee de coherence IAM. Relancez le script; aucune permission large n'a ete ajoutee."
            }
            Start-Sleep -Seconds 5
        }
    }
}

function Test-UnconditionalIamBinding {
    param(
        [Parameter(Mandatory = $true)][object]$Policy,
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][string]$Member
    )

    $bindings = Get-JsonProperty -InputObject $Policy -Name 'bindings'
    foreach ($binding in @($bindings)) {
        if ((Get-JsonProperty -InputObject $binding -Name 'role') -ne $Role) {
            continue
        }

        $condition = Get-JsonProperty -InputObject $binding -Name 'condition'
        if ($null -ne $condition) {
            continue
        }

        $members = @(Get-JsonProperty -InputObject $binding -Name 'members')
        if ($members -contains $Member) {
            return $true
        }
    }

    return $false
}

function Ensure-ServiceAccount {
    param(
        [Parameter(Mandatory = $true)][string]$AccountId,
        [Parameter(Mandatory = $true)][string]$Email,
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $matches = @(Get-GcloudLines -Operation "Recherche du compte de service $AccountId" -Arguments @(
        'iam', 'service-accounts', 'list',
        "--project=$ProjectId",
        "--filter=email=$Email",
        '--format=value(email)'
    ))

    if ($matches -notcontains $Email) {
        if ($ValidateOnly) {
            throw "Le compte de service preproduction attendu est absent : $Email"
        }

        Invoke-Gcloud -Operation "Creation du compte de service $AccountId" -Arguments @(
            'iam', 'service-accounts', 'create', $AccountId,
            "--project=$ProjectId",
            "--display-name=$DisplayName",
            "--description=$Description",
            '--quiet'
        ) | Out-Null
    }

    $details = Get-ServiceAccountDetailsWithRetry `
        -Email $Email `
        -Operation "Lecture du compte de service $AccountId"

    if ((Get-JsonProperty -InputObject $details -Name 'disabled') -eq $true) {
        throw "Le compte de service preproduction est desactive et doit etre examine manuellement : $Email"
    }

    $needsUpdate =
        (Get-JsonProperty -InputObject $details -Name 'displayName') -ne $DisplayName -or
        (Get-JsonProperty -InputObject $details -Name 'description') -ne $Description

    if ($needsUpdate) {
        if ($ValidateOnly) {
            throw "Les metadonnees du compte de service ne correspondent pas a la preproduction : $Email"
        }

        Invoke-Gcloud -Operation "Mise a jour du compte de service $AccountId" -Arguments @(
            'iam', 'service-accounts', 'update', $Email,
            "--project=$ProjectId",
            "--display-name=$DisplayName",
            "--description=$Description",
            '--quiet'
        ) | Out-Null

        $details = Get-ServiceAccountDetailsWithRetry `
            -Email $Email `
            -Operation "Relecture du compte de service $AccountId"
    }

    if ((Get-JsonProperty -InputObject $details -Name 'email') -ne $Email -or
        (Get-JsonProperty -InputObject $details -Name 'displayName') -ne $DisplayName -or
        (Get-JsonProperty -InputObject $details -Name 'description') -ne $Description -or
        (Get-JsonProperty -InputObject $details -Name 'disabled') -eq $true) {
        throw "Validation du compte de service preproduction incomplete : $Email"
    }
}

function Test-ResourceExists {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$ExpectedName
    )

    $resources = @(Get-GcloudLines -Operation $Operation -Arguments $Arguments)
    return ($resources -contains $ExpectedName)
}

$script:GcloudExecutable = Resolve-GcloudExecutable -Path $GcloudPath
Invoke-Gcloud -Operation 'Validation de gcloud' -Arguments @('version') | Out-Null

$activeAccounts = @(Get-GcloudLines -Operation 'Validation de l authentification Google Cloud' -Arguments @(
    'auth', 'list',
    '--filter=status:ACTIVE',
    '--format=value(account)',
    '--verbosity=error'
))
if ($activeAccounts.Count -eq 0) {
    throw 'Aucune authentification gcloud active. Connectez-vous, puis relancez le script.'
}

$projectNumbers = @(Get-GcloudLines -Operation 'Validation du projet Google Cloud' -Arguments @(
    'projects', 'describe', $ProjectId,
    '--format=value(projectNumber)'
))
if ($projectNumbers.Count -ne 1 -or $projectNumbers[0] -ne $ExpectedProjectNumber) {
    throw "Le projet $ProjectId ne correspond pas au numero de projet preproduction attendu."
}

if (-not $ValidateOnly) {
    $enableApiArguments = @('services', 'enable') + $RequiredApis + @(
            "--project=$ProjectId",
            '--quiet'
        )
    Invoke-Gcloud -Operation 'Activation des API Google Cloud preproduction' -Arguments $enableApiArguments | Out-Null
}

foreach ($api in $RequiredApis) {
    $enabled = @(Get-GcloudLines -Operation "Validation de l API $api" -Arguments @(
        'services', 'list',
        '--enabled',
        "--project=$ProjectId",
        "--filter=config.name=$api",
        '--format=value(config.name)'
    ))
    if ($enabled -notcontains $api) {
        throw "L API preproduction requise n'est pas active : $api"
    }
}

if (-not $ValidateOnly) {
    Invoke-Gcloud -Operation 'Creation explicite de l identite de service Pub/Sub' -Arguments @(
        'beta', 'services', 'identity', 'create',
        '--service=pubsub.googleapis.com',
        "--project=$ProjectId",
        '--quiet'
    ) | Out-Null
}

Ensure-ServiceAccount `
    -AccountId $PlayVerifierAccountId `
    -Email $PlayVerifierEmail `
    -DisplayName 'Index Canada Play verifier preprod' `
    -Description 'Validates Google Play purchases for Index Canada preproduction; no Pub/Sub push signing.'

Ensure-ServiceAccount `
    -AccountId $PushOidcAccountId `
    -Email $PushOidcEmail `
    -DisplayName 'Index Canada RTDN push OIDC preprod' `
    -Description 'Signs Pub/Sub OIDC push tokens for Index Canada preproduction; no private key.'

if ($PlayVerifierEmail -eq $PushOidcEmail) {
    throw 'Les identites Play verifier et Push OIDC doivent rester distinctes.'
}

# Les identites de service gerees par Google peuvent refuser
# iam.serviceAccounts.get, meme au proprietaire du projet. La commande
# services identity create ci-dessus garantit l'identite, et la validation
# finale du binding Token Creator prouve que le principal attendu est utilise.

$pushUserManagedKeys = @(Get-GcloudLines -Operation 'Validation des cles du compte Push OIDC' -Arguments @(
    'iam', 'service-accounts', 'keys', 'list',
    "--iam-account=$PushOidcEmail",
    '--managed-by=user',
    '--format=value(name)',
    '--verbosity=error'
))
if ($pushUserManagedKeys.Count -gt 0) {
    throw 'Le compte Push OIDC possede une cle geree par l utilisateur. Le script refuse de continuer et ne supprime aucune cle automatiquement.'
}

$topicExists = Test-ResourceExists `
    -Operation 'Recherche du topic RTDN preproduction' `
    -ExpectedName $TopicName `
    -Arguments @(
        'pubsub', 'topics', 'list',
        "--project=$ProjectId",
        "--filter=name=$TopicName",
        '--format=value(name)'
    )

if (-not $topicExists) {
    if ($ValidateOnly) {
        throw "Le topic RTDN preproduction attendu est absent : $TopicName"
    }

    Invoke-Gcloud -Operation 'Creation du topic RTDN preproduction' -Arguments @(
        'pubsub', 'topics', 'create', $TopicId,
        "--project=$ProjectId",
        '--labels=application=index-canada,environment=preprod',
        '--quiet'
    ) | Out-Null
}

$topic = Get-GcloudJson -Operation 'Lecture du topic RTDN preproduction' -Arguments @(
    'pubsub', 'topics', 'describe', $TopicId,
    "--project=$ProjectId",
    '--format=json(name,labels)'
)
$topicLabels = Get-JsonProperty -InputObject $topic -Name 'labels'
$topicApplication = Get-JsonProperty -InputObject $topicLabels -Name 'application'
$topicEnvironment = Get-JsonProperty -InputObject $topicLabels -Name 'environment'
if ($topicApplication -ne 'index-canada' -or $topicEnvironment -ne 'preprod') {
    if ($ValidateOnly) {
        throw 'Les labels du topic RTDN ne correspondent pas a la preproduction.'
    }

    Invoke-Gcloud -Operation 'Mise a jour des labels du topic RTDN' -Arguments @(
        'pubsub', 'topics', 'update', $TopicId,
        "--project=$ProjectId",
        '--update-labels=application=index-canada,environment=preprod',
        '--quiet'
    ) | Out-Null
}

$topicPolicy = Get-GcloudJson -Operation 'Lecture de la politique IAM du topic RTDN' -Arguments @(
    'pubsub', 'topics', 'get-iam-policy', $TopicId,
    "--project=$ProjectId",
    '--format=json'
)
if (-not (Test-UnconditionalIamBinding -Policy $topicPolicy -Role 'roles/pubsub.publisher' -Member $GooglePlayPublisher)) {
    if ($ValidateOnly) {
        throw 'Google Play ne possede pas le role Pub/Sub Publisher attendu sur le topic preproduction.'
    }

    Invoke-Gcloud -Operation 'Ajout du publisher Google Play sur le topic RTDN' -Arguments @(
        'pubsub', 'topics', 'add-iam-policy-binding', $TopicId,
        "--project=$ProjectId",
        "--member=$GooglePlayPublisher",
        '--role=roles/pubsub.publisher',
        '--quiet'
    ) | Out-Null
}

$pushAccountPolicy = Get-GcloudJson -Operation 'Lecture de la politique IAM du compte Push OIDC' -Arguments @(
    'iam', 'service-accounts', 'get-iam-policy', $PushOidcEmail,
    "--project=$ProjectId",
    '--format=json'
)
if (-not (Test-UnconditionalIamBinding -Policy $pushAccountPolicy -Role 'roles/iam.serviceAccountTokenCreator' -Member $PubSubServiceAgent)) {
    if ($ValidateOnly) {
        throw 'Le service agent Pub/Sub ne peut pas creer les jetons OIDC du compte Push preproduction.'
    }

    Invoke-Gcloud -Operation 'Ajout du Token Creator limite au compte Push OIDC' -Arguments @(
        'iam', 'service-accounts', 'add-iam-policy-binding', $PushOidcEmail,
        "--project=$ProjectId",
        "--member=$PubSubServiceAgent",
        '--role=roles/iam.serviceAccountTokenCreator',
        '--condition=None',
        '--quiet'
    ) | Out-Null
}

$subscriptionExists = Test-ResourceExists `
    -Operation 'Recherche de l abonnement push RTDN preproduction' `
    -ExpectedName $SubscriptionName `
    -Arguments @(
        'pubsub', 'subscriptions', 'list',
        "--project=$ProjectId",
        "--filter=name=$SubscriptionName",
        '--format=value(name)'
    )

if (-not $subscriptionExists) {
    if ($ValidateOnly) {
        throw "L abonnement push RTDN preproduction attendu est absent : $SubscriptionName"
    }

    Invoke-Gcloud -Operation 'Creation de l abonnement push RTDN authentifie' -Arguments @(
        'pubsub', 'subscriptions', 'create', $SubscriptionId,
        "--project=$ProjectId",
        "--topic=$TopicId",
        "--push-endpoint=$Endpoint",
        "--push-auth-service-account=$PushOidcEmail",
        "--push-auth-token-audience=$Audience",
        '--ack-deadline=20',
        '--message-retention-duration=7d',
        '--expiration-period=never',
        '--labels=application=index-canada,environment=preprod',
        '--quiet'
    ) | Out-Null
} else {
    $subscription = Get-GcloudJson -Operation 'Lecture de l abonnement push RTDN' -Arguments @(
        'pubsub', 'subscriptions', 'describe', $SubscriptionId,
        "--project=$ProjectId",
        '--format=json(name,topic,pushConfig,labels,ackDeadlineSeconds,messageRetentionDuration,expirationPolicy)'
    )
    $pushConfig = Get-JsonProperty -InputObject $subscription -Name 'pushConfig'
    $oidcToken = Get-JsonProperty -InputObject $pushConfig -Name 'oidcToken'
    $labels = Get-JsonProperty -InputObject $subscription -Name 'labels'

    if ((Get-JsonProperty -InputObject $subscription -Name 'topic') -ne $TopicName) {
        throw 'L abonnement preproduction existant vise un autre topic. Le script refuse de le supprimer ou de le recreer automatiquement.'
    }

    $pushConfigNeedsUpdate =
        (Get-JsonProperty -InputObject $pushConfig -Name 'pushEndpoint') -ne $Endpoint -or
        (Get-JsonProperty -InputObject $oidcToken -Name 'serviceAccountEmail') -ne $PushOidcEmail -or
        (Get-JsonProperty -InputObject $oidcToken -Name 'audience') -ne $Audience -or
        $null -ne (Get-JsonProperty -InputObject $pushConfig -Name 'noWrapper')
    $subscriptionLabelsNeedUpdate =
        (Get-JsonProperty -InputObject $labels -Name 'application') -ne 'index-canada' -or
        (Get-JsonProperty -InputObject $labels -Name 'environment') -ne 'preprod'
    $subscriptionDeliveryNeedsUpdate =
        [string](Get-JsonProperty -InputObject $subscription -Name 'ackDeadlineSeconds') -ne '20' -or
        (Get-JsonProperty -InputObject $subscription -Name 'messageRetentionDuration') -ne '604800s'
    $subscriptionExpirationPolicy = Get-JsonProperty -InputObject $subscription -Name 'expirationPolicy'
    $subscriptionExpirationNeedsUpdate =
        $null -eq $subscriptionExpirationPolicy -or
        $null -ne (Get-JsonProperty -InputObject $subscriptionExpirationPolicy -Name 'ttl')

    if ($pushConfigNeedsUpdate -or $subscriptionLabelsNeedUpdate -or
        $subscriptionDeliveryNeedsUpdate -or $subscriptionExpirationNeedsUpdate) {
        if ($ValidateOnly) {
            throw 'L abonnement push ne correspond pas a la configuration RTDN preproduction attendue.'
        }
    }

    if ($pushConfigNeedsUpdate) {
        Invoke-Gcloud -Operation 'Mise a jour de l abonnement push RTDN authentifie' -Arguments @(
            'pubsub', 'subscriptions', 'update', $SubscriptionId,
            "--project=$ProjectId",
            "--push-endpoint=$Endpoint",
            "--push-auth-service-account=$PushOidcEmail",
            "--push-auth-token-audience=$Audience",
            '--clear-push-no-wrapper-config',
            '--quiet'
        ) | Out-Null
    }

    if ($subscriptionLabelsNeedUpdate) {
        Invoke-Gcloud -Operation 'Mise a jour des labels de l abonnement RTDN' -Arguments @(
            'pubsub', 'subscriptions', 'update', $SubscriptionId,
            "--project=$ProjectId",
            '--update-labels=application=index-canada,environment=preprod',
            '--quiet'
        ) | Out-Null
    }

    if ($subscriptionDeliveryNeedsUpdate -or $subscriptionExpirationNeedsUpdate) {
        Invoke-Gcloud -Operation 'Mise a jour de la conservation de l abonnement RTDN' -Arguments @(
            'pubsub', 'subscriptions', 'update', $SubscriptionId,
            "--project=$ProjectId",
            '--ack-deadline=20',
            '--message-retention-duration=7d',
            '--expiration-period=never',
            '--quiet'
        ) | Out-Null
    }
}

# Relecture finale : aucune valeur secrete n'est demandee ni affichee.
$finalTopic = Get-GcloudJson -Operation 'Validation finale du topic RTDN' -Arguments @(
    'pubsub', 'topics', 'describe', $TopicId,
    "--project=$ProjectId",
    '--format=json(name,labels)'
)
$finalTopicLabels = Get-JsonProperty -InputObject $finalTopic -Name 'labels'
if ((Get-JsonProperty -InputObject $finalTopic -Name 'name') -ne $TopicName -or
    (Get-JsonProperty -InputObject $finalTopicLabels -Name 'application') -ne 'index-canada' -or
    (Get-JsonProperty -InputObject $finalTopicLabels -Name 'environment') -ne 'preprod') {
    throw 'Validation finale impossible : topic RTDN preproduction non conforme.'
}

$finalTopicPolicy = Get-GcloudJson -Operation 'Validation finale de la politique du topic' -Arguments @(
    'pubsub', 'topics', 'get-iam-policy', $TopicId,
    "--project=$ProjectId",
    '--format=json'
)
if (-not (Test-UnconditionalIamBinding -Policy $finalTopicPolicy -Role 'roles/pubsub.publisher' -Member $GooglePlayPublisher)) {
    throw 'Validation finale impossible : publisher Google Play absent du topic.'
}

$finalPushPolicy = Get-GcloudJson -Operation 'Validation finale de la politique Push OIDC' -Arguments @(
    'iam', 'service-accounts', 'get-iam-policy', $PushOidcEmail,
    "--project=$ProjectId",
    '--format=json'
)
if (-not (Test-UnconditionalIamBinding -Policy $finalPushPolicy -Role 'roles/iam.serviceAccountTokenCreator' -Member $PubSubServiceAgent)) {
    throw 'Validation finale impossible : Token Creator Pub/Sub absent du compte Push OIDC.'
}

$finalSubscription = Get-GcloudJson -Operation 'Validation finale de l abonnement RTDN' -Arguments @(
    'pubsub', 'subscriptions', 'describe', $SubscriptionId,
    "--project=$ProjectId",
    '--format=json(name,topic,pushConfig,labels,ackDeadlineSeconds,messageRetentionDuration,expirationPolicy)'
)
$finalPushConfig = Get-JsonProperty -InputObject $finalSubscription -Name 'pushConfig'
$finalOidcToken = Get-JsonProperty -InputObject $finalPushConfig -Name 'oidcToken'
$finalLabels = Get-JsonProperty -InputObject $finalSubscription -Name 'labels'

$validationFailures = @()
if ((Get-JsonProperty -InputObject $finalSubscription -Name 'name') -ne $SubscriptionName) {
    $validationFailures += 'nom abonnement'
}
if ((Get-JsonProperty -InputObject $finalSubscription -Name 'topic') -ne $TopicName) {
    $validationFailures += 'topic'
}
if ((Get-JsonProperty -InputObject $finalPushConfig -Name 'pushEndpoint') -ne $Endpoint) {
    $validationFailures += 'endpoint'
}
if ((Get-JsonProperty -InputObject $finalOidcToken -Name 'serviceAccountEmail') -ne $PushOidcEmail) {
    $validationFailures += 'identite OIDC'
}
if ((Get-JsonProperty -InputObject $finalOidcToken -Name 'audience') -ne $Audience) {
    $validationFailures += 'audience OIDC'
}
if ($null -ne (Get-JsonProperty -InputObject $finalPushConfig -Name 'noWrapper')) {
    $validationFailures += 'enveloppe Pub/Sub'
}
if ((Get-JsonProperty -InputObject $finalLabels -Name 'application') -ne 'index-canada' -or
    (Get-JsonProperty -InputObject $finalLabels -Name 'environment') -ne 'preprod') {
    $validationFailures += 'labels preproduction'
}
if ([string](Get-JsonProperty -InputObject $finalSubscription -Name 'ackDeadlineSeconds') -ne '20') {
    $validationFailures += 'delai acquittement'
}
if ((Get-JsonProperty -InputObject $finalSubscription -Name 'messageRetentionDuration') -ne '604800s') {
    $validationFailures += 'retention messages'
}
$finalExpirationPolicy = Get-JsonProperty -InputObject $finalSubscription -Name 'expirationPolicy'
if ($null -eq $finalExpirationPolicy -or
    $null -ne (Get-JsonProperty -InputObject $finalExpirationPolicy -Name 'ttl')) {
    $validationFailures += 'expiration abonnement'
}

if ($validationFailures.Count -gt 0) {
    throw "Validation finale RTDN incomplete : $($validationFailures -join ', ')."
}

$mode = if ($ValidateOnly) { 'validation' } else { 'provisionnement' }
Write-Output "RTDN Google Play preproduction : $mode termine avec succes."
Write-Output "Projet valide : $ProjectId ($ExpectedProjectNumber)"
Write-Output "Topic valide : $TopicName"
Write-Output "Abonnement push authentifie et enveloppe valide : $SubscriptionName"
Write-Output 'Aucune cle privee n a ete creee, exportee, lue ou affichee.'
