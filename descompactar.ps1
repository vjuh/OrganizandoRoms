Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Configurações
$sevenZipPath = "C:\Program Files\7-Zip\7z.exe"
$extensoesCompactadas = @(".7z", ".zip", ".rar")

# Função principal
function Descompactar-Pasta {
    param (
        [string]$pastaSelecionada
    )

    # Verifica se o 7-Zip está instalado
    if (-not (Test-Path $sevenZipPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "7-Zip não encontrado em $sevenZipPath`nPor favor, instale o 7-Zip primeiro.",
            "Erro",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }

    # Cria e configura a barra de progresso
    $formProgresso = New-Object System.Windows.Forms.Form
    $formProgresso.Text = "Descompactando arquivos..."
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

    # Mostra a janela de progresso
    $formProgresso.Show()
    [System.Windows.Forms.Application]::DoEvents()

    try {
        # Obtém todos os arquivos compactados na pasta
        $arquivos = Get-ChildItem -Path $pastaSelecionada -File | 
                    Where-Object { $extensoesCompactadas -contains $_.Extension }

        $totalArquivos = $arquivos.Count
        $contador = 0

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

            # Descompacta diretamente na pasta selecionada
            $argumentos = "x `"$($arquivo.FullName)`" -o`"$pastaSelecionada`" -y"
            $processo = Start-Process -FilePath $sevenZipPath -ArgumentList $argumentos -Wait -NoNewWindow -PassThru

            if ($processo.ExitCode -eq 0) {
                # Remove o arquivo compactado após descompactar com sucesso
                Remove-Item $arquivo.FullName -Force
            } else {
                Write-Host "Erro ao descompactar $($arquivo.Name)" -ForegroundColor Red
            }
        }

        $labelStatus.Text = "Descompactação concluída! $contador arquivos processados."
        $progressBar.Value = 100
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Seconds 2

    } catch {
        $labelStatus.Text = "Ocorreu um erro: $_"
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Seconds 3
    } finally {
        $formProgresso.Close()
    }
}

# Cria a interface gráfica principal
$form = New-Object System.Windows.Forms.Form
$form.Text = "Descompactador Automático"
$form.Size = New-Object System.Drawing.Size(400, 200)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false

# Label de instrução
$label = New-Object System.Windows.Forms.Label
$label.Location = New-Object System.Drawing.Point(10, 20)
$label.Size = New-Object System.Drawing.Size(360, 40)
$label.Text = "Selecione uma pasta contendo arquivos compactados (.7z, .zip, .rar):"
$form.Controls.Add($label)

# Botão para selecionar pasta
$buttonSelecionar = New-Object System.Windows.Forms.Button
$buttonSelecionar.Location = New-Object System.Drawing.Point(10, 70)
$buttonSelecionar.Size = New-Object System.Drawing.Size(360, 30)
$buttonSelecionar.Text = "Selecionar Pasta"
$buttonSelecionar.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Selecione a pasta com arquivos compactados"
    $folderBrowser.ShowNewFolderButton = $false

    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $pastaSelecionada = $folderBrowser.SelectedPath
        Descompactar-Pasta -pastaSelecionada $pastaSelecionada
    }
})
$form.Controls.Add($buttonSelecionar)

# Botão Sair
$buttonSair = New-Object System.Windows.Forms.Button
$buttonSair.Location = New-Object System.Drawing.Point(10, 120)
$buttonSair.Size = New-Object System.Drawing.Size(360, 30)
$buttonSair.Text = "Sair"
$buttonSair.Add_Click({ $form.Close() })
$form.Controls.Add($buttonSair)

# Exibe o formulário
[void]$form.ShowDialog()