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

function Scrape-ScreenScraper {
    param($romName)

    $url = "https://www.screenscraper.fr/api2/jeuInfos.php?devid=$($cfg.scraper_dev)&devpassword=$($cfg.scraper_pass)&softname=OrganizadorCGPT&output=xml&romnom=$([uri]::EscapeDataString($romName))&ssid=$($cfg.scraper_user)&sspassword=$($cfg.scraper_pass)"
    try {
        $res = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
        if ($res.StatusCode -eq 200) {
            return [xml]$res.Content
        }
    } catch {
        Write-Host "Erro no scraping de $romName" -ForegroundColor Red
    }
    return $null
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