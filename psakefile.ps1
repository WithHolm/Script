Properties {
  $ScriptFolders = @(
    "ConvertTo-splat"
  ) | ForEach-Object { get-item (join-path $psake.build_script_dir $_) }
}

task default -depends pester

task pester -depends Pester_General, Pester_Specific

task Pester_General {
  foreach ($ScriptFolder in $ScriptFolders)
  {
    $script = (join-path $ScriptFolder.FullName "$($ScriptFolder.Name).ps1")
    $env:ScriptPath = $script
    $GeneralPester = Invoke-Pester -TagFilter "General" -PassThru -Output None
    
    if ($GeneralPester.FailedCount -gt 0)
    {
      $GeneralPester.Failed | ForEach-Object {
        Write-Warning "$($ScriptFolder.Name) Failed '$($_.name)': $($_.ErrorRecord)"
      }
      # $GeneralPester
      throw "Script '$($ScriptFolder.Name)' failed general tests"
    }
    else
    {
      "Script '$($ScriptFolder.Name)' passed general tests"
    }

  }
}

task Pester_Specific {
  foreach ($ScriptFolder in $ScriptFolders)
  {
    $script = (join-path $ScriptFolder.FullName "$($ScriptFolder.Name).ps1")
    $env:ScriptPath = $script
    . $script
    $UnitTests = Invoke-Pester -Path $ScriptFolder.FullName -PassThru -Output Detailed
    if ($UnitTests.FailedCount -gt 0)
    {
      throw "Script '$($ScriptFolder.Name)' failed unit tests"
    }
    else
    {
      "Script '$($ScriptFolder.Name)' passed unit tests"
    }
  }
}

task BuildInfo {
  $GitRemoteUri = [uri](git config --get remote.origin.url)
  $GitProjectName = $GitRemoteUri.PathAndQuery.Replace(".git","")
  $GitProjectUri = "http://github.com/"+$GitProjectName
  $GitUserContentUri = "https://raw.githubusercontent.com/"+$GitProjectName
  foreach ($ScriptFolder in $ScriptFolders)
  {
    $script = (join-path $ScriptFolder.FullName "$($ScriptFolder.Name).ps1")
    $Info = @{
      version                    = ""
      guid                       = ""
      author                     = "Philip Meholm"
      companyname                = ""
      copyright                  = "Philip Meholm"
      tags                       = @("Withholm",$ScriptFolder.Name.Split("-"))
      licenseuri                 = $GitUserContentUri+"/main/licence.txt" 
      projecturi                 = $GitProjectUri+"/tree/main/"+$ScriptFolder.Name
      iconuri                    = ""
      externalmoduledependencies = ""
      requiredscripts            = ""
      externalscriptdependencies = ""
      releasenotes               = ""
      privatedata                = ""
    }
    
  }
}

task publish -depends pester  -action {
  if ([string]::IsNullOrEmpty($env:publishToken))
  {
    throw "no publishtoken set"
  }
}

