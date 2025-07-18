
# organizador_cgpt.ps1
# Ferramenta completa para organização de ROMs com interface gráfica e automação
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Diretórios principais
$Root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Config = Join-Path $Root "cgpt_config"
$Logs = Join-Path $Config "logs"
$consolesTxt = Join-Path $Config "consoles.txt"
$pastasAceitasTxt = Join-Path $Config "pastas_aceitas.txt"
$csvLog = Join-Path $Logs "log_organizador.csv"
$logGeral = Join-Path $Logs "log_geral.txt"
$logPastasInvalidas = Join-Path $Logs "log_pastas_nao_aceitas.txt"
$logArquivos = Join-Path $Logs "log_todos_arquivos.txt"
$7zip = "C:\Program Files\7-Zip\7z.exe"

# Garantir que os diretórios existem
$null = New-Item -ItemType Directory -Path $Config -Force
$null = New-Item -ItemType Directory -Path $Logs -Force

# Criar arquivos padrão se não existirem
if (!(Test-Path $consolesTxt)) {
    @"
GBA: .gba
GB: .gb
GBC: .gbc
NES: .nes
SNES: .sfc, .smc
MegaDrive: .md, .gen, .smd, .bin
MasterSystem: .sms
N64: .n64, .z64, .v64
PSX: .iso, .cue
"@ | Set-Content $consolesTxt -Encoding UTF8
}
if (!(Test-Path $pastasAceitasTxt)) {
    @"
GBA
GB
GBC
NES
SNES
MegaDrive
MasterSystem
N64
PSX
"@ | Set-Content $pastasAceitasTxt -Encoding UTF8
}

# Funções principais
function ObterMapeamentoConsoles {
    $map = @{}
    Get-Content $consolesTxt | Where-Object {$_ -match ":"} | ForEach-Object {
        $parts = $_ -split ":", 2
        $console = $parts[0].Trim()
        $exts = $parts[1].Split(",") | ForEach-Object { $_.Trim().ToLower() }
        foreach ($ext in $exts) {
            $map[$ext] = $console
        }
    }
    return $map
}

function LogGeral ($msg) {
    Add-Content $logGeral -Value "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") - $msg"
}

function OrganizarPorConsole {
    $map = ObterMapeamentoConsoles
    Get-ChildItem -Path $Root -Recurse -File | Where-Object { $_.Name -match "\(pt-br\)" } | ForEach-Object {
        $ext = $_.Extension.ToLower()
        if ($map.ContainsKey($ext)) {
            $dest = Join-Path $Root $map[$ext]
            if (!(Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
            Move-Item $_.FullName (Join-Path $dest $_.Name)
            LogGeral "Movido: $($_.FullName) → $dest\$($_.Name)"
        }
    }
}

function CompactarArquivos {
    Get-ChildItem -Path $Root -Recurse -File | Where-Object {
        $_.Extension -notin ".zip", ".7z", ".rar" -and $_.Name -match "\(pt-br\)"
    } | ForEach-Object {
        $dest = "$($_.FullName).7z"
        & "$7zip" a -t7z -mx=9 "$dest" "$($_.FullName)" | Out-Null
        if (Test-Path $dest) {
            Remove-Item $_.FullName
            LogGeral "Compactado: $($_.FullName) → $dest"
        }
    }
}

function ListarPastasInvalidas {
    $validas = Get-Content $pastasAceitasTxt
    Get-ChildItem -Path $Root -Directory | ForEach-Object {
        if ($validas -notcontains $_.Name -and $_.Name -notlike "cgpt_config*") {
            $novoNome = "# $($_.Name)"
            Rename-Item $_.FullName -NewName $novoNome
            Add-Content $logPastasInvalidas "$($_.FullName) renomeada para $novoNome"
        }
    }
}

function ListarArquivos {
    Get-ChildItem -Path $Root -Recurse | ForEach-Object {
        Add-Content $logArquivos $_.FullName
    }
}

function VerificarDuplicatas {
    $hashes = @{}
    $duplicatas = @()
    Get-ChildItem -Path $Root -Recurse -File | ForEach-Object {
        $hash = Get-FileHash $_.FullName -Algorithm MD5
        if ($hashes.ContainsKey($hash.Hash)) {
            $duplicatas += $_
        } else {
            $hashes[$hash.Hash] = $_.FullName
        }
    }
    if ($duplicatas.Count -gt 0) {
        $form = New-Object Windows.Forms.Form
        $form.Text = "Duplicatas Encontradas"
        $form.Width = 600
        $form.Height = 400

        $listBox = New-Object Windows.Forms.ListBox
        $listBox.Width = 560
        $listBox.Height = 300
        $listBox.Top = 10
        $listBox.Left = 10
        $listBox.SelectionMode = "MultiExtended"
        $form.Controls.Add($listBox)

        foreach ($f in $duplicatas) {
            $listBox.Items.Add($f.FullName)
        }

        $btnExcluir = New-Object Windows.Forms.Button
        $btnExcluir.Text = "Excluir Selecionados"
        $btnExcluir.Top = 320
        $btnExcluir.Left = 10
        $btnExcluir.Add_Click({
            foreach ($item in $listBox.SelectedItems) {
                Remove-Item $item -Force
                LogGeral "Duplicata removida: $item"
            }
            $form.Close()
        })
        $form.Controls.Add($btnExcluir)
        $form.ShowDialog()
    }
}

# Interface Gráfica Principal
$form = New-Object Windows.Forms.Form
$form.Text = "Organizador de ROMs - CGPT"
$form.Size = New-Object Drawing.Size(400,400)
$form.StartPosition = "CenterScreen"

function Add-Botao {
    param ($texto, $top, $acao)
    $btn = New-Object Windows.Forms.Button
    $btn.Text = $texto
    $btn.Width = 350
    $btn.Height = 40
    $btn.Top = $top
    $btn.Left = 20
    $btn.Add_Click($acao)
    $form.Controls.Add($btn)
}

Add-Botao "1. Organizar por Console" 20 { OrganizarPorConsole }
Add-Botao "2. Compactar arquivos (.7z)" 70 { CompactarArquivos }
Add-Botao "3. Verificar Duplicatas" 120 { VerificarDuplicatas }
Add-Botao "4. Listar arquivos e pastas" 170 { ListarArquivos }
Add-Botao "5. Listar/renomear pastas inválidas" 220 { ListarPastasInvalidas }
Add-Botao "Fechar" 280 { $form.Close() }

[void]$form.ShowDialog()
