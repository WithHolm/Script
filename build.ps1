
if (!(Get-module -list psdepend))
{
  Install-Module -Scope CurrentUser -Force -SkipPublisherCheck
}

import-module PSDepend
$depend = @{
  psake    = 'latest'
  Pester   = 'latest'
  psdepend = "latest"
}
$depend|Invoke-PSDepend -Install -Force

Invoke-psake -buildFile "$PSScriptRoot/psakefile.ps1"