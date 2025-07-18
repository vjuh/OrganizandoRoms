# organizador_cgpt.ps1
# Script PowerShell completo para organizar ROMs com scraping (ScreenScraper),
# compactação, detecção de duplicatas e atualização de gamelist.xml
# Interface gráfica com Windows Forms e leitura via configurar.xml

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

function Carregar-Config {
    [xml]$config = Get-Content "./cgpt_config/configurar.xml"
    return @{
        roms = $config.config.romsPath
        logs = $config.config.logsPath
        consoles = $config.config.consolesTxt
        aceitas = $config.config.pastasAceitasTxt
        sevenzip = $config.config.sevenZipPath
        scraper_user = $config.config.screenScraper.user
        scraper_pass = $config.config.screenScraper.password
        scraper_dev = $config.config.screenScraper.devId
    }
}

function Get-ConsolesMap {
    $map = @{}
    Get-Content $cfg.consoles | ForEach-Object {
        if ($_ -match ":") {
            $p = $_ -split ":", 2
            $console = $p[0].Trim()
            $exts = $p[1].Split(",") | ForEach-Object { $_.Trim().ToLower() }
            foreach ($e in $exts) { $map[$e] = $console }
        }
    }
    return $map
}

function Organizar-ROMs-Por-Console {
    param ($romsPath, $map)
	  Get-ChildItem -Path $romsPath -Recurse -File | ForEach-Object {
        $ext = $_.Extension.ToLower().TrimStart('.')
        if ($map.ContainsKey($ext)) {
            $destino = Join-Path $romsPath $map[$ext]
            if (!(Test-Path $destino)) { New-Item -ItemType Directory -Path $destino | Out-Null }
            $destinoCompleto = Join-Path $destino $_.Name
            if (!(Test-Path $destinoCompleto)) {
                Move-Item $_.FullName -Destination $destinoCompleto
            }
        }
    }
}

function Renomear-Pastas-Invalidas {
    param ($romsPath, $permitidasPath)

    $permitidas = Get-Content $permitidasPath | ForEach-Object { $_.Trim().ToLower() }
    Get-ChildItem -Path $romsPath -Directory | ForEach-Object {
        if ($_.Name.ToLower() -notin $permitidas) {
            $novoNome = "# $($_.Name)"
            Rename-Item $_.FullName -NewName $novoNome
        }
    }
}

function Gerar-Log-Arquivos {
    param ($romsPath, $logPath)

    $logCompleto = Join-Path $logPath "todos_arquivos.txt"
    $saida = Get-ChildItem -Path $romsPath -Recurse | Select-Object FullName
    $saida.FullName | Out-File -Encoding UTF8 $logCompleto
}

function Detectar-Duplicatas {
    param ($romsPath, $logPath)

    $hashTable = @{}
    $duplicatas = @()

    Get-ChildItem -Path $romsPath -Recurse -File | ForEach-Object {
        $hash = (Get-FileHash $_.FullName -Algorithm MD5).Hash
        if ($hashTable.ContainsKey($hash)) {
            $duplicatas += [PSCustomObject]@{
                Original = $hashTable[$hash]
                Duplicata = $_.FullName
            }
        } else {
            $hashTable[$hash] = $_.FullName
        }
    }

    $logDuplicatas = Join-Path $logPath "duplicatas.txt"
    $duplicatas | ForEach-Object {
        "ORIGINAL: $($_.Original)`nDUPLICATA: $($_.Duplicata)`n" | Out-File -Append -Encoding UTF8 $logDuplicatas
    }

    if ($duplicatas.Count -gt 0) {
        [System.Windows.Forms.Application]::EnableVisualStyles()
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "Duplicatas encontradas"
        $form.Size = New-Object System.Drawing.Size(700,400)

        $listBox = New-Object System.Windows.Forms.ListBox
        $listBox.Size = New-Object System.Drawing.Size(660,280)
        $listBox.Location = New-Object System.Drawing.Point(10,10)
        $listBox.SelectionMode = 'MultiExtended'

        foreach ($d in $duplicatas) {
            $listBox.Items.Add($d.Duplicata)
        }

        $button = New-Object System.Windows.Forms.Button
        $button.Text = "Excluir selecionados"
        $button.Size = New-Object System.Drawing.Size(160,30)
        $button.Location = New-Object System.Drawing.Point(10,300)

        $button.Add_Click({
            foreach ($item in $listBox.SelectedItems) {
                Remove-Item $item -Force
            }
            $form.Close()
        })

        $form.Controls.Add($listBox)
        $form.Controls.Add($button)
        $form.ShowDialog()
    }
}

function Compactar-ROMs {
    param ($romsPath, $sevenZipPath)

    Get-ChildItem -Path $romsPath -Recurse -File | Where-Object {
        $_.Extension -notin '.zip', '.7z'
    } | ForEach-Object {
        $arquivoOriginal = $_.FullName
        $arquivoCompactado = "$($arquivoOriginal).7z"

        if (!(Test-Path $arquivoCompactado)) {
            & "$sevenZipPath" a -t7z -mx9 "$arquivoCompactado" "$arquivoOriginal" | Out-Null
            if (Test-Path $arquivoCompactado) {
                Remove-Item $arquivoOriginal -Force
            }
        }
    }
}

