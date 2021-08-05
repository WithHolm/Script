Describe "General script tests" -Tag "General"{
  BeforeDiscovery {
    $testcase = @{
      path = $env:ScriptPath
    }
    # $ScriptPath = $env:ScriptPath
  }

  it "Passes tokenizer" -TestCases $testcase {
    param($path)
    # $path = $env:ScriptPath
    # $content = get-content -raw -Path $Path
    $err = @()
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$null,[ref]$err)
    $err|ForEach-Object{
      Write-warning $_
    }
    $err.count|should -be 0
  }

  it "Can load" -TestCases $testcase{
    param($path)
    . $path
  }

  It "Loading script only exposes 1 command" -TestCases $testcase{
    param($path)
    $commands = Get-Command
    . $path
    (Get-Command).count|should -be ($commands.count + 1)
  }

  it "all parameters documented in get-help" -TestCases $testcase{
    param($path)
    . $path
    $command = ([System.IO.FileInfo]$path).BaseName
    $Parameters = (Get-Command $command).Parameters
    $help = get-help $command
  }
  
}