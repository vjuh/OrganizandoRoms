@echo off
setlocal enabledelayedexpansion

REM Caminho raiz onde estão os arquivos
set "raiz=C:\Users\Junior\Downloads\roms"

REM Arquivo de log
set "log=%raiz%\log_renomeacao.txt"

REM Limpa o log anterior (se existir)
> "%log%" echo Início do log de renomeações em %date% às %time%

REM Vai até a pasta raiz
cd /d "%raiz%"

REM Percorre todas as subpastas e arquivos
for /r %%f in (*.*) do (
    set "arquivo=%%~nxf"
    set "nome=%%~nf"
    set "ext=%%~xf"

    REM Pula arquivos que já têm (pt-br)
    echo !nome! | findstr /i "(pt-br)" >nul
    if errorlevel 1 (
        set "novo_nome=!nome! (pt-br)!!ext!"
        echo Renomeando: %%~nxf → !novo_nome!
        ren "%%~f" "!novo_nome!"

        echo %%~f → !novo_nome! >> "%log%"
    )
)

echo.
echo Renomeação concluída. Log salvo em:
echo %log%
pause