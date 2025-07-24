<#
.SYNOPSIS
    Organizador de ROMs Universal - Versão Final
.DESCRIPTION
    Script completo para organização, scraping e gerenciamento de ROMs
.NOTES
    Arquivo de configuração: nome_do_aplicativo.xml (na mesma pasta)
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework
#Add-Type -AssemblyName System.Security.Cryptography

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Variáveis globais
$global:metadados = @{}
$global:formPrincipal = $null
$global:progressBar = $null
$global:lblStatus = $null
$global:config = $null
$global:scrapersDisponiveis = @("ScreenScraper", "IGDB", "TheGamesDB", "MobyGames", "ArcadeDB")

# Função para carregar configurações
function Carregar-Config {
    try {
        # Método mais confiável para obter o caminho do script
        $scriptPath = if ($PSCommandPath) { $PSCommandPath } 
                      else { $MyInvocation.MyCommand.Path }
        
        if (-not $scriptPath) {
            $scriptPath = [System.IO.Directory]::GetCurrentDirectory() + "\" + $MyInvocation.MyCommand.Name
        }

        # Verifica se encontramos um caminho válido
        if ([string]::IsNullOrEmpty($scriptPath)) {
            throw "Não foi possível determinar o local do script"
        }

        # Obtém o diretório e nome do script
        $scriptDir = [System.IO.Path]::GetDirectoryName($scriptPath)
        $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($scriptPath)
        
        # Constrói o caminho do arquivo de configuração
        $configPath = Join-Path -Path $scriptDir -ChildPath "$scriptName.xml"

        Write-Host "Tentando carregar configuracao de: $configPath" -ForegroundColor Cyan

        if (-not (Test-Path -Path $configPath)) {
            throw "Arquivo de configuracao nao encontrado: $configPath"
        }

        [xml]$xmlConfig = Get-Content -Path $configPath -ErrorAction Stop
        Write-Host "Configuracao carregada com sucesso!" -ForegroundColor Green

        # Cria estrutura de configuração
        $config = @{
            # Configurações de interface
            Textos = @{
                TituloPrincipal = $xmlConfig.config.textos.tituloPrincipal
                BotaoOrganizar = $xmlConfig.config.textos.botaoOrganizar
                BotaoPastasProibidas = $xmlConfig.config.textos.botaoPastasProibidas
                BotaoDuplicatas = $xmlConfig.config.textos.botaoDuplicatas
                BotaoCompactar = $xmlConfig.config.textos.botaoCompactar
                BotaoDescompactar = $xmlConfig.config.textos.botaoDescompactar
                BotaoScraping = $xmlConfig.config.textos.botaoScraping
                BotaoSair = $xmlConfig.config.textos.botaoSair
                LabelRomsPath = $xmlConfig.config.textos.labelRomsPath
                LabelStatus = $xmlConfig.config.textos.labelStatus
            }
            # Configurações de caminhos
            Paths = @{
                RomsPath = $xmlConfig.config.paths.romsPath
                LogsPath = $xmlConfig.config.paths.logsPath
                SevenZipPath = $xmlConfig.config.paths.sevenZipPath
                #ImagesPath = $xmlConfig.config.paths.imagesPath
                #VideosPath = $xmlConfig.config.paths.videosPath
                #ManualsPath = $xmlConfig.config.paths.manualsPath
                #GameListPath = $xmlConfig.config.paths.gameListPath
            }
            
            # Configurações de scraping
            Scrapers = @{
                ScreenScraper = @{
                    User = $xmlConfig.config.scrapers.screenScraper.user
                    Password = $xmlConfig.config.scrapers.screenScraper.password
                    DevId = $xmlConfig.config.scrapers.screenScraper.devId
                }
                IGDB = @{
                    ApiKey = $xmlConfig.config.scrapers.igdb.apiKey
                }
                TheGamesDB = @{
                    ApiKey = $xmlConfig.config.scrapers.theGamesDB.apiKey
                }
            }
            
            # Configurações de extensões
            Extensoes = @{
                Roms = $xmlConfig.config.extensoes.roms -split "," | ForEach-Object { $_.Trim() }
                IgnorarCompactacao = $xmlConfig.config.extensoes.ignorarCompactacao -split "," | ForEach-Object { $_.Trim() }
                IgnorarDuplicatas = $xmlConfig.config.extensoes.ignorarDuplicatas -split "," | ForEach-Object { $_.Trim() }
                Compactadas = $xmlConfig.config.extensoes.compactadas -split "," | ForEach-Object { $_.Trim() }
                Consoles = @{}
                Media = $xmlConfig.config.extensoes.media -split "," | ForEach-Object { $_.Trim() }
            }
            
            # Configurações de pastas
            Pastas = @{
                Permitidas = $xmlConfig.config.pastas.permitidas -split "," | ForEach-Object { $_.Trim() }
                Ignorar = $xmlConfig.config.pastas.ignorar -split "," | ForEach-Object { $_.Trim() }
            }
        }

        # Carrega associações de extensões para consoles
        foreach ($consoleNode in $xmlConfig.config.extensoes.consoles.console) {
            $consoleName = $consoleNode.name
            $extensoesConsole = $consoleNode.extensoes -split "," | ForEach-Object { $_.Trim() }
            $config.Extensoes.Consoles[$consoleName] = $extensoesConsole
        }
        
        # Verifica diretórios essenciais
        if (-not (Test-Path -Path $config.Paths.RomsPath)) {
            New-Item -ItemType Directory -Path $config.Paths.RomsPath -Force | Out-Null
        }
        
        if (-not (Test-Path -Path $config.Paths.LogsPath)) {
            New-Item -ItemType Directory -Path $config.Paths.LogsPath -Force | Out-Null
        }
        
        return $config
    }
    catch {
        $errorMsg = "ERRO ao carregar configuracao:`n$($_.Exception.Message)`n`nDetalhes:`n$($_.ScriptStackTrace)"
        Write-Host $errorMsg -ForegroundColor Red
        [System.Windows.MessageBox]::Show($errorMsg, "Erro de Configuracao", 'OK', 'Error')
        return $null
    }
}

function Mostrar-Erro {
    param($mensagem)
    [System.Windows.MessageBox]::Show($mensagem, $global:config.Textos.TituloPrincipal, 'OK', 'Error')
    Write-Host "ERRO: $mensagem" -ForegroundColor Red
}

