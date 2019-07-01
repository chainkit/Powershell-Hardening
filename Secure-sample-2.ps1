#region ChainKit
<# CK #>    Try {
<# CK #>        $tCK = @{
<# CK #>            Path = '.\Secure-sample-2.ps1'
<# CK #>            Hash = '488ba058391d944600e90e96bf91c873bfb4732ce1a247d1a4d6c75f9fda4c90'
<# CK #>            EntityId = '6566617573829110776'
<# CK #>            Storage = 'concord'
<# CK #>            HashAlgorithm = 'SHA256'
<# CK #>            Abort = $true
<# CK #>        }
<# CK #>        Test-CKFile @tCK
<# CK #>    }
<# CK #>    Catch {
<# CK #>        Throw "Unable to verify script"
<# CK #>    }
#endregion

# Simple vSphere object retrieval

#
# Data is stored in JSON file
# Layout file
# {
#   "vCenter": "vcsa-FQDN"
# }
#

$data = Get-Content -Path .\sample-2.json | ConvertFrom-Json

Connect-VIServer -Server $data.vCenter | Out-Null

$mask = "esx[13].local.lab"
Get-VMHost -Name $mask | Select-Object Name

Disconnect-VIServer -Server $data.vCenter -confirm:$false
