Param (
    [string] $ResourceGroupName = "ubuntudocker-local-rg",
    [string] $Location = "North Europe",
    [string] $Template = "$PSScriptRoot\azuredeploy.json",
    [string] $TemplateParameters = "$PSScriptRoot\azuredeploy.parameters.json",
    [string] $VaultOwner,
    [string] $VaultName = "ubuntudocker-local-kv",
    [string] $VaultSecretName = "VirtualMachineAdminPassword",
    [string] $AdminUsername = "azureuser"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrEmpty($env:RELEASE_DEFINITIONNAME))
{
    Write-Host (@"
Not executing inside VSTS Release Management.
Make sure you have done "Login-AzureRmAccount" and
"Select-AzureRmSubscription -SubscriptionName name"
so that script continues to work correctly for you.
"@)
}

if ((Get-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location -ErrorAction SilentlyContinue) -eq $null)
{
    Throw "Resource group '$ResourceGroupName' doesn't exist which means 'deploy-initial.ps1' is not called correctly."
}

# Get password from key vault
$secret = Get-AzureKeyVaultSecret -VaultName $VaultName -Name $VaultSecretName

# Create additional parameters that we pass to the template deployment
$additionalParameters = New-Object -TypeName hashtable
$additionalParameters['adminUsername'] = $AdminUsername
$additionalParameters['adminPassword'] = $secret.SecretValue

$result = New-AzureRmResourceGroupDeployment `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile $Template `
    -TemplateParameterFile $TemplateParameters `
    @additionalParameters `
    -Verbose

$result
if ($result.Outputs.fqdn -eq $null)
{
    Throw "Template deployment didn't return FQDN correctly and therefore deployment is cancelled."
}

$fqdn = $result.Outputs.fqdn.value

#
# As an _added_ bonus you can do all sorts of scripting
# since we have username and password available!
#
# Below example grabs "secure copy" tools from web and uses them to push
# simple script to the vm and then executes it. This enables
# any custom deployments you wish.
#
cd $PSScriptRoot
Invoke-WebRequest -Uri "https://the.earth.li/~sgtatham/putty/latest/x86/pscp.exe" -OutFile pscp.exe
Invoke-WebRequest -Uri "https://the.earth.li/~sgtatham/putty/latest/x86/plink.exe" -OutFile plink.exe
del log.txt -ErrorAction SilentlyContinue

$hostKey = ""
$ErrorActionPreference = "Continue"
.\pscp.exe -sshlog log.txt `
    -l $AdminUsername -pw $secret.SecretValueText `
    -batch *.sh ($fqdn + ":.") 2> $null
if ($LastExitCode -eq 1)
{
    # Most likely the host key check failed so we need to grab the
    # host key from log and pass that on the command-line:
    $hostKeyFind = (Get-Content .\log.txt | Select-String -Pattern "^Event Log: ssh-rsa \d* ([\d|a-z|:]*)")
    $hostKey = $hostKeyFind.Matches[0].Groups[1].Value
    .\pscp.exe `
        -l $AdminUsername -pw $secret.SecretValueText `
        -batch -hostkey "$hostKey" *.sh ($fqdn + ":.")
}

# Below command will execute script and print out
# "This is script coming from repository" text in console
.\plink.exe `
    -l $AdminUsername -pw $secret.SecretValueText `
    -batch -hostkey "$hostKey" $fqdn "bash deploy.sh"