function Scrape-ScreenScraper {
    param($romName)

    $url = "https://www.screenscraper.fr/api2/jeuInfos.php?devid=$($cfg.scraper_dev)&devpassword=$($cfg.scraper_pass)&softname=OrganizadorCGPT&output=xml&romnom=$([uri]::EscapeDataString($romName))&ssid=$($cfg.scraper_user)&sspassword=$($cfg.scraper_pass)"
    try {
        $res = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
        if ($res.StatusCode -eq 200) {
            $xml = [xml]$res.Content
            # Anexar metadados extras para uso posterior no gamelist.xml
            $global:metadados = @{
                name = $xml.ssjeu.jeu.noms.nom[0].InnerText
                desc = $xml.ssjeu.jeu.synopsis
                genre = $xml.ssjeu.jeu.genres.genre[0]
                developer = $xml.ssjeu.jeu.developpeur
                publisher = $xml.ssjeu.jeu.editeur
                players = $xml.ssjeu.jeu.joueurs
                releasedate = $xml.ssjeu.jeu.dates.date[0]
                lang = $xml.ssjeu.jeu.languages.language[0]
            }
            return $xml
        }
    } catch {
        Write-Host "Erro no scraping de $romName" -ForegroundColor Red
    }
    return $null
}

function Atualizar-GamelistXml {
    param(
        [string]$consolePath,
        [string]$romName,
        [string]$romPath
    )

    $gamelistPath = Join-Path $consolePath "gamelist.xml"
    [xml]$gamelistXml = if (Test-Path $gamelistPath) {
        Get-Content $gamelistPath
    } else {
        [xml]"<gameList></gameList>"
    }

    $gameNode = $gamelistXml.CreateElement("game")

    $fields = @{
        path = "./$romPath"
        name = $metadados.name
        desc = $metadados.desc
        image = "./images/$romName-image.png"
        marquee = "./images/$romName-marquee.png"
        thumbnail = "./images/$romName-thumb.png"
        releasedate = $metadados.releasedate
        developer = $metadados.developer
        publisher = $metadados.publisher
        genre = $metadados.genre
        players = $metadados.players
        lang = $metadados.lang
        playcount = "0"
        lastplayed = ""
        gametime = "0"
    }

    foreach ($key in $fields.Keys) {
        $element = $gamelistXml.CreateElement($key)
        $element.InnerText = $fields[$key]
        $gameNode.AppendChild($element) | Out-Null
    }

    $scrapNode = $gamelistXml.CreateElement("scrap")
    $scrapNode.SetAttribute("name", "ScreenScraper")
    $scrapNode.SetAttribute("date", (Get-Date -Format "yyyyMMddTHHmmss"))
    $gameNode.AppendChild($scrapNode) | Out-Null

    $gamelistXml.gameList.AppendChild($gameNode) | Out-Null
    $gamelistXml.Save($gamelistPath)
}

function Salvar-Midia-SeFaltando {
    param($xml, $consolePath, $romBaseName)

    $pastaImagem = Join-Path $consolePath "images"
    $pastaVideo  = Join-Path $consolePath "videos"
    $pastaManual = Join-Path $consolePath "manuals"
    $ok = $false

    $img = $xml.ssjeu.jeu.medias.media | Where-Object { $_.type -eq "box-2D" } | Select-Object -First 1
    $vid = $xml.ssjeu.jeu.medias.media | Where-Object { $_.type -eq "video-normalized" } | Select-Object -First 1
    $man = $xml.ssjeu.jeu.medias.media | Where-Object { $_.type -eq "wheel" } | Select-Object -First 1

    if ($img.url) {
        $imgPath = Join-Path $pastaImagem "$romBaseName-image.png"
        if (!(Test-Path $imgPath)) {
            New-Item -ItemType Directory -Force -Path $pastaImagem | Out-Null
            Invoke-WebRequest -Uri $img.url -OutFile $imgPath -UseBasicParsing
            $ok = $true
        }
    }
    if ($vid.url) {
        $vidPath = Join-Path $pastaVideo "$romBaseName-video.mp4"
        if (!(Test-Path $vidPath)) {
            New-Item -ItemType Directory -Force -Path $pastaVideo | Out-Null
            Invoke-WebRequest -Uri $vid.url -OutFile $vidPath -UseBasicParsing
            $ok = $true
        }
    }
    if ($man.url) {
        $manPath = Join-Path $pastaManual "$romBaseName-manual.png"
        if (!(Test-Path $manPath)) {
            New-Item -ItemType Directory -Force -Path $pastaManual | Out-Null
            Invoke-WebRequest -Uri $man.url -OutFile $manPath -UseBasicParsing
            $ok = $true
        }
    }
    return $ok
}

