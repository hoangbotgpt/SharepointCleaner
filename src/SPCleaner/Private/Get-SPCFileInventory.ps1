function Get-SPCFileInventory {
    <#
    .SYNOPSIS
    Returns every file in the site's document libraries (cached per site for the session).
    Callers must not mutate the returned objects; use Copy-SPCObject before Add-Member.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [string[]]$Library,
        [switch]$IncludeSystemLibraries,
        [switch]$Refresh
    )
    Assert-SPCConnected
    $site = $SiteUrl.TrimEnd('/')
    $key = '{0}|{1}' -f $site.ToLowerInvariant(), [bool]$IncludeSystemLibraries
    if ($Refresh -or -not $script:SPCInventoryCache.ContainsKey($key)) {
        $script:SPCInventoryCache[$key] = @(Get-SPCFileInventoryCore -SiteUrl $site -IncludeSystemLibraries:$IncludeSystemLibraries)
    }
    $items = $script:SPCInventoryCache[$key]
    if ($Library) { $items = $items | Where-Object { $_.Library -in $Library } }
    $items
}

function Get-SPCFileInventoryCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [switch]$IncludeSystemLibraries
    )
    $conn = Get-SPCSiteConnection -SiteUrl $SiteUrl
    $fields = 'FileLeafRef', 'FileRef', 'File_x0020_Size', 'SMTotalSize', '_UIVersionString',
        'Modified', 'Editor', 'FSObjType', 'UniqueId', 'CheckoutUser', '_ComplianceTag'

    $lists = @(Get-PnPList -Includes RootFolder -Connection $conn -ErrorAction Stop |
            Where-Object { Test-SPCDocumentLibrary -List $_ -IncludeSystemLibraries:$IncludeSystemLibraries })

    $activity = "Quét file: $SiteUrl"
    $index = 0
    foreach ($list in $lists) {
        $index++
        $libraryUrl = Get-SPCPropertyValue -InputObject (Get-SPCPropertyValue -InputObject $list -Name 'RootFolder') -Name 'ServerRelativeUrl'
        $minorVersions = Get-SPCPropertyValue -InputObject $list -Name 'EnableMinorVersions'
        Write-Progress -Activity $activity -Status "$($list.Title) ($($list.ItemCount) mục)" -PercentComplete (100 * ($index - 1) / $lists.Count)
        try {
            Get-PnPListItem -List $list.Id -PageSize 2000 -Fields $fields -Connection $conn -ErrorAction Stop |
                Where-Object { "$($_.FieldValues['FSObjType'])" -eq '0' } |
                ForEach-Object {
                    ConvertTo-SPCFileRecord -Item $_ -SiteUrl $SiteUrl -LibraryTitle $list.Title -LibraryUrl $libraryUrl `
                        -MinorVersionsEnabled ($null -eq $minorVersions -or [bool]$minorVersions)
                }
        } catch {
            Write-SPCLog -Level Warning -Action ScanLibrary -SiteUrl $SiteUrl -Target $list.Title -Result Failed -Message $_.Exception.Message
        }
    }
    Write-Progress -Activity $activity -Completed
}

function Test-SPCDocumentLibrary {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]$List,
        [switch]$IncludeSystemLibraries
    )
    if ([int]$List.BaseTemplate -ne 101 -or [int]$List.ItemCount -eq 0) { return $false }
    $folder = Get-SPCPropertyValue -InputObject (Get-SPCPropertyValue -InputObject $List -Name 'RootFolder') -Name 'Name'
    if ($folder -in $script:SPCProtectedLibraryFolders -or $List.Title -eq 'Preservation Hold Library') { return $false }
    if ($IncludeSystemLibraries) { return $true }
    if ($List.Hidden) { return $false }
    $folder -notin $script:SPCSystemLibraryFolders
}

function ConvertTo-SPCFileRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)][string]$SiteUrl,
        [Parameter(Mandatory)][string]$LibraryTitle,
        [string]$LibraryUrl,
        [bool]$MinorVersionsEnabled = $true
    )
    $fv = $Item.FieldValues
    $size = ConvertTo-SPCInt64 $fv['File_x0020_Size']
    if ($null -eq $size) { $size = [int64]0 }
    $total = ConvertTo-SPCInt64 $fv['SMTotalSize']
    [pscustomobject]@{
        SiteUrl              = $SiteUrl
        Library              = $LibraryTitle
        LibraryUrl           = $LibraryUrl
        FileName             = [string]$fv['FileLeafRef']
        FileRef              = [string]$fv['FileRef']
        UniqueId             = $fv['UniqueId']
        ItemId               = $Item.Id
        SizeBytes            = $size
        SizeMB               = [math]::Round($size / 1MB, 2)
        TotalSizeBytes       = $total
        TotalSizeMB          = if ($null -ne $total) { [math]::Round($total / 1MB, 2) } else { $null }
        VersionLabel         = [string]$fv['_UIVersionString']
        MinorVersionsEnabled = $MinorVersionsEnabled
        Modified             = ConvertTo-SPCLocalTime $fv['Modified']
        ModifiedBy           = Get-SPCUserEmail $fv['Editor']
        CheckedOutTo         = Get-SPCUserEmail $fv['CheckoutUser']
        RetentionLabel       = [string]$fv['_ComplianceTag']
    }
}