function Atualizar-Progresso {
    param($mensagem, $percentual = $null)
    
    if ($percentual -ne $null -and $global:progressBar -ne $null) {
        $global:progressBar.Value = [math]::Min($percentual, 100)
    }
    if ($global:lblStatus -ne $null) {
        $global:lblStatus.Text = $mensagem
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Gerar-Log {
    param(
        [string]$operacao,
        [array]$itens,
        [string]$tipoLog = "txt"
    )

    try {
        $dataHora = Get-Date -Format "yyyyMMdd_HHmmss"
        $nomeArquivo = "Log_${operacao}_${dataHora}.$tipoLog"
        $caminhoLog = Join-Path -Path $global:config.Paths.LogsPath -ChildPath $nomeArquivo

        if ($tipoLog -eq "csv") {
            $itens | Export-Csv -Path $caminhoLog -NoTypeInformation -Encoding UTF8
        } else {
            $itens | Out-File -FilePath $caminhoLog -Encoding UTF8
        }

        Write-Host "Log gerado em: $caminhoLog" -ForegroundColor Cyan
    }
    catch {
        Write-Host "Erro ao gerar log: $_" -ForegroundColor Red
    }
}

# Função para extrair a extensão do arquivo dentro de um arquivo compactado
function Get-ExtensaoInterna {
    param(
        [string]$arquivoCompactado,
        [string]$sevenZipPath
    )
    
    try {
        $argumentos = "l `"$arquivoCompactado`""
        $output = & $sevenZipPath $argumentos | Out-String
        
        # Analisa a saída para encontrar arquivos ROM
        $linhas = $output -split "`n"
        foreach ($linha in $linhas) {
            if ($linha -match "(\.[a-zA-Z0-9]+)\s*$") {
                $extensao = $matches[1].ToLower()
                if ($global:config.Extensoes.Roms -contains $extensao) {
                    return $extensao
                }
            }
        }
        
        return $null
    }
    catch {
        Write-Host "Erro ao analisar arquivo compactado $arquivoCompactado : $_" -ForegroundColor Yellow
        return $null
    }
}

# Função para organizar ROMs por console (incluindo verificação dentro de arquivos compactados)
function Organizar-ROMs-Por-Console {
    param($pastaRoms)

    try {
        Atualizar-Progresso -mensagem "Organizando ROMs por console..." -percentual 0

        # Verifica se a pasta existe
        if (-not (Test-Path -Path $pastaRoms)) {
            Mostrar-Erro -mensagem "Pasta de ROMs não encontrada: $pastaRoms"
            return
        }

        # Obtém todos os arquivos de ROM (apenas na pasta raiz, sem subpastas)
        $arquivos = Get-ChildItem -Path $pastaRoms -File | 
                    Where-Object { 
                        $global:config.Extensoes.Roms -contains $_.Extension.ToLower() -or
                        $global:config.Extensoes.Compactadas -contains $_.Extension.ToLower()
                    }

        $totalArquivos = $arquivos.Count
        $contador = 0
        $logItens = @()

        if ($totalArquivos -eq 0) {
            Atualizar-Progresso -mensagem "Nenhuma ROM encontrada para organizar!" -percentual 100
            Start-Sleep -Seconds 2
            return
        }

        foreach ($arquivo in $arquivos) {
            $contador++
            $porcentagem = [math]::Round(($contador / $totalArquivos) * 100)
            Atualizar-Progresso -mensagem "Processando ($contador/$totalArquivos): $($arquivo.Name)" -percentual $porcentagem

            $extensao = $arquivo.Extension.ToLower()
            $console = "Outros"
            
            # Se for arquivo compactado, verifica o conteúdo
            if ($global:config.Extensoes.Compactadas -contains $extensao) {
                $extensaoInterna = Get-ExtensaoInterna -arquivoCompactado $arquivo.FullName -sevenZipPath $global:config.Paths.SevenZipPath
                if ($extensaoInterna) {
                    $extensao = $extensaoInterna
                }
            }

            # Verifica a extensão para determinar o console
            foreach ($cons in $global:config.Extensoes.Consoles.GetEnumerator()) {
                if ($cons.Value -contains $extensao) {
                    $console = $cons.Key
                    break
                }
            }

            # Cria a pasta do console se não existir
            $pastaConsole = Join-Path -Path $pastaRoms -ChildPath $console
            if (-not (Test-Path -Path $pastaConsole)) {
                New-Item -ItemType Directory -Path $pastaConsole | Out-Null
            }

            # Move o arquivo para a pasta do console
            $caminhoDestino = Join-Path -Path $pastaConsole -ChildPath $arquivo.Name
            if (Test-Path -Path $caminhoDestino) {
                $logItens += "CONFLITO: $($arquivo.Name) -> Já existe em $console"
                continue
            }

            Move-Item -Path $arquivo.FullName -Destination $pastaConsole -Force -ErrorAction SilentlyContinue
            $logItens += "$($arquivo.Name) -> $console"
        }

        # Gera log da operação
        Gerar-Log -operacao "OrganizarROMs" -itens $logItens

        Atualizar-Progresso -mensagem "Organizacao concluida! $contador ROMs processadas." -percentual 100
        Start-Sleep -Seconds 2

    } catch {
        Mostrar-Erro -mensagem "Erro ao organizar ROMs: $_"
    }
}

# Função para calcular hash MD5 de um arquivo
function Get-FileHashMD5 {
    param($filePath)
    
    try {
        # Ignora arquivos muito pequenos (menos de 1KB)
        if ((Get-Item $filePath).Length -lt 1024) {
            return "smallfile_ignore"
        }
        
        $hashAlgorithm = [System.Security.Cryptography.MD5]::Create()
        $fileStream = [System.IO.File]::OpenRead($filePath)
        $hashBytes = $hashAlgorithm.ComputeHash($fileStream)
        $fileStream.Close()
        return [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
    }
    catch {
        Write-Host "Erro ao calcular hash do arquivo $filePath : $_" -ForegroundColor Red
        return $null
    }
}

function Verificar-Duplicatas {
    param($pastaRoms)

    try {
        # Primeiro verifica se a pasta existe
        if (-not (Test-Path -Path $pastaRoms)) {
            [System.Windows.Forms.MessageBox]::Show("Pasta de ROMs nao encontrada: $pastaRoms", "Erro", "OK", "Error")
            return
        }

        # Cria o formulário
        $formDuplicatas = New-Object System.Windows.Forms.Form
        $formDuplicatas.Text = "Verificacao de Duplicatas"
        $formDuplicatas.Size = New-Object System.Drawing.Size(800, 600)
        $formDuplicatas.StartPosition = "CenterScreen"
        $formDuplicatas.TopMost = $true

        $labelStatus = New-Object System.Windows.Forms.Label
        $labelStatus.Location = New-Object System.Drawing.Point(10, 10)
        $labelStatus.Size = New-Object System.Drawing.Size(760, 20)
        $labelStatus.Text = "Preparando para verificar duplicatas..."
        $formDuplicatas.Controls.Add($labelStatus)

        $progressBar = New-Object System.Windows.Forms.ProgressBar
        $progressBar.Location = New-Object System.Drawing.Point(10, 40)
        $progressBar.Size = New-Object System.Drawing.Size(760, 20)
        $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        $formDuplicatas.Controls.Add($progressBar)

        $listView = New-Object System.Windows.Forms.ListView
        $listView.Location = New-Object System.Drawing.Point(10, 70)
        $listView.Size = New-Object System.Drawing.Size(760, 450)
        $listView.View = [System.Windows.Forms.View]::Details
        $listView.FullRowSelect = $true
        $listView.MultiSelect = $true
        $listView.CheckBoxes = $true
        $listView.Columns.Add("Hash MD5", 150) | Out-Null
        $listView.Columns.Add("Arquivo", 350) | Out-Null
        $listView.Columns.Add("Tamanho", 100) | Out-Null
        $listView.Columns.Add("Data", 120) | Out-Null
        $formDuplicatas.Controls.Add($listView)

        # Botão para marcar/desmarcar todos
        $btnMarcarTodos = New-Object System.Windows.Forms.Button
        $btnMarcarTodos.Location = New-Object System.Drawing.Point(10, 530)
        $btnMarcarTodos.Size = New-Object System.Drawing.Size(120, 30)
        $btnMarcarTodos.Text = "Marcar Todos"
        $btnMarcarTodos.Add_Click({
            $marcar = ($btnMarcarTodos.Text -eq "Marcar Todos")
            foreach ($item in $listView.Items) {
                if ($item.Text -ne "") {
                    $item.Checked = $marcar
                }
            }
            $btnMarcarTodos.Text = if ($marcar) { "Desmarcar Todos" } else { "Marcar Todos" }
        })
        $formDuplicatas.Controls.Add($btnMarcarTodos)

        # Botão para marcar apenas duplicados
        $btnMarcarDuplicados = New-Object System.Windows.Forms.Button
        $btnMarcarDuplicados.Location = New-Object System.Drawing.Point(140, 530)
        $btnMarcarDuplicados.Size = New-Object System.Drawing.Size(150, 30)
        $btnMarcarDuplicados.Text = "Marcar Duplicados"
        $btnMarcarDuplicados.Add_Click({
            $hashesProcessados = @{}
            foreach ($item in $listView.Items) {
                if ($item.Text -ne "") {
                    if ($hashesProcessados.ContainsKey($item.Text)) {
                        $item.Checked = $true
                    } else {
                        $hashesProcessados[$item.Text] = $true
                        $item.Checked = $false
                    }
                }
            }
        })
        $formDuplicatas.Controls.Add($btnMarcarDuplicados)

        # Botão para excluir selecionados
        $btnExcluir = New-Object System.Windows.Forms.Button
        $btnExcluir.Location = New-Object System.Drawing.Point(300, 530)
        $btnExcluir.Size = New-Object System.Drawing.Size(120, 30)
        $btnExcluir.Text = "Excluir Selecionados"
        $btnExcluir.Enabled = $false
        $formDuplicatas.Controls.Add($btnExcluir)

        # Botão para fechar
        $btnFechar = New-Object System.Windows.Forms.Button
        $btnFechar.Location = New-Object System.Drawing.Point(650, 530)
        $btnFechar.Size = New-Object System.Drawing.Size(120, 30)
        $btnFechar.Text = "Fechar"
        $btnFechar.Add_Click({ $formDuplicatas.Close() }) # Removido Gerar-Log daqui (mantido no FormClosing)
        $formDuplicatas.Controls.Add($btnFechar)

        # Mostra o formulário antes do processamento para atualizar a interface
        $formDuplicatas.Add_Shown({
        # Obtém todos os arquivos de ROM
            $arquivos = Get-ChildItem -Path $pastaRoms -File -Recurse | 
                        Where-Object {
                            $global:config.Extensoes.Roms -contains $_.Extension.ToLower() -and
                            $global:config.Extensoes.IgnorarDuplicatas -notcontains $_.Extension.ToLower() -and
                            $_.Length -ge 1024
                        }

            $totalArquivos = $arquivos.Count
            $contador = 0
            $hashes = @{}
            $duplicatas = @{}
            $script:logItens = @()

            if ($totalArquivos -eq 0) {
                $labelStatus.Text = "Nenhum arquivo encontrado para verificar!"
                return
            }

        # Calcula hashes para todos os arquivos
            foreach ($arquivo in $arquivos) {
                $contador++
                $porcentagem = [math]::Round(($contador / $totalArquivos) * 100)
                $labelStatus.Text = "Calculando hash ($contador/$totalArquivos): $($arquivo.Name)"
                $progressBar.Value = $porcentagem
                [System.Windows.Forms.Application]::DoEvents()

                $hash = Get-FileHashMD5 -filePath $arquivo.FullName
                if ($hash -ne $null -and $hash -ne "smallfile_ignore") {
                    if (-not $hashes.ContainsKey($hash)) {
                        $hashes[$hash] = @()
                    }
                    $hashes[$hash] += $arquivo.FullName
                }
            }

        # Filtra apenas os que tem duplicatas
            $duplicatas = $hashes.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }

            if ($duplicatas.Count -eq 0) {
                $labelStatus.Text = "Nenhuma duplicata encontrada!"
                return
            }

        # Preenche a lista com as duplicatas
            foreach ($item in $duplicatas) {
                $hash = $item.Key
                $primeiro = $true

                foreach ($caminho in $item.Value) {
                    $arquivo = Get-Item -Path $caminho

                    # === CORREÇÃO: Caminho relativo calculado corretamente ===
                    $pastaBase = [System.IO.Path]::GetFullPath($pastaRoms).TrimEnd('\','/')
                    $caminhoAbsoluto = [System.IO.Path]::GetFullPath($caminho)
                    $caminhoRelativo = $caminhoAbsoluto.Substring($pastaBase.Length).TrimStart('\','/')

                    $listItem = New-Object System.Windows.Forms.ListViewItem($hash)
                    if (-not $primeiro) {
                        $listItem.Checked = $true
                    }
                    $listItem.SubItems.Add($caminhoRelativo) | Out-Null
                    $listItem.SubItems.Add("{0:N2} MB" -f ($arquivo.Length / 1MB)) | Out-Null
                    $listItem.SubItems.Add($arquivo.LastWriteTime.ToString("dd/MM/yyyy")) | Out-Null
                    $listItem.Tag = $caminhoAbsoluto
                    $listItem.ToolTipText = $caminhoAbsoluto  # Caminho completo no tooltip
                    $listView.Items.Add($listItem) | Out-Null

                    $script:logItens += "$hash | $caminhoRelativo | {0:N2} MB | $($arquivo.LastWriteTime)" -f ($arquivo.Length / 1MB)
                    $primeiro = $false
                }

            # Adiciona uma linha separadora
                $listView.Items.Add((New-Object System.Windows.Forms.ListViewItem(""))) | Out-Null
            }

            $labelStatus.Text = "Encontrados $($duplicatas.Count) conjuntos de arquivos duplicados!"
            $btnExcluir.Enabled = $true
        })

        # Configuração do botão Excluir
        $btnExcluir.Add_Click({
            # === NOVO: Exclusão direta (sem confirmação) ===
            $itensSelecionados = @($listView.CheckedItems | Where-Object { $_.Text -ne "" })
            foreach ($item in $itensSelecionados) {
                try {
                    Remove-Item -Path $item.Tag -Force -ErrorAction Stop
                    $script:logItens += "EXCLUIDO: $($item.Tag)"
                    $listView.Items.Remove($item)
                }
                catch {
                    $script:logItens += "ERRO: Falha ao excluir $($item.Tag) - $_"
                }
            }
        })

        # === NOVO: Clique duplo para abrir no Explorer ===
        $listView.Add_DoubleClick({
            if ($listView.SelectedItems.Count -gt 0) {
                $item = $listView.SelectedItems[0]
                $caminho = $item.Tag
                if ($caminho -and (Test-Path $caminho)) {
                    Start-Process explorer "/select,`"$caminho`""
                }
            }
        })

        # === NOVO: Tecla DELETE para exclusão direta ===
        $formDuplicatas.KeyPreview = $true
        $formDuplicatas.Add_KeyDown({
            if ($_.KeyCode -eq 'Delete') {
                $itensSelecionados = @($listView.SelectedItems | Where-Object { $_.Text -ne "" })
                foreach ($item in $itensSelecionados) {
                    try {
                        Remove-Item -Path $item.Tag -Force -ErrorAction Stop
                        $script:logItens += "EXCLUIDO (DEL): $($item.Tag)"
                        $listView.Items.Remove($item)
                    }
                    catch {
                        $script:logItens += "ERRO: Falha ao excluir $($item.Tag) - $_"
                    }
                }
            }
        })

        # === CORREÇÃO: Log gerado uma única vez no fechamento ===
        $formDuplicatas.Add_FormClosing({
            if ($script:logItens.Count -gt 0) {
                Gerar-Log -operacao "Duplicatas" -itens $script:logItens
            }
        })

        $formDuplicatas.ShowDialog() | Out-Null

    } catch {
        [System.Windows.Forms.MessageBox]::Show("Ocorreu um erro: $_", "Erro", "OK", "Error")
        $formDuplicatas.Close()
    }
}


function Compactar-ROMs {
    param(
        [Parameter(Mandatory=$true)]
        [string]$pastaSelecionada
    )

    try {
        $formProgresso = New-Object System.Windows.Forms.Form
        $formProgresso.Text = $global:config.Textos.BotaoCompactar
        $formProgresso.Size = New-Object System.Drawing.Size(450, 150)
        $formProgresso.StartPosition = "CenterScreen"
        $formProgresso.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $formProgresso.MaximizeBox = $false

        $labelStatus = New-Object System.Windows.Forms.Label
        $labelStatus.Location = New-Object System.Drawing.Point(10, 20)
        $labelStatus.Size = New-Object System.Drawing.Size(420, 20)
        $labelStatus.Text = "Preparando para compactar..."
        $formProgresso.Controls.Add($labelStatus)

        $progressBar = New-Object System.Windows.Forms.ProgressBar
        $progressBar.Location = New-Object System.Drawing.Point(10, 50)
        $progressBar.Size = New-Object System.Drawing.Size(420, 20)
        $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        $formProgresso.Controls.Add($progressBar)

        $labelDetails = New-Object System.Windows.Forms.Label
        $labelDetails.Location = New-Object System.Drawing.Point(10, 80)
        $labelDetails.Size = New-Object System.Drawing.Size(420, 20)
        $labelDetails.Text = ""
        $formProgresso.Controls.Add($labelDetails)

        $formProgresso.Show()
        [System.Windows.Forms.Application]::DoEvents()

        # Verifica se o 7-Zip está instalado
        if (-not (Test-Path $global:config.Paths.SevenZipPath)) {
            $labelStatus.Text = "7-Zip nao encontrado!"
            $labelDetails.Text = "Caminho: $($global:config.Paths.SevenZipPath)"
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Seconds 3
            $formProgresso.Close()
            Mostrar-Erro -mensagem "7-Zip nao encontrado em $($global:config.Paths.SevenZipPath)`nPor favor, instale o 7-Zip primeiro."
            return
        }

        # Valida diretório de origem
        if (-not (Test-Path -Path $pastaSelecionada -PathType Container)) {
            $labelStatus.Text = "Diretório inválido!"
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Seconds 2
            $formProgresso.Close()
            Mostrar-Erro -mensagem "O diretorio especificado nao existe: $pastaSelecionada"
            return
        }

        # Lista para armazenar itens que já foram processados (para evitar duplicação)
        $itensProcessados = @()
        $logItens = @()
        $erros = 0

        # Primeiro processa as pastas (compacta cada pasta inteira)
        $pastasParaCompactar = Get-ChildItem -Path $pastaSelecionada -Directory | 
            Where-Object {
                # Verifica se a pasta não está na lista de ignorar
                $_.Name -notin $global:config.Pastas.Ignorar
            }

        # Depois processa os arquivos (apenas os que não estão em subpastas)
        $arquivosParaCompactar = Get-ChildItem -Path $pastaSelecionada -File | 
            Where-Object {
                # Verifica se a extensão não está na lista de ignorar
                $_.Extension -notin $global:config.Extensoes.IgnorarCompactacao
            }

        $totalItens = $pastasParaCompactar.Count + $arquivosParaCompactar.Count
        $contador = 0

        if ($totalItens -eq 0) {
            $labelStatus.Text = "Nenhum item encontrado para compactar!"
            $labelDetails.Text = "Verifique as configuracoes de pastas/extensoes ignoradas"
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Seconds 3
            $formProgresso.Close()
            return
        }

        # Processa pastas primeiro
        foreach ($pasta in $pastasParaCompactar) {
            $contador++
            $porcentagem = [math]::Round(($contador / $totalItens) * 100)
            $labelStatus.Text = "Compactando pasta ($contador/$totalItens)"
            $labelDetails.Text = $pasta.Name
            $progressBar.Value = $porcentagem
            [System.Windows.Forms.Application]::DoEvents()

            $nomeCompactado = "$($pasta.Name).7z"
            $caminhoCompactado = Join-Path -Path $pasta.Parent.FullName -ChildPath $nomeCompactado

            $argumentos = "a -t7z `"$caminhoCompactado`" `"$($pasta.FullName)`" -mx=9"
            $processo = Start-Process -FilePath $global:config.Paths.SevenZipPath -ArgumentList $argumentos -Wait -NoNewWindow -PassThru

            if ($processo.ExitCode -eq 0) {
                Remove-Item $pasta.FullName -Recurse -Force -ErrorAction SilentlyContinue
                $logItens += "SUCESSO (PASTA): $($pasta.FullName) -> $caminhoCompactado"
                $itensProcessados += $pasta.FullName
            } else {
                $erros++
                $logItens += "ERRO: Falha ao compactar pasta $($pasta.FullName)"
            }
        }

        # Processa arquivos individuais depois
        foreach ($arquivo in $arquivosParaCompactar) {
            $contador++
            $porcentagem = [math]::Round(($contador / $totalItens) * 100)
            $labelStatus.Text = "Compactando arquivo ($contador/$totalItens)"
            $labelDetails.Text = $arquivo.Name
            $progressBar.Value = $porcentagem
            [System.Windows.Forms.Application]::DoEvents()

            $nomeCompactado = "$($arquivo.BaseName).7z"
            $caminhoCompactado = Join-Path -Path $arquivo.DirectoryName -ChildPath $nomeCompactado

            $argumentos = "a -t7z `"$caminhoCompactado`" `"$($arquivo.FullName)`" -mx=9"
            $processo = Start-Process -FilePath $global:config.Paths.SevenZipPath -ArgumentList $argumentos -Wait -NoNewWindow -PassThru

            if ($processo.ExitCode -eq 0) {
                Remove-Item $arquivo.FullName -Force -ErrorAction SilentlyContinue
                $logItens += "SUCESSO: $($arquivo.FullName) -> $caminhoCompactado"
                $itensProcessados += $arquivo.FullName
            } else {
                $erros++
                $logItens += "ERRO: Falha ao compactar $($arquivo.FullName)"
            }
        }

        # Gera log da operação
        Gerar-Log -operacao "CompactarROMs" -itens $logItens

        $labelStatus.Text = "Compactacao concluida! $contador itens processados."
        $labelDetails.Text = "$erros erro(s) encontrado(s)"
        $progressBar.Value = 100
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Seconds 3
        $formProgresso.Close()

    } catch {
        if ($labelStatus -ne $null) {
            $labelStatus.Text = "Ocorreu um erro: $_"
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Seconds 3
        if ($formProgresso -ne $null) {
            $formProgresso.Close()
        }
        Mostrar-Erro -mensagem "Erro ao compactar: $_"
    }
}
# Função para realizar scraping completo (mídias e metadados)
function Iniciar-Scraping {
    try {
        $fontesDisponiveis = $global:scrapersDisponiveis | Where-Object {
            switch ($_)
            {
                "ScreenScraper" { return -not [string]::IsNullOrWhiteSpace($global:config.Scrapers.ScreenScraper.User) }
                "IGDB"          { return -not [string]::IsNullOrWhiteSpace($global:config.Scrapers.IGDB.ApiKey) }
                "TheGamesDB"    { return -not [string]::IsNullOrWhiteSpace($global:config.Scrapers.TheGamesDB.ApiKey) }
                "MobyGames"     { return $true } # Placeholder para futura integração
                "ArcadeDB"      { return $true } # Placeholder para futura integração
                default         { return $false }
            }
        }

        if ($fontesDisponiveis.Count -eq 0) {
            Mostrar-Erro "Nenhuma fonte de scraping configurada corretamente."
            return
        }

        $formFonte = New-Object System.Windows.Forms.Form
        $formFonte.Text = "Selecionar Fonte de Scraping"
        $formFonte.Size = New-Object System.Drawing.Size(300,200)
        $formFonte.StartPosition = "CenterScreen"

        $comboFontes = New-Object System.Windows.Forms.ComboBox
        $comboFontes.Location = New-Object System.Drawing.Point(20,30)
        $comboFontes.Size = New-Object System.Drawing.Size(240,30)
        $comboFontes.DropDownStyle = 'DropDownList'
        $comboFontes.Items.AddRange($fontesDisponiveis)
        $comboFontes.SelectedIndex = 0
        $formFonte.Controls.Add($comboFontes)

        $btnOK = New-Object System.Windows.Forms.Button
        $btnOK.Text = "Iniciar"
        $btnOK.Location = New-Object System.Drawing.Point(90,80)
        $btnOK.Add_Click({
            $formFonte.Tag = $comboFontes.SelectedItem
            $formFonte.Close()
        })
        $formFonte.Controls.Add($btnOK)

        $formFonte.ShowDialog() | Out-Null

        $fonteSelecionada = $formFonte.Tag
        if (-not $fonteSelecionada) {
            return
        }

        Atualizar-Progresso "Preparando scraping com $fonteSelecionada..."

        $pastasConsoles = Get-ChildItem -Path $global:config.Paths.RomsPath -Directory | Where-Object {
            $global:config.Pastas.Permitidas -contains $_.Name
        }

        foreach ($pastaConsole in $pastasConsoles) {
            $roms = Get-ChildItem -Path $pastaConsole.FullName -Recurse -File |
                Where-Object { $global:config.Extensoes.Roms -contains $_.Extension.ToLower() }

            $total = $roms.Count
            $atual = 0

            foreach ($rom in $roms) {
                $atual++
                $percentual = [math]::Round(($atual / $total) * 100, 0)
                Atualizar-Progresso "Buscando dados para: $($rom.Name) [$atual/$total]" $percentual

                $midiaPath = Join-Path $rom.Directory.FullName "images"
                $videoPath = Join-Path $rom.Directory.FullName "videos"
                $manualPath = Join-Path $rom.Directory.FullName "manuals"
                $gamelistPath = Join-Path $rom.Directory.FullName "gamelist.xml"

                if (-not (Test-Path $midiaPath)) { New-Item -ItemType Directory -Path $midiaPath -Force | Out-Null }
                if (-not (Test-Path $videoPath)) { New-Item -ItemType Directory -Path $videoPath -Force | Out-Null }
                if (-not (Test-Path $manualPath)) { New-Item -ItemType Directory -Path $manualPath -Force | Out-Null }

                switch ($fonteSelecionada) {
                    "ScreenScraper" {
                        # TODO: Integrar scraping real com ScreenScraper
                        # Exemplo: Obter dados, baixar imagem/video/manual
                        $user = $global:config.Scrapers.ScreenScraper.User
                        $pass = $global:config.Scrapers.ScreenScraper.Password

                        $params = @{ 
                            romfilename = $rom.Name
                            system = $pastaConsole.Name
                            software = 'true'
                            md5 = (Get-FileHash -Path $rom.FullName -Algorithm MD5).Hash.ToLower()
                            langue = 'pt' 
                            output = 'json'
                            devlogin = $user
                            devpassword = $pass
                        }

                        $query = ($params.GetEnumerator() | ForEach-Object { "{0}={1}" -f $_.Key, [uri]::EscapeDataString($_.Value) }) -join "&"
                        $url = "https://www.screenscraper.fr/api2/jeuInfos.php?$query"

                        try {
                            $resposta = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop

                            if ($resposta -and $resposta.response -and $resposta.response.jeu) {
                                $jogo = $resposta.response.jeu

                                if (-not $imagemExistente -and $jogo.medias.screenshot) {
                                    if (-not (Test-Path $midiaPath)) { New-Item -ItemType Directory -Path $midiaPath -Force | Out-Null }
                                    $imgURL = $jogo.medias.screenshot.url
                                    Invoke-WebRequest -Uri $imgURL -OutFile (Join-Path $midiaPath "$($rom.BaseName).jpg")
                                }
                                if (-not $videoExistente -and $jogo.medias.video_normalized) {
                                    if (-not (Test-Path $videoPath)) { New-Item -ItemType Directory -Path $videoPath -Force | Out-Null }
                                    $videoURL = $jogo.medias.video_normalized.url
                                    Invoke-WebRequest -Uri $videoURL -OutFile (Join-Path $videoPath "$($rom.BaseName).mp4")
                                }
                                if (-not $manualExistente -and $jogo.medias.manual) {
                                    if (-not (Test-Path $manualPath)) { New-Item -ItemType Directory -Path $manualPath -Force | Out-Null }
                                    $manualURL = $jogo.medias.manual.url
                                    Invoke-WebRequest -Uri $manualURL -OutFile (Join-Path $manualPath "$($rom.BaseName).pdf")
                                }

                                # Atualizar ou criar gamelist.xml
                                Atualizar-Gamelist -GamelistPath $gamelistPath -Rom $rom -Jogo $jogo -Console $pastaConsole.Name
                            }
                        }
                        catch {
                            Mostrar-Erro "Erro ao consultar ScreenScraper para $($rom.Name): $_"
                        }
                    }
                    "IGDB" {
                        # TODO: Integrar scraping com IGDB
							$clientId = $global:config.Scrapers.IGDB.clientId
							$clientSecret = $global:config.Scrapers.IGDB.clientSecret
							$token = Obter-TokenIGDB -ClientId $clientId -ClientSecret $clientSecret

							if (-not $token) { continue }

							$jogo = Obter-Dados-IGDB -JogoNome $rom.BaseName -ClientId $clientId -Token $token
							if (-not $jogo) { continue }

							$imagem = $null
							if ($jogo.cover.url) {
								$imgURL = "https:" + $jogo.cover.url.Replace("t_thumb", "t_720p")
								$imagem = Join-Path $midiaPath "$($rom.BaseName).jpg"
								Invoke-WebRequest -Uri $imgURL -OutFile $imagem -ErrorAction SilentlyContinue
							}

							$video = $null
							if ($jogo.videos -and $jogo.videos[0].video_id) {
								$videoURL = "https://youtube.com/watch?v=$($jogo.videos[0].video_id)"
								$video = Join-Path $videoPath "$($rom.BaseName).url"
								"[InternetShortcut]`nURL=$videoURL" | Set-Content $video
							}

							Atualizar-Gamelist -GamelistPath $gamelistPath -Rom $rom -Jogo @{ nom = $jogo.name; synopsis = $jogo.summary } -Console $pastaConsole.Name
                    }
                    "TheGamesDB" {
                        # TODO: Integrar scraping com TheGamesDB
						$apiKey = $global:config.Scrapers.TheGamesDB.apiKey
						$jogo, $include = Obter-Dados-TheGamesDB -ApiKey $apiKey -JogoNome $rom.BaseName
						if (-not $jogo) { continue }

						$imagem = $null
						if ($jogo.boxart) {
							$baseImg = $include.boxart.base_url.original
							$imgPath = $baseImg + $jogo.boxart.front
							$imagem = Join-Path $midiaPath "$($rom.BaseName).jpg"
							Invoke-WebRequest -Uri $imgPath -OutFile $imagem -ErrorAction SilentlyContinue
						}

						Atualizar-Gamelist -GamelistPath $gamelistPath -Rom $rom -Jogo @{ nom = $jogo.game_title; synopsis = $jogo.overview } -Console $pastaConsole.Name
                    }
                    "MobyGames" {
                        # TODO: Placeholder para integração
						$apiKey = $global:config.Scrapers.MobyGames.apiKey
						$jogo = Obter-Dados-MobyGames -ApiKey $apiKey -JogoNome $rom.BaseName
						if (-not $jogo) { continue }

						$imagem = $null
						if ($jogo.sample_cover -and $jogo.sample_cover.image) {
							$imgURL = $jogo.sample_cover.image
							$imagem = Join-Path $midiaPath "$($rom.BaseName).jpg"
							Invoke-WebRequest -Uri $imgURL -OutFile $imagem -ErrorAction SilentlyContinue
						}

						$descricao = if ($jogo.description) { $jogo.description } else { "" }

						Atualizar-Gamelist -GamelistPath $gamelistPath -Rom $rom -Jogo @{ nom = $jogo.title; synopsis = $descricao } -Console $pastaConsole.Name
                    }
                }

                # TODO: Criar ou atualizar gamelist.xml com os dados obtidos
function Atualizar-Gamelist {
    param(
        [string]$GamelistPath,
        [System.IO.FileInfo]$Rom,
        $Jogo,
        [string]$Console
    )

    [xml]$xml = if (Test-Path $GamelistPath) {
        Get-Content $GamelistPath -Raw
    } else {
        $doc = New-Object System.Xml.XmlDocument
        $decl = $doc.CreateXmlDeclaration("1.0", "UTF-8", $null)
        $doc.AppendChild($decl) | Out-Null
        $root = $doc.CreateElement("gameList")
        $doc.AppendChild($root) | Out-Null
        $doc
    }

if ($xml -eq $null) {
    $xml = New-Object System.Xml.XmlDocument
    $root = $xml.CreateElement("gameList")
    $xml.AppendChild($root) | Out-Null
} else {
    $root = $xml.SelectSingleNode("//gameList")
}

    $romPath = "./$($Rom.Name)"
    $nome = $Jogo.nom -replace '"', ''

    $nodeExistente = $root.game | Where-Object { $_.path -eq $romPath }
    if ($nodeExistente) {
        $root.RemoveChild($nodeExistente) | Out-Null
    }

    $novoNode = $xml.CreateElement("game")

    $pathNode = $xml.CreateElement("path");      $pathNode.InnerText = $romPath
    $nameNode = $xml.CreateElement("name");      $nameNode.InnerText = $nome
    $descNode = $xml.CreateElement("desc");      $descNode.InnerText = $Jogo.synopsis
    $imgNode  = $xml.CreateElement("image");     $imgNode.InnerText = "./images/$($Rom.BaseName).jpg"
    $vidNode  = $xml.CreateElement("video");     $vidNode.InnerText = "./videos/$($Rom.BaseName).mp4"
    $manNode  = $xml.CreateElement("manual");    $manNode.InnerText = "./manuals/$($Rom.BaseName).pdf"

    $novoNode.AppendChild($pathNode) | Out-Null
    $novoNode.AppendChild($nameNode) | Out-Null
    $novoNode.AppendChild($descNode) | Out-Null
    $novoNode.AppendChild($imgNode)  | Out-Null
    $novoNode.AppendChild($vidNode)  | Out-Null
    $novoNode.AppendChild($manNode)  | Out-Null

    $root.AppendChild($novoNode) | Out-Null
    $xml.Save($GamelistPath)
}
            }
        }

        Atualizar-Progresso "Scraping finalizado."
    }
    catch {
        Mostrar-Erro "Erro durante o scraping: $_"
    }
}

function Obter-TokenIGDB {
    param (
        [string]$ClientId,
        [string]$ClientSecret
    )

    $url = "https://id.twitch.tv/oauth2/token"
    $body = @{ client_id = $ClientId; client_secret = $ClientSecret; grant_type = 'client_credentials' }
    try {
        $res = Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded'
        return $res.access_token
    } catch {
        Mostrar-Erro "Erro ao obter token do IGDB: $_"
        return $null
    }
}

function Obter-Dados-IGDB {
    param (
        [string]$JogoNome,
        [string]$ClientId,
        [string]$Token
    )

    $headers = @{ 
        'Client-ID' = $ClientId
        'Authorization' = "Bearer $Token"
    }

    $query = "search $JogoNome; fields name,summary,cover.url,videos.video_id; limit 1;"
    try {
        $res = Invoke-RestMethod -Uri "https://api.igdb.com/v4/games" -Headers $headers -Method Post -Body $query -ContentType 'text/plain'
        return $res[0]
    } catch {
        Mostrar-Erro "Erro ao consultar IGDB para '$JogoNome': $_"
        return $null
    }
}
function Obter-Dados-MobyGames {
    param (
        [string]$JogoNome
    )

    # Prepara o nome para URL de busca no MobyGames
    $searchName = [uri]::EscapeDataString($JogoNome)
    $searchUrl = "https://www.mobygames.com/search/quick?q=$searchName"

    try {
        # Obtém HTML da página de busca
        $html = Invoke-WebRequest -Uri $searchUrl -UseBasicParsing

        # Extrai o primeiro link de jogo listado (normalmente dentro de <a class="searchResult" href="/game/....">)
        $firstGameLink = $html.Links | Where-Object { $_.href -match '^/game/' } | Select-Object -First 1

        if (-not $firstGameLink) {
            Mostrar-Erro "Jogo '$JogoNome' não encontrado no MobyGames."
            return $null
        }

        $gameUrl = "https://www.mobygames.com$($firstGameLink.href)"

        # Obtém HTML da página do jogo
        $gamePage = Invoke-WebRequest -Uri $gameUrl -UseBasicParsing

        # Extrai título do jogo
        $titulo = ($gamePage.ParsedHtml.getElementsByTagName("h1") | Where-Object { $_.className -eq "niceHeaderTitle" }).innerText.Trim()

        # Extrai resumo (sinopse) do jogo
        $descNode = $gamePage.ParsedHtml.getElementsByClassName("description")
        $descricao = if ($descNode.length -gt 0) { $descNode[0].innerText.Trim() } else { "Descricao nao disponível." }

        # Extrai URL da capa (primeira imagem dentro da div "mainImage")
        $imgDiv = $gamePage.ParsedHtml.getElementsByClassName("mainImage")
        $imgUrl = if ($imgDiv.length -gt 0) {
            $imgTag = $imgDiv[0].getElementsByTagName("img")
            if ($imgTag.length -gt 0) { $imgTag[0].src } else { $null }
        } else { $null }

        return @{
            nom = $titulo
            synopsis = $descricao
            cover_url = $imgUrl
        }
    }
    catch {
        Mostrar-Erro "Erro ao consultar MobyGames para '$JogoNome': $_"
        return $null
    }
}
function Obter-Dados-ArcadeDB {
    param (
        [string]$JogoNome
    )

    $searchTerm = [uri]::EscapeDataString($JogoNome)
    $searchUrl = "https://arcade-museum.com/game_detail.php?game_id="

    try {
        # Primeira tentativa: pesquisa pelo nome na página principal
        $searchPageUrl = "https://arcade-museum.com/game_list.php?letter=$searchTerm"
        $searchPage = Invoke-WebRequest -Uri $searchPageUrl -UseBasicParsing

        # Extrair links para os jogos da página de resultados
        # (No ArcadeDB, jogos estão listados em <a href="game_detail.php?game_id=XXXX">Nome do Jogo</a>)
        $gameLinks = $searchPage.Links | Where-Object { $_.href -match "game_detail.php\?game_id=\d+" }

        if (-not $gameLinks -or $gameLinks.Count -eq 0) {
            Mostrar-Erro "Jogo '$JogoNome' não encontrado no ArcadeDB."
            return $null
        }

        $primeiroLink = $gameLinks | Select-Object -First 1
        $gameDetailUrl = "https://arcade-museum.com/$($primeiroLink.href)"

        $gamePage = Invoke-WebRequest -Uri $gameDetailUrl -UseBasicParsing

        # Extrair título: geralmente está em <title> ou em h1/h2 da página
        $titulo = ($gamePage.ParsedHtml.getElementsByTagName("h1") | Select-Object -First 1).innerText.Trim()
        if (-not $titulo) {
            $titulo = ($gamePage.ParsedHtml.getElementsByTagName("title") | Select-Object -First 1).innerText.Trim()
        }

        # Extrair descrição: ArcadeDB não tem resumo claro, pode tentar pegar textos na div "gameInfo" ou similar
        $desc = ""
        $descNode = $gamePage.ParsedHtml.getElementsByClassName("gameInfo")
        if ($descNode.length -gt 0) {
            $desc = $descNode[0].innerText.Trim()
        } else {
            $desc = "Descricao não disponível."
        }

        # Extrair imagem capa (normalmente um img dentro de div "gameImg" ou similar)
        $imgUrl = $null
        $imgDiv = $gamePage.ParsedHtml.getElementsByClassName("gameImg")
        if ($imgDiv.length -gt 0) {
            $imgTag = $imgDiv[0].getElementsByTagName("img")
            if ($imgTag.length -gt 0) {
                $imgUrl = $imgTag[0].src
                if ($imgUrl -notmatch "^http") {
                    $imgUrl = "https://arcade-museum.com/$imgUrl"
                }
            }
        }

        return @{
            nom = $titulo
            synopsis = $desc
            cover_url = $imgUrl
        }
    }
    catch {
        Mostrar-Erro "Erro ao consultar ArcadeDB para '$JogoNome': $_"
        return $null
    }
}




# Função para renomear pastas não permitidas
function Renomear-Pastas-Proibidas {
    param($pastaRoms)

    try {
        Atualizar-Progresso -mensagem "Verificando pastas não permitidas..." -percentual 0

        # Verifica se a pasta existe
        if (-not (Test-Path -Path $pastaRoms)) {
            Mostrar-Erro -mensagem "Pasta de ROMs nao encontrada: $pastaRoms"
            return
        }

        # Obtém todas as pastas
        $pastas = Get-ChildItem -Path $pastaRoms -Directory

        $totalPastas = $pastas.Count
        $contador = 0
        $pastasRenomeadas = 0
        $logItens = @()

        if ($totalPastas -eq 0) {
            Atualizar-Progresso -mensagem "Nenhuma pasta encontrada para verificar!" -percentual 100
            Start-Sleep -Seconds 2
            return
        }

        foreach ($pasta in $pastas) {
            $contador++
            $porcentagem = [math]::Round(($contador / $totalPastas) * 100)
            Atualizar-Progresso -mensagem "Verificando ($contador/$totalPastas): $($pasta.Name)" -percentual $porcentagem

            # Verifica se o nome da pasta NÃO está na lista de permitidas
            if ($global:config.Pastas.Permitidas -notcontains $pasta.Name) {
                $novoNome = "_$($pasta.Name)"
                $novoCaminho = Join-Path -Path $pastaRoms -ChildPath $novoNome
                
                try {
                    # Renomeia a pasta
                    Rename-Item -Path $pasta.FullName -NewName $novoNome -Force
                    $pastasRenomeadas++
                    $logItens += "$($pasta.FullName) -> $novoNome"
                } catch {
                    Write-Host "Erro ao renomear pasta $($pasta.Name): $_" -ForegroundColor Yellow
                    $logItens += "ERRO: $($pasta.FullName) -> Falha ao renomear"
                }
            }
        }

        # Gera log da operação
        Gerar-Log -operacao "PastasProibidas" -itens $logItens

        Atualizar-Progresso -mensagem "Verificacao concluida! $pastasRenomeadas pastas renomeadas." -percentual 100
        Start-Sleep -Seconds 2

    } catch {
        Mostrar-Erro -mensagem "Erro ao verificar pastas proibidas: $_"
    }
}
# Função para descompactar arquivos
function Descompactar-Arquivos {
    param ($pastaSelecionada)

    try {
        $formProgresso = New-Object System.Windows.Forms.Form
        $formProgresso.Text = $global:config.Textos.BotaoDescompactar
        $formProgresso.Size = New-Object System.Drawing.Size(400, 150)
        $formProgresso.StartPosition = "CenterScreen"
        $formProgresso.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $formProgresso.MaximizeBox = $false

        $labelStatus = New-Object System.Windows.Forms.Label
        $labelStatus.Location = New-Object System.Drawing.Point(10, 20)
        $labelStatus.Size = New-Object System.Drawing.Size(360, 20)
        $labelStatus.Text = "Preparando para descompactar..."
        $formProgresso.Controls.Add($labelStatus)

        $progressBar = New-Object System.Windows.Forms.ProgressBar
        $progressBar.Location = New-Object System.Drawing.Point(10, 50)
        $progressBar.Size = New-Object System.Drawing.Size(360, 20)
        $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        $formProgresso.Controls.Add($progressBar)

        $formProgresso.Show()
        [System.Windows.Forms.Application]::DoEvents()

        # Verifica se o 7-Zip está instalado
        if (-not (Test-Path $global:config.Paths.SevenZipPath)) {
            $labelStatus.Text = "7-Zip nao encontrado em $($global:config.Paths.SevenZipPath)"
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Seconds 3
            $formProgresso.Close()
            Mostrar-Erro -mensagem "7-Zip nao encontrado em $($global:config.Paths.SevenZipPath)`nPor favor, instale o 7-Zip primeiro."
            return
        }

        $arquivos = Get-ChildItem -Path $pastaSelecionada -File | 
                    Where-Object { $global:config.Extensoes.Compactadas -contains $_.Extension.ToLower() }

        $totalArquivos = $arquivos.Count
        $contador = 0
        $logItens = @()

        if ($totalArquivos -eq 0) {
            $labelStatus.Text = "Nenhum arquivo compactado encontrado!"
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Seconds 2
            $formProgresso.Close()
            return
        }

        foreach ($arquivo in $arquivos) {
            $contador++
            $porcentagem = [math]::Round(($contador / $totalArquivos) * 100)
            $progressBar.Value = $porcentagem
            $labelStatus.Text = "Descompactando ($contador/$totalArquivos): $($arquivo.Name)"
            [System.Windows.Forms.Application]::DoEvents()

            $argumentos = "x `"$($arquivo.FullName)`" -o`"$pastaSelecionada`" -y"
            $processo = Start-Process -FilePath $global:config.Paths.SevenZipPath -ArgumentList $argumentos -Wait -NoNewWindow -PassThru

            if ($processo.ExitCode -eq 0) {
                Remove-Item $arquivo.FullName -Force -ErrorAction SilentlyContinue
                $logItens += "SUCESSO: $($arquivo.FullName) -> Descompactado"
            } else {
                Write-Host "Erro ao descompactar $($arquivo.Name)" -ForegroundColor Red
                $logItens += "ERRO: Falha ao descompactar $($arquivo.FullName)"
            }
        }

        # Gera log da operação
        Gerar-Log -operacao "DescompactarROMs" -itens $logItens

        $labelStatus.Text = "Descompactacao concluida! $contador arquivos processados."
        $progressBar.Value = 100
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Seconds 2
        $formProgresso.Close()

    } catch {
        if ($labelStatus -ne $null) {
            $labelStatus.Text = "Ocorreu um erro: $_"
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Seconds 3
        if ($formProgresso -ne $null) {
            $formProgresso.Close()
        }
        Mostrar-Erro -mensagem "Erro ao descompactar: $_"
    }
}

# Interface gráfica principal
function Mostrar-Interface {
    $global:config = Carregar-Config
    if (-not $global:config) { 
        [System.Windows.Forms.MessageBox]::Show("Nao foi possivel carregar a configuracao. O aplicativo será fechado.", "Erro", "OK", "Error")
        return 
    }

    $global:formPrincipal = New-Object System.Windows.Forms.Form
    $global:formPrincipal.Text = $global:config.Textos.TituloPrincipal
    $global:formPrincipal.Size = New-Object System.Drawing.Size(600, 400)
    $global:formPrincipal.StartPosition = "CenterScreen"
    $global:formPrincipal.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $global:formPrincipal.MaximizeBox = $false

    # Link para romsPath
    $linkRomsPath = New-Object System.Windows.Forms.LinkLabel
    $linkRomsPath.Location = New-Object System.Drawing.Point(10, 10)
    $linkRomsPath.Size = New-Object System.Drawing.Size(560, 20)
    $linkRomsPath.Text = "$($global:config.Textos.LabelRomsPath): $($global:config.Paths.RomsPath)"
    $linkRomsPath.Add_Click({
        if (Test-Path -Path $global:config.Paths.RomsPath) {
            Start-Process "explorer.exe" -ArgumentList $global:config.Paths.RomsPath
        } else {
            Mostrar-Erro -mensagem "O caminho para ROMs não foi encontrado: $($global:config.Paths.RomsPath)"
        }
    })
    $global:formPrincipal.Controls.Add($linkRomsPath)

    # Painel de botões
    $panel = New-Object Windows.Forms.Panel
    $panel.Location = New-Object Drawing.Point(10, 40)
    $panel.Size = New-Object Drawing.Size(560, 200)
    $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    # Função auxiliar para criar botões
    function Criar-Botao {
        param(
            [string]$Texto,
            [int]$X,
            [int]$Y,
            [int]$Largura = 120,
            [int]$Altura = 40,
            [scriptblock]$Acao
        )

        $botao = New-Object Windows.Forms.Button
        $botao.Text = $Texto
        $botao.Size = New-Object Drawing.Size($Largura, $Altura)
        $botao.Location = New-Object Drawing.Point($X, $Y)
        $botao.Add_Click($Acao)
        return $botao
    }

    # Botões (usando textos do config)
    $btnOrganizar = Criar-Botao -Texto $global:config.Textos.BotaoOrganizar -X 20 -Y 20 -Acao {
        Organizar-ROMs-Por-Console -pastaRoms $global:config.Paths.RomsPath
    }

    $btnPastasProibidas = Criar-Botao -Texto $global:config.Textos.BotaoPastasProibidas -X 180 -Y 20 -Acao {
        Renomear-Pastas-Proibidas -pastaRoms $global:config.Paths.RomsPath
    }

    $btnDuplicatas = Criar-Botao -Texto $global:config.Textos.BotaoDuplicatas -X 340 -Y 20 -Acao {
        Verificar-Duplicatas -pastaRoms $global:config.Paths.RomsPath
    }

    $btnCompactar = Criar-Botao -Texto $global:config.Textos.BotaoCompactar -X 20 -Y 80 -Acao {
        $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderBrowser.Description = "Selecione a pasta com ROMs para compactar"
        $folderBrowser.ShowNewFolderButton = $false

        if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            Compactar-ROMs -pastaSelecionada $folderBrowser.SelectedPath
        }
    }

    $btnDescompactar = Criar-Botao -Texto $global:config.Textos.BotaoDescompactar -X 180 -Y 80 -Acao {
        $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderBrowser.Description = "Selecione a pasta com arquivos compactados"
        $folderBrowser.ShowNewFolderButton = $false

        if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            Descompactar-Arquivos -pastaSelecionada $folderBrowser.SelectedPath
        }
    }

    $btnScraping = Criar-Botao -Texto $global:config.Textos.BotaoScraping -X 180 -Y 140 -Largura 200 -Acao {
        $fonte = Iniciar-Scraping #Selecionar-Fonte-Scraping
        if ($fonte) {
            Iniciar-Scraping -fonte $fonte
        }
    }

    # Adicionar botões ao painel
    $panel.Controls.AddRange(@($btnOrganizar, $btnPastasProibidas, $btnDuplicatas, 
                             $btnCompactar, $btnDescompactar, $btnScraping))

    # Barra de progresso e status
    $global:progressBar = New-Object Windows.Forms.ProgressBar
    $global:progressBar.Minimum = 0
    $global:progressBar.Maximum = 100
    $global:progressBar.Value = 0
    $global:progressBar.Size = New-Object Drawing.Size(560, 25)
    $global:progressBar.Location = New-Object Drawing.Point(10, 260)
    $global:progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous

    $global:lblStatus = New-Object Windows.Forms.Label
    $global:lblStatus.Text = $global:config.Textos.LabelStatus
    $global:lblStatus.Size = New-Object Drawing.Size(560, 20)
    $global:lblStatus.Location = New-Object Drawing.Point(10, 290)
    $global:lblStatus.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center

    # Botão Sair
    $btnSair = Criar-Botao -Texto $global:config.Textos.BotaoSair -X 230 -Y 320 -Acao {
        $global:formPrincipal.Close()
    }

    # Adicionar controles ao formulário
    $global:formPrincipal.Controls.Add($panel)
    $global:formPrincipal.Controls.Add($global:progressBar)
    $global:formPrincipal.Controls.Add($global:lblStatus)
    $global:formPrincipal.Controls.Add($btnSair)

    # Exibir janela
    $global:formPrincipal.Topmost = $false
    $global:formPrincipal.Add_Shown({ $global:formPrincipal.Activate() })
    [void]$global:formPrincipal.ShowDialog()
}

# Iniciar aplicação
Mostrar-Interface