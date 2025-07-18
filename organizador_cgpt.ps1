# organizador_cgpt.ps1
# Script PowerShell completo para organizar ROMs com scraping (ScreenScraper),
# compactação, detecção de duplicatas e atualização de gamelist.xml
# Interface gráfica com Windows Forms e leitura via configurar.xml

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Variável global para metadados
$global:metadados = @{}
$global:formPrincipal = $null
$global:progressBar = $null
$global:lblStatus = $null

function Carregar-Config {
    try {
        [xml]$config = Get-Content "./cgpt_config/configurar.xml" -ErrorAction Stop
        return @{
            roms = $config.config.romsPath
            logs = $config.config.logsPath
            consoles = $config.config.consolesTxt
            aceitas = $config.config.pastasAceitasTxt
            sevenzip = $config.config.sevenZipPath
            scraper_user = $config.config.screenScraper.user
            scraper_pass = $config.config.screenScraper.password
            scraper_dev = $config.config.screenScraper.devId
            ignorarCompactacao = $config.config.ignorarCompactacao -split "," | ForEach-Object { $_.Trim() }
            pastasIgnorar = $config.config.pastasIgnorar -split "," | ForEach-Object { $_.Trim() }
        }
    } catch {
        Mostrar-Erro "Erro ao carregar configuração: $_"
        return $null
    }
}

function Mostrar-Erro {
    param($mensagem)
    [System.Windows.Forms.MessageBox]::Show($mensagem, "Erro", 'OK', 'Error')
    Write-Host "ERRO: $mensagem" -ForegroundColor Red
}

