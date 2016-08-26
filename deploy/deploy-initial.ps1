<#
Prepare environment before it can be used in CD process.
This can be part of the CD process or then it can be executed beforehand.

Script requires that service principal is known. You can use
following queries to get the SPN information:
# Use you own search string to find your SPN:
Get-AzureRmADServicePrincipal -SearchString "VSTS.VSTSIntegrationAccount"

# If you now have correct SPN then you can call the script as follows:
$password = ConvertTo-SecureString -String "password" -Force -AsPlainText
$spn = (Get-AzureRmADServicePrincipal -SearchString "VSTS.VSTSIntegrationAccount")[0]

.\deploy-initial.ps1 -ServicePrincipal $spn.ApplicationId -AdminPassword $password

# If this gets created in CD process then you might not have access to the
# newly created key vault since service principal creates it.
# You can add yourself to they key vault using following commands:
$me = Get-AzureRmADUser -SearchString "your name"
Set-AzureRmKeyVaultAccessPolicy `
    -VaultName $VaultName `
    -ResourceGroupName $ResourceGroupName `
    -UserPrincipalName $me.UserPrincipalName `
    -PermissionsToKeys all `
    -PermissionsToSecrets all
#>
Param (
    [string] $ResourceGroupName = "ubuntudocker-local-rg",
    [string] $Location = "North Europe",
    [string] $VaultName = "ubuntudocker-local-kv",
    [Parameter(Mandatory=$true)] [string] $ServicePrincipal,
    [string] $VaultSecretName = "VirtualMachineAdminPassword",
    [string] $AdminUsername = "azureuser",
    [securestring] $AdminPassword
)

$ErrorActionPreference = "Stop"
if ((Get-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location -ErrorAction SilentlyContinue) -eq $null)
{
    Write-Host Creating resource group...
    New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location -Verbose

    Write-Host Creating key vault...
    New-AzureRmKeyVault `
        -VaultName $VaultName `
        -EnabledForDeployment `
        -EnabledForTemplateDeployment `
        -ResourceGroupName $ResourceGroupName `
        -Location $Location -Verbose

    Write-Host Setting access policy to the service principal...
    Set-AzureRmKeyVaultAccessPolicy `
        -VaultName $VaultName `
        -ResourceGroupName $ResourceGroupName `
        -PermissionsToSecrets get,set `
        -ServicePrincipalName $ServicePrincipal

    Write-Host Set admin password to key vault...
    Set-AzureKeyVaultSecret `
        -SecretValue $AdminPassword `
        -VaultName $VaultName `
        -Name $VaultSecretName
}
