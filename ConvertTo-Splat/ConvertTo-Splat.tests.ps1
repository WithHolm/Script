Describe "ConvertTo-ParamHash" -Tag "ConvertTo-ParamHash" {
  BeforeAll {
    Function ConvertTo-Answer
    {
      param([scriptblock]$sb)
      $answer = $sb.tostring().split("`n").split("`r") | Where-Object { $_ }
      $answer = $answer | Join-String -Separator ([System.Environment]::NewLine)
      return $answer
    }
  }

  # BeforeDiscovery {
  #   Function ConvertTo-Answer
  #   {
  #     param([scriptblock]$sb)
  #     $answer = $sb.tostring().split("`n")|Where-Object{$_}
  #     $answer = $answer | Join-String -Separator ([System.Environment]::NewLine)
  #     return $answer
  #   }
  # }
  context "Inputs" {

    it "command without parameters" {
      $question = "Get-Command"
      $question | ConvertTo-Splat | should -be 'get-command'
    }
    
    it "command from <name>" -TestCases @(
      @{
        name = "scriptblock"
        q    = { Get-Command -Name "test" }
        a    = @(
          '$getcommandParam = @{'
          '    Name = "test"'
          '}'
          'Get-Command @getcommandParam'
        )
      }
      @{
        name = "string"
        q    = 'Get-Command -Name "test"'
        a    = @(
          '$getcommandParam = @{'
          '    Name = "test"'
          '}'
          'Get-Command @getcommandParam'
        )
      }
    ) -Test {
      param(
        $name,
        $q,
        $a
      )
      $q | ConvertTo-Splat | should -Be ($a -join [System.Environment]::NewLine)
    }
    
    it "switch <name>" -TestCases @(
      @{
        name = "default"
        q    = { Get-Command -Syntax }
        a    = @(
          '$getcommandParam = @{'
          '    Syntax = $true'
          '}'
          'Get-Command @getcommandParam'
        )
      }
      @{
        name = "with override false"
        q    = { Get-Command -Syntax:$false }
        a    = @(
          '$getcommandParam = @{'
          '    Syntax = $false'
          '}'
          'Get-Command @getcommandParam'
        )
      }
      @{
        name = "with override true"
        q    = { Get-Command -Syntax:$false }
        a    = @(
          '$getcommandParam = @{'
          '    Syntax = $false'
          '}'
          'Get-Command @getcommandParam'
        )
      }
    ) {
      param(
        $name,
        $q,
        $a
      )
      $q | ConvertTo-Splat | should -Be ($a -join [System.Environment]::NewLine)
    }
    
    it "command with backticks" {
      $answer = @(
        '$getcommandParam = @{'
        '    Name   = "test"'
        '    module = "other"'
        '}'
        'Get-Command @getcommandParam'
      )
      { get-command `
          -Name "test"`
          -Module "other" } | ConvertTo-Splat | should -Be ($answer -join [System.Environment]::NewLine)
    }
    
    it "hashtable, <name> output non compressed"-TestCases @(
      @{
        name = "non-compressed"
        q    = { Get-content -ReadCount @{
            test  = 'testing'
            test2 = "testing"
          } }
        a    = @(
          '$getcontentParam = @{'
          '    ReadCount = @{'
          '        test  = "testing"'
          '        test2 = "testing"'
          '    }'
          '}'
          'Get-content @getcontentParam')
      },
      @{
        name = "compressed"
        q    = { Get-content -ReadCount @{test = 'testing'; other = "testing" } }
        a    = @(
          '$getcontentParam = @{'
          '    ReadCount = @{'
          '        test  = "testing"'
          '        other = "testing"'
          '    }'
          '}'
          'Get-content @getcontentParam')
      }
    ) -test {
      param(
        $name,
        $q,
        $a
      )
      $q | ConvertTo-Splat | should -be ($a -join [System.Environment]::NewLine)
    }
    
    it "hashtable, <name>, output compressed"-TestCases @(
      @{
        name = "non-compressed"
        q    = { Get-content -ReadCount @{
            test  = 'testing'
            test2 = "testing"
          } }
        a    = @(
          '$getcontentParam = @{'
          '    ReadCount = @{test="testing"; test2="testing"}'
          '}'
          'Get-content @getcontentParam')
      },
      @{
        name = "compressed"
        q    = { Get-content -ReadCount @{test = 'testing'; other = "testing" } }
        a    = @(
          '$getcontentParam = @{'
          '    ReadCount = @{test="testing"; other="testing"}'
          '}'
          'Get-content @getcontentParam')
      }
    ) -test {
      param(
        $name,
        $q,
        $a
      )
      $q | ConvertTo-Splat -CompressObjectValues | should -be ($a -join [System.Environment]::NewLine)
    }
    
    it "casted object" {
      $Answer = @(
        '$getcontentParam = @{'
        '    ReadCount = ([ordered]@{'
        '        test  = "testing"'
        '        other = "test"'
        '    })'
        '}'
        'Get-content @getcontentParam'
      )
      $sb = { Get-content -ReadCount ([ordered]@{test = 'testing'; other = "test" }) }
      { $sb | ConvertTo-Splat } | should -not -Throw
      $sb | ConvertTo-Splat | should -be ($answer -join "`r`n")
    }
    
    it "array" {
      $Answer = @(
        '$getcontentParam = @{'
        '    ReadCount = @("one","two")'
        '}'
        'Get-content @getcontentParam')
      { Get-content -ReadCount @("one", "two") } | ConvertTo-Splat | should -be ($answer -join [System.Environment]::NewLine)
    }
    
    it "scriptblock" {
      $answer = @(
        '$invokepsdependParam = @{'
        '    PSDependTypePath = {'
        '        get-content "test.ps1" -raw'
        '        other-command -param'
        '        Test-Lineshift'
        '    }'
        '}'
        'Invoke-PSDepend @invokepsdependParam'
      )
    
      { Invoke-PSDepend -PSDependTypePath {
          get-content 'test.ps1' -raw; other-command -param
          Test-Lineshift
        }
      } | ConvertTo-Splat | should -be ($answer -join [System.Environment]::NewLine)
    }
  }

  context "Parameters" {
    it "-TabSpaceCount: can supports <space> spaces form tab" -TestCases (@(1..9) | % { @{space = $_ } }) {
      param(
        [int]$space
      )
    
      $Checkval = ( { get-content -Path "path" } | ConvertTo-Splat -TabSpaceCount $space).split([System.Environment]::NewLine)[1]
      $answer = "$(' '*$space)Path = ""path"""
      $Checkval | should -be $answer
    }
    
    it "-TabSpaceCount: should throw when int is <explain> <limit>: <space>" -TestCases @(
      @{
        explain = "below"
        limit   = 1
        space   = 0
      },
      @{
        explain = "over"
        limit   = 10
        space   = 11
      },
      @{
        explain = "over"
        limit   = 10
        space   = 12
      }
    ) {
      param(
        $explain,
        $limit,
        $space
      )
      { { get-command "test" } | ConvertTo-Splat -TabSpaceCount $space } | should -Throw
    }
  }
}