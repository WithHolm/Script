

<#
.SYNOPSIS
Converts a command line with parameters to splatted commands

.DESCRIPTION
Converts a command inside string or scriptblock using standard "-param value" to a splatted command

.PARAMETER InputItem
string or scriptblock

.PARAMETER TabSpaceCount
How many spaces are in a tab? defaults to 4

.PARAMETER SplatParamName
Sets the name of the parameter used for splatting. if not defined, it will use the command name as a base for the parameter

.PARAMETER CompressObjectValues
compresses objects using ; delimiter instead of new lines. single property objects will be treated as compressed

.EXAMPLE
{get-command -name "test"}|convertto-splat

output:
$param = @{
    name = "test"
}
get-command @param

.NOTES
Created By Philip Meholm (Withholm)

Known issues:
No automatic conversion to string, even tho parameter would accept it.
It handles positional parameters exeptionally bad
it does not handle multiple commands in pipe (yet)
#>
function ConvertTo-Splat
{
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        $InputItem,
        [switch]$CompressObjectValues,
        [string]$SplatParamName,
        [ValidateRange(1,10)]
        [int]$TabSpaceCount = 4
        # [switch]$DontResolveCommand
    )
    begin
    {
        $Tab = " " * $tabSpaceCount
    }
    process
    {
        if ($InputItem -is [scriptblock])
        {
            $InputItem = $InputItem.tostring()
        }

        $code = $InputItem -join [System.Environment]::NewLine

        #check that code is actually correct
        $err = @()
        [void][System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$null, [ref]$err)
        $err | ForEach-Object {
            Write-warning $_
        }

        #Get tokens for the command
        $err = $null
        $tokens = [System.Management.Automation.PSParser]::Tokenize($code, [ref]$err)

        # analyze errors:
        if ($err.Count -gt 0)
        {
            # move the nested token up one level so we see all properties:
            $syntaxError = $errors | Select-Object -ExpandProperty Token -Property Message
            $syntaxError | ForEach-Object {
                Write-warning $_
            }
            throw "Error getting tokens for command. see warning above."
        }
        else
        {
            #Name of command
            $BeforeCommand = @()
            $command = ""
            $pscommand = $null

            #parameters to be outputed
            $params = [ordered]@{}

            #stack the gets filles if command have any grouping i need to take care of (commandgroup, array, objects.. etc)
            $GroupContents = @{}

            #Generate psuedo object to access last item in groupcontents stack. hate the $groupcontents[$groupcontents.count - 1] shit.. so this thing exists
            $Lastgroup = [pscustomobject]@{}
            $Lastgroup | Add-Member -Name 'exists' -MemberType ScriptProperty -Value { [bool]$GroupContents.Count }
            $Lastgroup | Add-Member -Name 'index' -MemberType ScriptProperty -Value { $GroupContents.count - 1 }
            $Lastgroup | Add-Member -Name 'type' -MemberType ScriptProperty -Value { $GroupContents[$Lastgroup.index].type }
            $Lastgroup | Add-Member -Name 'val' -MemberType ScriptProperty -Value { $GroupContents[$Lastgroup.index].val }

            # $Lastgroup.exists
            for ($i = 0; $i -lt $tokens.Count; $i++)
            {
                #set to true if you want to add the content to latest parameter
                $AddToParameter = $false
                $currtok = $tokens[$i]
                $Content = $currtok.Content
                if ($currtok.Type -eq "newline")
                {
                    Write-Verbose ("type:'{0}', content:'{1}'" -f $currtok.Type, '`n')
                }
                else
                {
                    Write-Verbose ("type:'{0}', content:'{1}'" -f $currtok.Type, $currtok.Content)
                }
                switch ($currtok.Type)
                {
                    "LineContinuation"
                    {
                        if ($Lastgroup.type -ne 'scriptblock')
                        {
                            continue
                        }
                        $AddToParameter = $true
                    }
                    "Newline"
                    {
                        if ($Lastgroup.type -ne 'scriptblock')
                        {
                            continue
                        }
                        $AddToParameter = $true
                    }
                    "Command"
                    {
                        #if no main command is registered
                        if ([string]::IsNullOrEmpty($command) -and $GroupContents.count -eq 0)
                        {
                            Write-verbose ("`tregistering as main command" -f $currtok.Type, $currtok.Content)
                            $command = $currtok.Content

                            #if splatparamname is not defined in arguments, use the command name
                            if ([string]::IsNullOrEmpty($SplataramName))
                            {
                                $SplatParamName = $command.Replace("-", "").ToLower() + "Param"
                            }

                            $pscommand = get-command $command -ErrorAction SilentlyContinue

                            if ($null -eq $pscommand)
                            {
                                Throw "Cannot find the command '$command' in current session"
                            }

                            $CommandParameters = $pscommand.Parameters
                        }
                        else
                        {
                            $AddToParameter = $true
                        }
                    }
                    "CommandParameter"
                    {
                        $thisParamName = $currtok.Content.substring(1).Replace(":", "")
                        $CommandParameter = $CommandParameters.($thisParamName)
                        if ($CommandParameter -and $GroupContents.count -eq 0)
                        {
                            Write-Verbose ("`tregistering new parameter" -f $thisParamName)
                            $params.$thisParamName = $null

                            #if param is switch and no override is defined
                            if ('SwitchParameter' -eq $CommandParameter.parametertype.name -and $currtok.Content -notlike "*:")
                            {
                                Write-Verbose "`tParameter is of type switch without override. adding $true"
                                $params.$thisParamName = '$true'
                            }
                        }
                        else
                        {
                            #ths parameter is part of a subcommand (ie -path (join-path "some" "path"))
                            $AddToParameter = $true
                        }
                    }
                    "type"
                    {
                        #if its a type casted object: [type]@{}
                        if ($tokens[$i + 1].content -eq '@{' )
                        {
                            Write-Verbose "Its a casted hashtable. handling it like groupStart"
                            $GroupContents.$($GroupContents.Count) = @{
                                type = $currtok.Content
                                val  = @()
                            }
                            $i++
                        }
                        else
                        {
                            $AddToParameter = $true
                        }
                    }
                    "GroupStart"
                    {
                        $NewIndex = $GroupContents.Count

                        #usually just on the start of a hashtable
                        if ($currtok.Content -eq '@{')
                        {
                            $GroupContents.$($NewIndex) = @{
                                type = "hashtable"
                                val  = @()
                            }
                        }
                        elseif ($currtok.Content -eq '(')
                        {
                            $GroupContents.$($NewIndex) = @{
                                type = "commandGroup"
                                val  = @()
                            }
                        }
                        elseif ($currtok.Content -eq "{")
                        {
                            $GroupContents.$($NewIndex) = @{
                                type = "scriptblock"
                                val  = @()
                            }
                        }
                        else
                        {
                            $AddToParameter = $true
                        }

                        #if groupcontents have a new member
                        if ($NewIndex -ne $GroupContents.Count)
                        {
                            Write-Verbose "`tRegistering new group at index $($Lastgroup.index)`: $($Lastgroup.type)"
                        }
                    }
                    "GroupEnd"
                    {
                        #End of a object
                        if ($currtok.Content -eq '}' -and $Lastgroup.type -eq 'scriptblock')
                        {
                            Write-Verbose "`tEnding scriptblock"
                            $content = @(
                                "{"
                            )
                            $ScriptblockContent = @()
                            $cache = @()

                            <# 
                                Adding together the different items in scriptblock

                            #>
                            for ($y = 0; $y -lt $Lastgroup.val.Count; $y++) {
                                if($Lastgroup.val[$y] -eq [System.Environment]::NewLine -and $cache.count -gt 0)
                                {
                                    $ScriptblockContent += "$tab$(($cache|Where-Object{$_}) -join " ")"
                                    $cache = @()
                                }
                                elseif($Lastgroup.val[$y] -ne [System.Environment]::NewLine){
                                    $cache += $Lastgroup.val[$y]
                                }
                            }

                            if($cache.count)
                            {
                                $Content += "$(($cache|Where-Object{$_}) -join " ")"
                            }
                            $Content += $ScriptblockContent
                            $Content += "}"

                            $AddToParameter = $true
                            $GroupContents.Remove($Lastgroup.index)
                        }
                        #end of scriptblock
                        elseif ($currtok.Content -eq "}" -and $Lastgroup.exists -and $Lastgroup.type -ne "scriptblock")
                        {

                            Write-Verbose "`tEnding object"
                            $TempContent = $GroupContents[$Lastgroup.index]
                            switch ($Lastgroup.type)
                            {
                                "hashtable"
                                {
                                    $prefix = ""
                                }
                                Default
                                {
                                    $prefix = "$($Lastgroup.type)"
                                }
                            }

                            # creates @{key="val";key2="val"} style object
                            if ($CompressObjectValues)
                            {
                                $ObjectItemsString = $Lastgroup.val -join '; '
                                $content = $prefix, "@{", $ObjectItemsString, "}" -join ""
                            }
                            #if object only have one property in it, it dont see why everything shouldn't be on the same line
                            elseif ($Lastgroup.val.count -eq 1)
                            {
                                $ObjectItemsString = $Lastgroup.val -join '; '
                                $content = $prefix, "@{", $ObjectItemsString, "}" -join ""
                            }
                            else
                            {
                                $tab = " " * $tabSpaceCount
                                $ObjectItems = $Lastgroup.val | ForEach-Object { "$tab$_" }
                                $content = @(
                                    "$prefix@{"
                                )
                                $ObjectItems | ForEach-Object {
                                    $Content += $_
                                }
                                $Content += "}"
                            }
                            $GroupContents.Remove($Lastgroup.index)
                        }
                        elseif ($currtok.content -eq ')' -and $Lastgroup.exists)
                        {
                            Write-Verbose "`tEnding commandgroup"

                            if ($Lastgroup.type -eq 'commandGroup')
                            {
                                Write-Verbose "$($Lastgroup.val.length),$($Lastgroup.val.gettype().name)"
                                $content = $Lastgroup.val
                                if($Content -is [array])
                                {
                                    $content[0] = "($($content[0])"
                                    $content[-1] = "$($content[-1]))"
                                }
                                else {
                                    $content = "($content)"
                                }
                            }
                            $GroupContents.Remove($Lastgroup.index)
                        }
                        $AddToParameter = $true
                    }
                    "string"
                    {
                        $Content = ( '"{0}"' -f $currtok.Content)
                        $AddToParameter = $true
                    }
                    "variable"
                    {
                        $content = ( '${0}' -f $currtok.Content)
                        $AddToParameter = $true
                    }
                    "StatementSeparator"
                    {
                        #Ignore separators if we are inside a group. the members and values inside the object would be handled other ways
                        if($Lastgroup.exists -and $Lastgroup.type -eq "scriptblock" -and $currtok.Content -eq ";")
                        {
                            Write-Verbose "Converting ';' to newline when inside scriptblock"
                            $content = [System.Environment]::NewLine
                            $AddToParameter = $true
                        }
                        if ($currtok.Content -eq ";" -and $GroupContents.Count)
                        {
                            continue
                        }
                    }
                    "Member"
                    {
                        Write-verbose "`tAdding member $($currtok.Content) to group $($Lastgroup.type) ($($Lastgroup.index))"
                        $GroupContents[$Lastgroup.index].val += $currtok.Content
                    }
                    Default
                    {
                        $AddToParameter = $true
                    }
                }

                #if token is defined as good to add to parameters hashtable
                if ($AddToParameter)
                {
                    #if a group exists in the groupstack (we are still inside a grouping)
                    if ($Lastgroup.exists)
                    {
                        Write-verbose "`tAdding data to group $($Lastgroup.type) ($($Lastgroup.index))"
                        if ('commandGroup', "scriptblock" -eq $Lastgroup.type)
                        {
                            $GroupContents[$Lastgroup.index].val += $Content
                        }
                        else
                        {
                            #hashtables and objects already have defined a 'member =', so it adds data to this line
                            $GroupContents[$Lastgroup.index].val[-1] += $Content
                        }
                    }
                    #if a command has been defined
                    elseif ([string]::IsNullOrEmpty($command) -eq $false)
                    {
                        #select latest parameter
                        $UsingParameter = $params.keys | Select-Object -Last 1

                        if (!$UsingParameter)
                        {
                            Write-Verbose "`tNo parameter defined. finding first positional parameter"
                            $PosAttr = $CommandParameters.values |
                            Select-Object name, @{
                                n = "position"
                                e = {
                                    ($_.Attributes | Where-Object { $_.TypeId.name -like "param*attr*" }).position
                                }
                            } | Where-Object { $_.position -ge 0 }
                            $UsingParameter = ($PosAttr | Sort-Object | Select-Object -First 1).name
                            if ([string]::IsNullOrEmpty($UsingParameter))
                            {
                                Throw "Cannot find a positional parameter for the first argument"
                            }
                            Write-Verbose "`tUsing positional parameter '$UsingParameter'"
                            # $CommandParameters.values|?{$_} |sort
                        }

                        Write-verbose "`tAdding data to '$UsingParameter'"
                        $Content | ForEach-Object {
                            Write-Verbose "`t`t$_"
                        }
                        if ($params.$UsingParameter -isnot [array] -and $Content -is [array])
                        {
                            $TempContent = @($params.$UsingParameter)
                            $Content | ForEach-Object {
                                $TempContent += $_
                            }
                            $Content = $TempContent
                            $params.$UsingParameter = $null
                        }
                        $params.$UsingParameter += $Content
                    }
                    #whatever goes here happens before a command
                    else
                    {
                        Write-verbose "`tAdding data to 'BeforeCommand'"
                        $BeforeCommand += $Content
                    }
                }
            }
        }
    }
    end
    {
        #get length of longest property name in order to allign the = in the resulting param
        $KeyPad = ($params.Keys.length | Sort-Object | Select-Object -Last 1)

        #setup tab length

        $ParamArr = @()
        Write-verbose "Creating parameter keyval string"
        foreach ($ParamLine in $params.GetEnumerator())
        {
            $Key = $ParamLine.Key.ToString().PadRight($KeyPad, " ")

            #remove empty lines
            $ParamLine.Value = ($ParamLine.Value | Where-Object { $_ })
            Write-verbose "parmeter key '$($ParamLine.key)' is of type $($ParamLine.Value.gettype().Name)"

            #join with newline and tab
            $Value = $ParamLine.Value -join "$([System.Environment]::NewLine)$tab"
            $ParamArr += "$Key = $Value"
        }
        $outarr = @()

        #if paramarr has items (ie if a command with parameters was sent in)
        if ($ParamArr.count)
        {
            $outarr = @(
                ("`$$($SplatParamName) = @{")
                (($ParamArr | ForEach-Object { "$tab$_" }) -join [System.Environment]::NewLine)
                '}'.trim()
                "$($BeforeCommand -join '')$command @$($SplatParamName)".Trim()
            )
        }
        else
        {
            $outarr = @("$command")
        }
        $outarr -join [System.Environment]::NewLine
    }
}