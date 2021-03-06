﻿# Copyright (c) 2018 Teradici Corporation
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

Param(
  [Parameter(Mandatory=$true)]
  [string]$rgName,

  [Parameter(Mandatory=$true)]
  [string]$azureUserName, 

  [Parameter(Mandatory=$true)]
  [string]$azurePassword,

  [Parameter(Mandatory=$false)]
  [string]$tenantID,

  [Parameter(Mandatory=$true)]
  [string]$subnetRef,

  [Parameter(Mandatory=$true)]
  [string]$backendIpAddressDefault,

  [Parameter(Mandatory=$true)]
  [string]$backendIpAddressForPathRule1,

  [Parameter(Mandatory=$true)]
  [string]$templateUri
)


# Create application gateway and a pre-baked certificate


Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module AzureRM -Force

# Login to Azure
$azurePwd = ConvertTo-SecureString $azurePassword -AsPlainText -Force
$azureloginCred = New-Object -TypeName pscredential –ArgumentList $azureUserName, $azurePwd
if($tenantID -and $tenantID -ne "null")
{
	Write-Host "Logging in SP $azureUserName in tenant $tenantID."
	Login-AzureRmAccount -ServicePrincipal -Credential $azureloginCred –TenantId $tenantID
}
else
{
	Write-Host "Logging in $azureUserName with no provided tenant ID."
    Login-AzureRmAccount -Credential $azureloginCred
}

# create self signed certificate
$certLoc = 'cert:Localmachine\My'
$startDate = [DateTime]::Now.AddDays(-1)
$subject = "CN=localhost,O=Teradici Corporation,OU=SoftPCoIP,L=Burnaby,ST=BC,C=CA"
$cert = New-SelfSignedCertificate -certstorelocation $certLoc -DnsName "*.cloudapp.net" -Subject $subject -KeyLength 3072 -FriendlyName "PCoIP Application Gateway" -NotBefore $startDate -TextExtension @("2.5.29.19={critical}{text}ca=1") -HashAlgorithm SHA384 -KeyUsage DigitalSignature, CertSign, CRLSign, KeyEncipherment

#generate pfx file from certificate
$certPath = $certLoc + '\' + $cert.Thumbprint

$pfxPath = 'C:\WindowsAzure'
if (!(Test-Path -Path $pfxPath)) {
	New-Item $pfxPath -type directory
}
$certPfx = $pfxPath + '\mySelfSignedCert.pfx'

#generate password for pfx file
$certPswd = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 16 | % {[char]$_})
$secureCertPswd = ConvertTo-SecureString -String $certPswd -AsPlainText -Force

#export pfx file
Export-PfxCertificate -Cert $certPath -FilePath $certPfx -Password $secureCertPswd

#read from pfx file and convert to base64 string
$fileContentEncoded = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($certPfx))

# deploy application gateway
$parameters = @{}
$parameters.Add(“subnetRef”, $subnetRef)
$parameters.Add(“skuName”, "Standard_Small")
$parameters.Add(“capacity”, 1)
$parameters.Add(“backendIpAddressDefault”, "$backendIpAddressDefault")
$parameters.Add(“backendIpAddressForPathRule1”, "$backendIpAddressForPathRule1")
$parameters.Add(“pathMatch1”, "/pcoip-broker/*")
$parameters.Add(“certData”, "$fileContentEncoded")
$parameters.Add(“certPassword”, "$certPswd")

New-AzureRmResourceGroupDeployment -Mode Incremental -Name "DeployAppGateway" -ResourceGroupName $rgName -TemplateUri $templateUri -TemplateParameterObject $parameters
