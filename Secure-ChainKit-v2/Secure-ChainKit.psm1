$script:EndPoint = "https://api.pencildata.com"

Function Get-StringHash
{
    [cmdletbinding()]
    param(
        [string]$String,
        [string]$HashAlgorithm
    )

    $StringBuilder = New-Object System.Text.StringBuilder
    [System.Security.Cryptography.HashAlgorithm]::Create($HashAlgorithm).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($String)) | % {
        [Void]$StringBuilder.Append($_.ToString("x2"))
    }
    $StringBuilder.ToString()
}

function Invoke-RestAPI
{
    [cmdletbinding()]
    param(
        [hashtable]$Arguments
    )

    try
    {
        Invoke-WebRequest @Arguments
    }
    catch [System.Net.WebException]
    {
        $_.ErrorDetails.Message | Out-Default
        throw "Web request failed"
    }
    catch
    {
        $_.ErrorDetails.Message | Out-Default
        throw "General exception"
    }
}

Function Connect-CKService
{
    [cmdletbinding()]
    param(
        [PSCredential]$Credential
    )

    $credPlain = $Credential.GetNetworkCredential()
    $user = $credPlain.UserName
    $pswd = $credPlain.password

    $sWeb = @{
        Uri = "$($script:EndPoint)/token"
        Method = 'POST'
        Body = @{userId = $user; password = $pswd } | ConvertTo-Json
        Headers = @{'Content-Type' = 'application/json' }
    }
    $response = Invoke-RestAPI -Arguments $sWeb
    $script:ChainKitToken = ($response | ConvertFrom-Json).data.accessToken

    return $script:ChainKitToken
}

Function Disconnect-CKService
{
    [cmdletbinding()]
    param()

    $script:ChainKitToken = $null
}

Function Register-CKFile
{
    [cmdletbinding()]
    param(
        [string]$Path,
        [string]$Storage = 'concord',
        [string]$HashAlgorithm = "SHA256",
        [string]$Token = $script:Token
    )

    if ($null -eq $script:ChainKitToken)
    {
        Write-Error "You are currently not connected to the ChainKit service."
        return
    }

    $Content = -join (Get-Content -Path $Path)
    $contentsHash = Get-StringHash -String $Content -HashAlgorithm $HashAlgorithm

    $sWeb = @{
        Uri = "$($script:EndPoint)/register"
        Method = 'POST'
        Body = @{
            hash = $contentsHash
            description = "Hardened Script: {0}" -f $Path
            storage = $Storage
        } | ConvertTo-Json
        Headers = @{
            'Content-Type' = 'application/json'
            Authorization = "Bearer $('{0}' -f $script:ChainKitToken)"
        }
    }
    $response = Invoke-RestAPI -Arguments $sWeb
    $entityId = $response | ConvertFrom-Json

    New-Object -TypeName PSObject -Property @{
        entityId = $entityId
        hash = $contentsHash
    }
}

Function Test-CKFile()
{
    [cmdletbinding()]
    param(
        [parameter(Mandatory = $true)]
        [string]$Path,
        [string]$Hash,
        [string]$EntityId,
        [string]$Storage = "concord",
        [string]$HashAlgorithm = "SHA256",
        [int]$SkipLine = 0,
        [switch]$Abort
    )

    if ($null -eq $script:ChainKitToken)
    {
        Write-Error "You are currently not connected to the ChainKit service."
        return
    }

    $content = -join (Get-Content -Path $Path |
        Where-Object { $_.ReadCount -ne $SkipLine -and $_ -notmatch "<# CK #>|#region|#endregion" })
    $contentHash = Get-StringHash -String $content -HashAlgorithm $HashAlgorithm

    if ( $contentHash -ne $hash )
    {
        Throw "Script $Path does not have Hash of $Hash"
    }

    $sWeb = @{
        Uri = "$($script:endPoint)/verify/$($EntityId)?storage=$($Storage)&hash=$($contentHash)"
        Method = 'GET'
        Headers = @{
            'Content-Type' = 'application/json'
            Authorization = "Bearer $('{0}' -f $script:ChainKitToken)"
        }
    }
    $response = Invoke-RestAPI -Arguments $sWeb
    $verified = $response | ConvertFrom-Json
    if ($Abort -and -not $verified)
    {
        Throw "File did not pass verification"
    }
}

Function Protect-CKScript ()
{
    [cmdletbinding()]
    param(
        [STRING]$Path,
        [string]$Storage = 'concord',
        [string]$HashAlgorithm = "SHA256",
        [string]$Prefix = 'Secure'
    )

    $ckCode = @'
#region ChainKit
<# CK #>    Try {
<# CK #>        `$tCK = @{
<# CK #>            Path = '$newFile'
<# CK #>            Hash = '$($result.hash)'
<# CK #>            EntityId = '$($result.entityId)'
<# CK #>            Storage = '$Storage'
<# CK #>            HashAlgorithm = '$HashAlgorithm'
<# CK #>            Abort = `$true
<# CK #>        }
<# CK #>        Test-CKFile @tCK
<# CK #>    }
<# CK #>    Catch {
<# CK #>        Throw "Unable to verify script"
<# CK #>    }
#endregion

'@

    if ($null -eq $script:ChainKitToken)
    {
        Write-Error "You are currently not connected to the ChainKit service."
        return
    }

    $dir = Split-Path -Path $Path
    $file = Split-Path -Path $Path -leaf
    $newFile = "$dir\$Prefix-$file"

    $result = Register-CKFile -Path $Path -Storage $Storage -HashAlgorithm $HashAlgorithm

    $line = $ExecutionContext.InvokeCommand.ExpandString($ckCode)
    ($line, (Get-Content -Path $Path)) | Out-File -FilePath $newFile

    $result | Add-Member -Name FileName -Value $newFile -MemberType NoteProperty

    return $result
}