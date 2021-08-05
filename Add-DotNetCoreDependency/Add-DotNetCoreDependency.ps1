<#
.SYNOPSIS
Imports nuget dependencies to your solution. supports dotnet core and standard packages.

.DESCRIPTION
Using dotnet client, finds and downloads correct packages and imports then to your desired path

.PARAMETER VersionMap
hashtable map of the solutions you want to use 

.PARAMETER SavePath
Parameter description

.PARAMETER PersistTag
Parameter description

.EXAMPLE
An example

.NOTES
General notes
#>
function Add-DotNetCoreDependency
{
  [CmdletBinding()]
  param (
    # [String]$Name,
    # [String]$Version,
    [parameter(
      ParameterSetName = "PackageMap",
      Mandatory,
      HelpMessage = "hashtable with packagename = version"
    )]
    $PackageMap,

    [parameter(
      Mandatory,
      HelpMessage = "hashtable with packagename = version"
    )]
    [System.IO.DirectoryInfo]$SavePath,

    # [parameter(
    #   HelpMessage = "Set a name so that future adds on your client will get faster"
    # )]
    # [String]$PersistTag,
    
    [ValidateSet("net5.0","netstandard2.1","netcoreapp3.1","net48","net45")]
    [String]$TargetFramework = "netcoreapp3.1"
  )
  
  begin
  {
    #i dont really know if it works with a lover version..
    $RequiredDotnetVersion = "3.0.0"

    #check for dotnet
    if (!(Get-command dotnet -ErrorAction SilentlyContinue))
    {
      Throw "You need to have dotnet cli in order to continue"
    }
    elseif ([version](dotnet --version) -lt [version]$RequiredDotnetVersion)
    {
      throw "You need to have atleast version '$RequiredDotnetVersion' of dotnet. you have '$(dotnet --version)'"
    }


    $ProjectCacheName = [system.io.path]::GetRandomFileName().split('.')[0]
    if ($PersistTag)
    {
      $ProjectCacheName = $PersistTag
    }

    $cache = (dotnet nuget locals global-packages --list).split("global-packages:")[-1].trim()
    $ProjectTemp = [System.IO.DirectoryInfo](join-path -Path $env:TEMP -ChildPath "DotnetImport/$ProjectCacheName")
    $Logfile = Join-Path $ProjectTemp ([system.io.path]::GetRandomFileName())
    # $Options = @{
    #   cache       = (dotnet nuget locals global-packages --list).split("global-packages:")[-1].trim()
    #   ProjectTemp = [System.IO.DirectoryInfo](join-path -Path $env:TEMP -ChildPath "DotnetImport/$ProjectCacheName")
    # }
    # $Options.log = Join-Path $Options.ProjectTemp ([system.io.path]::GetRandomFileName())

    if (-not $ProjectTemp.Exists)
    {
      Write-Verbose "Creating new path '$($Options.ProjectTemp)'"
      new-item -Path $ProjectTemp.FullName -ItemType Directory|Out-Null
    }
    elseif ([string]::IsNullOrEmpty($PersistTag) -and (Get-ChildItem $Options.ProjectTemp.FullName))
    {
      Write-Verbose "Cleaning out existsing path '$($Options.ProjectTemp)'"
      Get-ChildItem $ProjectTemp.FullName | remove-item -Recurse -Force
    }
  }
  
  process
  {
    $CurrentLoc = Get-Location
    try{
      Write-Verbose "Setting working directory to $($Options.ProjectTemp)"
      Set-Location $ProjectTemp

    
      if(!(Get-ChildItem -Filter "*.csproj"))
      {
        Write-Verbose "Creating new project"
        dotnet new console|out-null
      }

      #region fix target version
      $ProjectFile = Get-ChildItem -Filter "*.csproj"
      $ProjectFileContent = [xml](Get-Content $ProjectFile)
      $ProjectFileContent.Project.PropertyGroup.TargetFramework = ($TargetFramework -join ";")
      $ProjectFileContent.Save($ProjectFile.FullName)
      #endregion

      # $InstalledPackages = $ProjectFileContent.Project.ItemGroup.PackageReference
      foreach($add in $PackageMap.GetEnumerator())
      {
        $RequestVersion = $Add.value
        $RequestName = $Add.name

        if($RequestVersion -eq "latest")
        {
          dotnet add package $RequestName -n #&2> $
        }
        else {
          dotnet add package $RequestName -v $RequestVersion -n #&2> $
        }

        dotnet restore #$

        # who does this start a job?
        #dotnet restore &2> $ 
      }
    }
    catch{
      throw $_
    }
    finally{
      Set-Location $CurrentLoc
      if($ProjectTemp.Exists)
      {
        remove-item $ProjectTemp.FullName -Recurse
      }
    }
  }
  
  end
  {
    
  }
}
Add-DotNetCoreDependency -PackageMap @{"newtonsoft.json" = "latest" } -SavePath "c:\testing"
# Import-DotNetCoreDependencies -