function Atualizar-Progresso {
    param($mensagem, $percentual = $null)
    
    if ($percentual -ne $null) {
        $global:progressBar.Value = [math]::Min($percentual, 100)
    }
    $global:lblStatus.Text = $mensagem
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-ConsolesMap {
    param($cfg)
    try {
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
    } catch {
        Mostrar-Erro "Erro ao mapear consoles: $_"
        return $null
    }
}

function Organizar-ROMs-Por-Console {
    param ($romsPath, $map)
    try {
        $arquivos = Get-ChildItem -Path $romsPath -Recurse -File
        $total = $arquivos.Count
        $processados = 0
        
        foreach ($arquivo in $arquivos) {
            $processados++
            $percentual = [math]::Round(($processados / $total) * 100)
            Atualizar-Progresso -mensagem "Organizando: $($arquivo.Name)" -percentual $percentual
            
            $ext = $arquivo.Extension.ToLower().TrimStart('.')
            if ($map.ContainsKey($ext)) {
                $destino = Join-Path $romsPath $map[$ext]
                if (!(Test-Path $destino)) { New-Item -ItemType Directory -Path $destino | Out-Null }
                $destinoCompleto = Join-Path $destino $arquivo.Name
                if (!(Test-Path $destinoCompleto)) {
                    Move-Item $arquivo.FullName -Destination $destinoCompleto
                }
            }
        }
        return $true
    } catch {
        Mostrar-Erro "Erro ao organizar ROMs: $_"
        return $false
    }
}

function Renomear-Pastas-Invalidas {
    param ($romsPath, $permitidasPath)
    try {
        $permitidas = Get-Content $permitidasPath | ForEach-Object { $_.Trim().ToLower() }
        $pastas = Get-ChildItem -Path $romsPath -Directory
        $total = $pastas.Count
        $processadas = 0
        
        foreach ($pasta in $pastas) {
            $processadas++
            $percentual = [math]::Round(($processadas / $total) * 100)
            Atualizar-Progresso -mensagem "Verificando pasta: $($pasta.Name)" -percentual $percentual
            
            if ($pasta.Name.ToLower() -notin $permitidas) {
                $novoNome = "# $($pasta.Name)"
                Rename-Item $pasta.FullName -NewName $novoNome
            }
        }
        return $true
    } catch {
        Mostrar-Erro "Erro ao renomear pastas: $_"
        return $false
    }
}

function Gerar-Log-Arquivos {
    param ($romsPath, $logPath)
    try {
        Atualizar-Progresso -mensagem "Gerando log de arquivos..."
        $logCompleto = Join-Path $logPath "todos_arquivos.txt"
        $saida = Get-ChildItem -Path $romsPath -Recurse | Select-Object FullName
        $saida.FullName | Out-File -Encoding UTF8 $logCompleto
        return $true
    } catch {
        Mostrar-Erro "Erro ao gerar log: $_"
        return $false
    }
}

function Detectar-Duplicatas {
    param ($romsPath, $logPath)
    
    try {
        Atualizar-Progresso -mensagem "Buscando duplicatas..." -percentual 0
        $hashTable = @{}
        $duplicatas = @{}
        $romsFolder = (Get-Item $romsPath).Name

        $arquivos = Get-ChildItem -Path $romsPath -Recurse -File
        $total = $arquivos.Count
        $processados = 0

        foreach ($arquivo in $arquivos) {
            $processados++
            $percentual = [math]::Round(($processados / $total) * 100)
            Atualizar-Progresso -mensagem "Verificando: $($arquivo.Name)" -percentual $percentual

            $hash = (Get-FileHash $arquivo.FullName -Algorithm MD5).Hash
            if ($hashTable.ContainsKey($hash)) {
                if (-not $duplicatas.ContainsKey($hash)) {
                    $duplicatas[$hash] = @($hashTable[$hash])
                }
                $duplicatas[$hash] += $arquivo.FullName
            } else {
                $hashTable[$hash] = $arquivo.FullName
            }
        }

        $logDuplicatas = Join-Path $logPath "duplicatas.txt"
        if ($duplicatas.Count -gt 0) {
            $duplicatas.GetEnumerator() | ForEach-Object {
                "GRUPO DE DUPLICATAS:`nORIGINAL: $($_.Value[0] -replace ".*\\$romsFolder\\", ".\")" | Out-File -Append -Encoding UTF8 $logDuplicatas
                for ($i = 1; $i -lt $_.Value.Count; $i++) {
                    "DUPLICATA ${i}: $($_.Value[$i] -replace ".*\\$romsFolder\\", ".\")" | Out-File -Append -Encoding UTF8 $logDuplicatas
                }
                "`n" | Out-File -Append -Encoding UTF8 $logDuplicatas
            }

            # Minimizar a janela principal
            if ($global:formPrincipal) {
                $global:formPrincipal.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
            }

            $formDuplicatas = New-Object System.Windows.Forms.Form
            $formDuplicatas.Text = "Duplicatas encontradas ($($duplicatas.Count) grupos)"
            $formDuplicatas.Size = New-Object System.Drawing.Size(800,500)
            $formDuplicatas.StartPosition = "CenterScreen"
            $formDuplicatas.Add_FormClosed({
                if ($global:formPrincipal) {
                    $global:formPrincipal.WindowState = [System.Windows.Forms.FormWindowState]::Normal
                }
            })

            $treeView = New-Object System.Windows.Forms.TreeView
            $treeView.Size = New-Object System.Drawing.Size(760,400)
            $treeView.Location = New-Object System.Drawing.Point(10,10)
            $treeView.CheckBoxes = $true

            foreach ($group in $duplicatas.GetEnumerator()) {
                $groupNode = New-Object System.Windows.Forms.TreeNode
                $groupNode.Text = "Duplicatas: $($group.Value.Count) itens"
                $groupNode.Tag = $group.Value
                
                # Adiciona o original (primeiro item)
                $originalNode = New-Object System.Windows.Forms.TreeNode
                $originalNode.Text = "(ORIGINAL) $($group.Value[0] -replace ".*\\$romsFolder\\", ".\")"
                $originalNode.Tag = $group.Value[0]
                $originalNode.ForeColor = [System.Drawing.Color]::Green
                $groupNode.Nodes.Add($originalNode) | Out-Null
                
                # Adiciona as duplicatas (itens restantes)
                for ($i = 1; $i -lt $group.Value.Count; $i++) {
                    $dupNode = New-Object System.Windows.Forms.TreeNode
                    $dupNode.Text = "$($group.Value[$i] -replace ".*\\$romsFolder\\", ".\")"
                    $dupNode.Tag = $group.Value[$i]
                    $groupNode.Nodes.Add($dupNode) | Out-Null
                }
                
                $treeView.Nodes.Add($groupNode) | Out-Null
            }

            $buttonExcluir = New-Object System.Windows.Forms.Button
            $buttonExcluir.Text = "Excluir selecionados"
            $buttonExcluir.Size = New-Object System.Drawing.Size(160,30)
            $buttonExcluir.Location = New-Object System.Drawing.Point(10,420)

            $buttonExcluir.Add_Click({
                $itemsToDelete = @()
                foreach ($node in $treeView.Nodes) {
                    foreach ($child in $node.Nodes) {
                        if ($child.Checked -and $child.Tag -ne $node.Tag[0]) {
                            $itemsToDelete += $child.Tag
                        }
                    }
                }
                
                if ($itemsToDelete.Count -gt 0) {
                    $confirm = [System.Windows.Forms.MessageBox]::Show(
                        "Deseja realmente excluir $($itemsToDelete.Count) arquivos duplicados?",
                        "Confirmação",
                        'YesNo',
                        'Question'
                    )
                    
                    if ($confirm -eq 'Yes') {
                        foreach ($item in $itemsToDelete) {
                            try {
                                Remove-Item $item -Force
                            } catch {
                                Mostrar-Erro "Erro ao excluir $item : $_"
                            }
                        }
                        $formDuplicatas.Close()
                    }
                } else {
                    [System.Windows.Forms.MessageBox]::Show("Nenhum item selecionado para exclusão.", "Aviso", 'OK', 'Information')
                }
            })

            $formDuplicatas.Controls.Add($treeView)
            $formDuplicatas.Controls.Add($buttonExcluir)
            $formDuplicatas.ShowDialog()
        } else {
            [System.Windows.Forms.MessageBox]::Show("Nenhuma duplicata encontrada.", "Informação", 'OK', 'Information')
        }
        
        return $true
    } catch {
        Mostrar-Erro "Erro ao detectar duplicatas: $_"
        return $false
    }
}

function Compactar-ROMs {
    param ($romsPath, $sevenZipPath, $ignorarCompactacao, $pastasIgnorar)
    try {
        $arquivos = Get-ChildItem -Path $romsPath -Recurse -File | Where-Object {
            $_.Extension -notin $ignorarCompactacao -and
            $_.Directory.Name -notin $pastasIgnorar -and
            $_.Name -ne "gamelist.xml"
        }
        
        $total = $arquivos.Count
        $processados = 0
        
        foreach ($arquivo in $arquivos) {
            $processados++
            $percentual = [math]::Round(($processados / $total) * 100)
            Atualizar-Progresso -mensagem "Compactando: $($arquivo.Name)" -percentual $percentual

            $arquivoOriginal = $arquivo.FullName
            $arquivoCompactado = "$($arquivoOriginal).7z"

            if (!(Test-Path $arquivoCompactado)) {
                & "$sevenZipPath" a -t7z -mx9 "$arquivoCompactado" "$arquivoOriginal" | Out-Null
                if (Test-Path $arquivoCompactado) {
                    Remove-Item $arquivoOriginal -Force
                }
            }
        }
        return $true
    } catch {
        Mostrar-Erro "Erro ao compactar ROMs: $_"
        return $false
    }
}

function Scrape-ScreenScraper {
    param($romName, $cfg)
    try {
        $url = "https://www.screenscraper.fr/api2/jeuInfos.php?devid=$($cfg.scraper_dev)&devpassword=$($cfg.scraper_pass)&softname=OrganizadorCGPT&output=xml&romnom=$([uri]::EscapeDataString($romName))&ssid=$($cfg.scraper_user)&sspassword=$($cfg.scraper_pass)"
        $res = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
        if ($res.StatusCode -eq 200) {
            $xml = [xml]$res.Content
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
        Write-Host "Erro no scraping de $romName : $_" -ForegroundColor Red
    }
    return $null
}

function Atualizar-GamelistXml {
    param(
        [string]$consolePath,
        [string]$romName,
        [string]$romPath,
        [hashtable]$metadados
    )
    try {
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
        return $true
    } catch {
        Mostrar-Erro "Erro ao atualizar gamelist.xml: $_"
        return $false
    }
}

function Salvar-Midia-SeFaltando {
    param($xml, $consolePath, $romBaseName)
    try {
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
    } catch {
        Mostrar-Erro "Erro ao salvar mídia para $romBaseName : $_"
        return $false
    }
}

# --- INTERFACE GRÁFICA ---
$global:formPrincipal = New-Object Windows.Forms.Form
$global:formPrincipal.Text = "Organizador CGPT"
$global:formPrincipal.Size = New-Object Drawing.Size(600,350)
$global:formPrincipal.StartPosition = "CenterScreen"
$global:formPrincipal.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$global:formPrincipal.MaximizeBox = $false

# Painel de botões
$panel = New-Object Windows.Forms.Panel
$panel.Location = New-Object Drawing.Point(10,10)
$panel.Size = New-Object Drawing.Size(565,150)
$panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

# Botão Organizar ROMs
$btnOrganizar = New-Object Windows.Forms.Button
$btnOrganizar.Text = "Organizar ROMs"
$btnOrganizar.Size = New-Object Drawing.Size(120,40)
$btnOrganizar.Location = New-Object Drawing.Point(20,20)
$btnOrganizar.Add_Click({
    $cfg = Carregar-Config
    if ($cfg) {
        $map = Get-ConsolesMap -cfg $cfg
        if ($map) {
            $success = Organizar-ROMs-Por-Console -romsPath $cfg.roms -map $map
            if ($success) {
                [System.Windows.Forms.MessageBox]::Show("ROMs organizadas por console!", "CGPT", 'OK', 'Information')
            }
        }
    }
    Atualizar-Progresso -mensagem "Pronto" -percentual 0
})

# Botão Renomear Pastas
$btnRenomear = New-Object Windows.Forms.Button
$btnRenomear.Text = "Renomear Pastas"
$btnRenomear.Size = New-Object Drawing.Size(120,40)
$btnRenomear.Location = New-Object Drawing.Point(150,20)
$btnRenomear.Add_Click({
    $cfg = Carregar-Config
    if ($cfg) {
        $success = Renomear-Pastas-Invalidas -romsPath $cfg.roms -permitidasPath $cfg.aceitas
        if ($success) {
            [System.Windows.Forms.MessageBox]::Show("Pastas inválidas renomeadas!", "CGPT", 'OK', 'Information')
        }
    }
    Atualizar-Progresso -mensagem "Pronto" -percentual 0
})

# Botão Ver Duplicatas
$btnDuplicatas = New-Object Windows.Forms.Button
$btnDuplicatas.Text = "Ver Duplicatas"
$btnDuplicatas.Size = New-Object Drawing.Size(120,40)
$btnDuplicatas.Location = New-Object Drawing.Point(280,20)
$btnDuplicatas.Add_Click({
    $cfg = Carregar-Config
    if ($cfg) {
        $success = Detectar-Duplicatas -romsPath $cfg.roms -logPath $cfg.logs
    }
    Atualizar-Progresso -mensagem "Pronto" -percentual 0
})

# Botão Compactar ROMs
$btnCompactar = New-Object Windows.Forms.Button
$btnCompactar.Text = "Compactar ROMs"
$btnCompactar.Size = New-Object Drawing.Size(120,40)
$btnCompactar.Location = New-Object Drawing.Point(410,20)
$btnCompactar.Add_Click({
    $cfg = Carregar-Config
    if ($cfg) {
        $success = Compactar-ROMs -romsPath $cfg.roms -sevenZipPath $cfg.sevenzip -ignorarCompactacao $cfg.ignorarCompactacao -pastasIgnorar $cfg.pastasIgnorar
        if ($success) {
            [System.Windows.Forms.MessageBox]::Show("ROMs compactadas!", "CGPT", 'OK', 'Information')
        }
    }
    Atualizar-Progresso -mensagem "Pronto" -percentual 0
})

# Botão Iniciar Scraping
$btnScraping = New-Object Windows.Forms.Button
$btnScraping.Text = "Iniciar Scraping"
$btnScraping.Size = New-Object Drawing.Size(240,40)
$btnScraping.Location = New-Object Drawing.Point(150,80)
$btnScraping.Add_Click({
    $cfg = Carregar-Config
    if ($cfg) {
        $map = Get-ConsolesMap -cfg $cfg
        if ($map) {
            $roms = Get-ChildItem -Recurse -Path $cfg.roms -Include *.zip,*.7z,*.iso,*.sfc,*.smc,*.gba,*.gbc,*.nes,*.md,*.sms -File | Where-Object { $_.Name -match "\(pt-br\)" }
            
            $total = $roms.Count
            $i = 0

            foreach ($rom in $roms) {
                $i++
                $romName = [System.IO.Path]::GetFileNameWithoutExtension($rom.Name)
                $percentual = [math]::Round(($i / $total) * 100)
                Atualizar-Progresso -mensagem "Processando: $romName" -percentual $percentual

                $ext = $rom.Extension.ToLower().TrimStart('.')
                if ($map.ContainsKey($ext)) {
                    $console = $map[$ext]
                    $consolePath = Join-Path $cfg.roms $console
                    $romRelPath = "$console/$($rom.Name)"

                    $imgPath = Join-Path $consolePath "images\$romName-image.png"
                    $vidPath = Join-Path $consolePath "videos\$romName-video.mp4"
                    $manPath = Join-Path $consolePath "manuals\$romName-manual.png"

                    if (!(Test-Path $imgPath) -or !(Test-Path $vidPath) -or !(Test-Path $manPath)) {
                        $xml = Scrape-ScreenScraper -romName $romName -cfg $cfg
                        if ($xml) {
                            $mediaOk = Salvar-Midia-SeFaltando -xml $xml -consolePath $consolePath -romBaseName $romName
                            if ($mediaOk) {
                                Atualizar-GamelistXml -consolePath $consolePath -romName $romName -romPath $romRelPath -metadados $global:metadados
                            }
                        }
                    }
                }
            }
            [System.Windows.Forms.MessageBox]::Show("Scraping e atualização do gamelist finalizados!", "CGPT", 'OK', 'Information')
        }
    }
    Atualizar-Progresso -mensagem "Pronto" -percentual 0
})

# Adiciona botões ao painel
$panel.Controls.Add($btnOrganizar)
$panel.Controls.Add($btnRenomear)
$panel.Controls.Add($btnDuplicatas)
$panel.Controls.Add($btnCompactar)
$panel.Controls.Add($btnScraping)

# Barra de progresso
$global:progressBar = New-Object Windows.Forms.ProgressBar
$global:progressBar.Minimum = 0
$global:progressBar.Maximum = 100
$global:progressBar.Value = 0
$global:progressBar.Size = New-Object Drawing.Size(565,25)
$global:progressBar.Location = New-Object Drawing.Point(10,180)
$global:progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous

# Label de status
$global:lblStatus = New-Object Windows.Forms.Label
$global:lblStatus.Text = "Pronto"
$global:lblStatus.Size = New-Object Drawing.Size(565,20)
$global:lblStatus.Location = New-Object Drawing.Point(10,210)
$global:lblStatus.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center

# Botão Sair
$btnSair = New-Object Windows.Forms.Button
$btnSair.Text = "Sair"
$btnSair.Size = New-Object Drawing.Size(120,40)
$btnSair.Location = New-Object Drawing.Point(230,250)
$btnSair.Add_Click({
    $global:formPrincipal.Close()
})

# Adiciona controles ao formulário
$global:formPrincipal.Controls.Add($panel)
$global:formPrincipal.Controls.Add($global:progressBar)
$global:formPrincipal.Controls.Add($global:lblStatus)
$global:formPrincipal.Controls.Add($btnSair)

# --- Exibir janela ---
$global:formPrincipal.Topmost = $true
$global:formPrincipal.Add_Shown({ $global:formPrincipal.Activate() })
[void]$global:formPrincipal.ShowDialog()