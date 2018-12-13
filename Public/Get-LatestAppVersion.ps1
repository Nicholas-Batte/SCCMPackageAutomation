function Get-LatestAppVersion {
<#
.SYNOPSIS

Gets the latest version of a given app.
.DESCRIPTION

Gets the latest version of an app by scraping a website. It gets the latest version by ether
checking a web api for latest version (chrome and firefox have this)
gets the latest version from a give ftp directory (vlc and others)
scrapes a web page with download links for the latest version (most apps require this)
.PARAMETER App

The app you want the latest version of. Dynamic tab completion from GlobalVariables Apps list.
.PARAMETER AsString
Returns the version # as a string. Useful for apps that a have leading zeros in version number.
.EXAMPLE
Get-LatestAppVersion -App Firefox
#>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true,
        HelpMessage = 'What standard app are you trying to get the version of?')]
        [string]
        [ValidateSet('7zip','BigFix','Chrome','CutePDF','Firefox','Flash','GIMP','Git','insync','Java','Notepad++','Putty','Reader','Receiver','VLC','VSCode','WinSCP','WireShark', IgnoreCase = $true)]
        $App,
        [switch]
        $AsString
    )
    # DynamicParam {
    #     #Example from https://mcpmag.com/articles/2016/10/06/implement-dynamic-parameters.aspx
    #     $ParamAttrib = New-Object System.Management.Automation.ParameterAttribute -Property @{
    #         Mandatory = $true
    #         Position = 0
    #         HelpMessage = "What App are you trying to get the version of"
    #     }
    #     $ParamAttrib.ParameterSetName  = '__AllParameterSets'

    #     $AttribColl = New-Object  System.Collections.ObjectModel.Collection[System.Attribute]
    #     $AttribColl.Add($ParamAttrib)
    #     $AttribColl.Add((New-Object  System.Management.Automation.ValidateSetAttribute($global:Apps)))

    #     $RuntimeParam = New-Object System.Management.Automation.RuntimeDefinedParameter('App',  [string], $AttribColl)

    #     $RuntimeParamDic = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
    #     $RuntimeParamDic.Add('App',  $RuntimeParam)

    #     return  $RuntimeParamDic
    # }

    begin {
        #$App = $PSBoundParameters['App']
        $App = $App.toLower()
    }

    process {
        #TLS
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        switch ($App) {
            '7zip' {
                # https://www.reddit.com/r/PowerShell/comments/9gwbed/scrape_7zip_website_for_the_latest_version/
                $Domain = "https://www.7-zip.org/download.html"
                $temp   = (Invoke-WebRequest -uri $Domain)
                $regex  = $temp.Content -match 'Download 7-Zip (.*)\s(.*) for Windows'

                if ($regex) {
                    $LatestAppVersion  = $Matches[1]
                }
                else {
                    throw "Error could not scrape 7-zip.org for version"
                }

            }
            'bigfix' {
                $url = "http://support.bigfix.com/bes/release/"
                $html = Invoke-WebRequest -Uri "$url"
                $versionLinks = $html.Links | Where-Object href -Match "\d+\.\d+\/patch\d+"
                #todo get "| Sort-Object -Descending" to work
                $latestURL = $url + $versionLinks[0].href
                $html = Invoke-WebRequest -Uri "$latestURL"
                $ClientDownload = $html.Links | Where-Object href -Match "Client.+\.exe"
                $LatestAppVersion = [regex]::match($ClientDownload.href,'\d+(\.\d+)+').Value
            }
            'chrome' {
                # https://stackoverflow.com/questions/35114642/get-latest-release-version-number-for-chrome-browser
                # https://omahaproxy.appspot.com/


                $LatestAppVersion = (Invoke-WebRequest -Uri "https://omahaproxy.appspot.com/all.json" | ConvertFrom-Json)[0].versions[-1].version
            }
            'cutepdf' {
                    #Scrubbing the page for version is difficult. It also gives an incomplete version.
                    # http://www.cutepdf.com/products/cutepdf/writer.asp

                    $download = Download-LatestAppVersion -App $App
                    $LatestAppVersion = $download.VersionInfo.ProductVersion
            }
            'firefox' {
                $LatestAppVersion = (Invoke-WebRequest -Uri "https://product-details.mozilla.org/1.0/firefox_versions.json" | ConvertFrom-Json).LATEST_FIREFOX_VERSION
            }
            'flash' {
                # https://github.com/auberginehill/update-adobe-flash-player/blob/master/Update-AdobeFlashPlayer.ps1

                $url = "https://fpdownload.macromedia.com/pub/flashplayer/masterversion/masterversion.xml"
                $xml_versions = New-Object XML
                $xml_versions.Load($url)

                # The different flash types can have different version numbers. I need to loop through
                # all of them to get be sure
                [version]$xml_activex_win10_current = ($xml_versions.version.release.ActiveX_win10.version).replace(",",".")
                [version]$xml_activex_edge_current = ($xml_versions.version.release.ActiveX_Edge.version).replace(",",".")
                [version]$xml_activex_win_current = ($xml_versions.version.release.ActiveX_win.version).replace(",",".")
                [version]$xml_plugin_win_current = ($xml_versions.version.release.NPAPI_win.version).replace(",",".")
                [version]$xml_ppapi_win_current = ($xml_versions.version.release.PPAPI_win.version).replace(",",".")

                $FlashVersions = $xml_activex_win10_current,$xml_activex_edge_current,$xml_activex_win_current,$xml_plugin_win_current,$xml_ppapi_win_current
                $FlashVersions = Sort-Object -InputObject $FlashVersions -Descending
                $LatestAppVersion = $FlashVersions[0]
            }
            'gimp'{
                $url = "https://download.gimp.org/mirror/pub/gimp/"
                $html = Invoke-WebRequest -Uri "$url"

                $GIMP_Versions = $html.Links | Where-Object innerHTML -Match "v\d+\.\d+\.*\d*/"
                $GIMP_Versions = Sort-Object -InputObject $GIMP_Versions -Property innerHTML

                $Gimp_MinorVersionsUrl = $url + "$($GIMP_Versions[-1].href)" + "windows/"
                $html2 = Invoke-WebRequest -Uri $Gimp_MinorVersionsUrl
                $Gimp_MinorVersions = $html2.Links | Where-Object innerHTML -Match "gimp-\d+\.\d+\.*\d*-setup.+exe"
                $Gimp_MinorVersions = Sort-Object -InputObject $Gimp_MinorVersions -Property innerHTML
                #gimp-(\d+\.*){3}-setup(-\d+)*\.exe[^.]

                if(($Gimp_MinorVersions[-1].innerHTML -split "." | Select-Object -Last 1) -eq "torrent"){
                    $LatestAppVersion = $Gimp_MinorVersions[-2].innerHTML -split "-" | Select-Object -First 2 | Select-Object -Last 1
                }
                else {
                    $LatestAppVersion = $Gimp_MinorVersions[-1].innerHTML -split "-" | Select-Object -First 2 | Select-Object -Last 1
                }
            }
            'git'{
                    $url = "https://git-scm.com/download/win"
                    $html = Invoke-WebRequest -Uri $url

                    $32bitDownload = ($html.links | Where-Object innerHTML -Match "32-bit Git for Windows Setup" | Select-Object -First 1).href
                    $LatestAppVersion = [regex]::match($32bitDownload,'\d+(\.\d+)+').Value
            }
            'java' {
                Write-Output "Java can't be automatically downloaded."
                $url = "https://java.com/en/download/manual.jsp"
                #todo?
            }
            'notepad++' {
                <#
                I am scrapping the domain for links like *Notepad++ Installer 64-bit.
                This solution will break if they change their link naming format. However there is on offical notepad++
                api to query.
                #>
                # URL to scan
                $SiteToScan = "https://notepad-plus-plus.org/download"
                $html = Invoke-WebRequest -uri $SiteToScan
                # Scan URL to download file
                $url64 = ($html.links | Where-Object innerHTML -like "*Notepad++ Installer 64-bit*").href
                $LatestAppVersion = $url64 -split "/" | Select-Object -Last 2 | Select-Object -first 1

            }
            'putty' {
                $SiteToScan = "https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html"
                $foundVersion = (Invoke-WebRequest -Uri $SiteToScan).Parsedhtml.title -match "\d+.\d+"

                if ($foundVersion){
                    $LatestAppVersion = $Matches[0]
                }
                else {
                    throw "Error $app version not found"
                }
            }
            'reader' {
                $url = "https://helpx.adobe.com/acrobat/release-note/release-notes-acrobat-reader.html"
                $html = Invoke-WebRequest -Uri "$url"

                $DC_Versions = $html.Links | Where-Object innerHTML -Match "\(\d+\.\d+\.\d+\)"

                foreach ($version in $DC_Versions){
                    $index = $version.innerHTML.indexOf("(")
                    $version.innerHTML = $version.innerHTML.substring($index)
                }

                $DC_Versions = $DC_Versions | Sort-Object -Descending -Property innerHTML
                $LatestAppVersion = $DC_Versions[0].innerHTML.Replace("(","").replace(")","")
            }
            'receiver' {
                $url = "https://www.citrix.com/downloads/citrix-receiver/"
                $html = Invoke-WebRequest -Uri "$url"
                $versionLinks = $html.Links | Where-Object innerHTML -Match "Receiver \d+(\.\d+)+.* for Windows$"

                $versionArray = @()
                foreach ($version in $versionLinks){
                    [version]$VersionNumber = $version.innerHTML -split " " | Select-Object -First 2 | Select-Object -Last 1
                    $versionArray += $VersionNumber
                }

                $versionArray = $versionArray | Sort-Object -Descending
                $LatestAppVersion = $versionArray[0]
            }
            'vlc' {
                $url = "http://download.videolan.org/pub/videolan/vlc/"
                $html = Invoke-WebRequest -Uri "$url"

                $versionlinks = $html.Links | Where-Object href -match "^(\d+\.)?(\d+\.)?(\*|\d+)\/$" | Sort-Object -Property href -Descending
                $LatestAppVersion = $versionlinks[0].href -replace "/",""

            }
            'vscode' {
                $url = "https://github.com/Microsoft/vscode/releases"
                $html = Invoke-WebRequest -Uri "$url" -UseBasicParsing
                $versionlinks = $html.Links | Where-Object href -match "\d+(\.\d+)+"
                $versionNumbers = @()
                foreach ($link in $versionlinks){
                    $versionNumbers += [regex]::match($link.href,'\d+(\.\d+)+').Value
                }
                $versionNumbers = $versionNumbers | Sort-Object -Descending
                $LatestAppVersion = $versionNumbers[0]
            }
            'winscp' {
                $url = "https://winscp.net/eng/downloads.php"
                $html = Invoke-WebRequest -Uri "$url" -UseBasicParsing
                $versionlinks = $html.Links -match ".+download\/WinSCP-\d+(\.\d+)+-Setup\.exe" | Sort-Object -Descending
                $LatestAppVersion = [regex]::match($versionlinks[0].href,'\d+(\.\d+)+').Value
            }
            'wireshark' {
                $url = "https://www.wireshark.org/download/win64/all-versions/"
                $html = Invoke-WebRequest -Uri "$url"

                $Versions = $html.Links | Where-Object innerHTML -Match "\d+\.\d+\.\d+\.msi"

                $versionArray = @()
                foreach ($version in $Versions){
                    $VersionNumber = $version.innerHTML -split "-" | Select-Object -Last 1
                    $VersionNumber = $VersionNumber -replace ".msi", ""
                    $versionArray += $VersionNumber
                }

                $versionArray = $versionArray | Sort-Object -Descending
                $LatestAppVersion = $versionArray[0]
            }
        }

        if (($app -eq "reader") -or ($AsString) ){
            return $LatestAppVersion
        }
        else {
            return [version]$LatestAppVersion
        }
    }

}