function Atualizar-BarraProgresso {
    param($form, $progressBar, $current, $total)
    $percent = [math]::Round(($current / $total) * 100)
    $progressBar.Value = [math]::Min($percent, 100)
    $form.Text = "Organizador CGPT - $current de $total"
}

# --- EXECUÇÃO PRINCIPAL ---

Organizar-ROMs-Por-Console -romsPath $cfg.roms -map $map
Renomear-Pastas-Invalidas -romsPath $cfg.roms -permitidasPath $cfg.aceitas
Gerar-Log-Arquivos -romsPath $cfg.roms -logPath $cfg.logs
Detectar-Duplicatas -romsPath $cfg.roms -logPath $cfg.logs
Compactar-ROMs -romsPath $cfg.roms -sevenZipPath $cfg.sevenzip

    $cfg = Carregar-Config
    $map = Get-ConsolesMap
    $roms = Get-ChildItem -Recurse -Path $cfg.roms -Include *.zip,*.7z,*.iso,*.sfc,*.smc,*.gba,*.gbc,*.nes,*.md,*.sms -File | Where-Object { $_.Name -match "\(pt-br\)" }

    $total = $roms.Count
    $i = 0
$button.Add_Click({
    foreach ($rom in $roms) {
        $i++
        Atualizar-BarraProgresso -form $form -progressBar $progressBar -current $i -total $total

        $ext = $rom.Extension.ToLower().TrimStart('.')
        if ($map.ContainsKey($ext)) {
            $console = $map[$ext]
            $consolePath = Join-Path $cfg.roms $console
            $romName = [System.IO.Path]::GetFileNameWithoutExtension($rom)
            $romRelPath = "$console/$($rom.Name)"

            $imgPath = Join-Path $consolePath "images\$romName-image.png"
            $vidPath = Join-Path $consolePath "videos\$romName-video.mp4"
            $manPath = Join-Path $consolePath "manuals\$romName-manual.png"

            if (!(Test-Path $imgPath -and (Test-Path $vidPath) -and (Test-Path $manPath))) {
                $xml = Scrape-ScreenScraper $romName
                if ($xml) {
                    $mediaOk = Salvar-Midia-SeFaltando -xml $xml -consolePath $consolePath -romBaseName $romName
                    if ($mediaOk) {
                        Atualizar-GamelistXml -consolePath $consolePath -romName $romName -romPath $romRelPath
                    }
                }
            }
        }
    }
    [System.Windows.Forms.MessageBox]::Show("Scraping e atualização do gamelist finalizados!", "CGPT", 'OK', 'Information')
})


# --- INTERFACE GRÁFICA SIMPLES ---
$form = New-Object Windows.Forms.Form
$form.Text = "Organizador CGPT"
$form.Size = New-Object Drawing.Size(500,200)
$form.StartPosition = "CenterScreen"

$button = New-Object Windows.Forms.Button
$button.Text = "Iniciar Scraping"
$button.Size = New-Object Drawing.Size(150,40)
$button.Location = New-Object Drawing.Point(160,40)
$form.Controls.Add($button)

$progressBar = New-Object Windows.Forms.ProgressBar
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$progressBar.Size = New-Object Drawing.Size(460,25)
$progressBar.Location = New-Object Drawing.Point(10,110)
$form.Controls.Add($progressBar)

# --- LÓGICA DE EXECUÇÃO ---
$button.Add_Click({
    $cfg = Carregar-Config
    $map = Get-ConsolesMap
    $roms = Get-ChildItem -Recurse -Path $cfg.roms -Include *.zip,*.7z,*.iso,*.sfc,*.smc,*.gba,*.gbc,*.nes,*.md,*.sms -File | Where-Object { $_.Name -match "\(pt-br\)" }

    $total = $roms.Count
    $i = 0

    foreach ($rom in $roms) {
        $i++
        Atualizar-BarraProgresso -form $form -progressBar $progressBar -current $i -total $total

        $ext = $rom.Extension.ToLower()
        if ($map.ContainsKey($ext)) {
            $console = $map[$ext]
            $consolePath = Join-Path $cfg.roms $console
            $romName = [System.IO.Path]::GetFileNameWithoutExtension($rom)

            $imgPath = Join-Path $consolePath "images\$romName-image.png"
            $vidPath = Join-Path $consolePath "videos\$romName-video.mp4"
            $manPath = Join-Path $consolePath "manuals\$romName-manual.png"

            if (!(Test-Path $imgPath -and (Test-Path $vidPath) -and (Test-Path $manPath))) {
                $xml = Scrape-ScreenScraper $romName
                if ($xml) {
                    Salvar-Midia-SeFaltando -xml $xml -consolePath $consolePath -romBaseName $romName | Out-Null
                }
            }
        }
    }
    [System.Windows.Forms.MessageBox]::Show("Scraping finalizado!", "CGPT", 'OK', 'Information')
})

# --- Exibir janela ---
$form.Topmost = $true
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()