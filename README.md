# Organizador CGPT de ROMs

Ferramenta completa e automatizada para organização de ROMs com interface gráfica, compactação, verificação de duplicatas, scraping de mídias (ScreenScraper, IGDB, TheGamesDB, etc.) e geração automática de `gamelist.xml`.

## ✅ Funcionalidades
- Organização automática por console com base em extensões
- Compactação individual em `.7z` com alta taxa de compressão
- Verificação de duplicatas com interface gráfica para escolha de exclusão
- Geração de logs completos (TXT e CSV)
- Detecção e renomeio de pastas inválidas com prefixo `#`
- Scraping automático de imagens, vídeos e manuais
- Geração e atualização do `gamelist.xml` por console
- Interface gráfica em PowerShell (Windows Forms)
- Toda configuração centralizada em `configurar.xml`

## 🛠️ Requisitos
- PowerShell 5+ (Windows)
- [.NET Framework 4.8+](https://dotnet.microsoft.com/en-us/download/dotnet-framework)
- [7-Zip](https://www.7-zip.org/) instalado no caminho padrão
- Contas e chaves de API para ScreenScraper, IGDB, TheGamesDB, etc.

## 📁 Estrutura de Pastas Recomendada
/
├── organizador_cgpt.ps1
├── cgpt_config/
│ ├── configurar.xml
│ ├── consoles.txt
│ ├── pastas_aceitas.txt
│ └── logs/
├── roms/
│ ├── GBA/, SNES/, etc.
│  ├── images/
│  ├── videos/
│  └── manuals/


## 💡 Como usar
1. Configure os caminhos e credenciais no `configurar.xml`.
2. Coloque suas ROMs na pasta `roms/` (somente com `(pt-br)`).
3. Execute `organizador_cgpt.ps1` com PowerShell.
4. Use a interface gráfica para organizar, compactar, verificar duplicatas, baixar mídias e gerar o `gamelist.xml`.

## 🧑‍💻 Contribuições
Contribuições são bem-vindas! Use issues ou pull requests.

## 📄 Licença
Distribuído sob a Licença MIT. Veja `LICENSE` para mais detalhes.
