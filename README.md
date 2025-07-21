# Organizador CGPT de ROMs

Ferramenta completa e automatizada para organização de ROMs com interface gráfica, compactação, verificação de duplicatas, scraping de mídias (ScreenScraper, IGDB, TheGamesDB, etc.) e geração automática de `gamelist.xml`.
No momento apenas o ScreenScraper está configurado.

## ✅ Funcionalidades
- Organização automática por console com base em extensões.
- Compactação individual em `.7z` com alta taxa de compressão.
- Descompactação de arquivos em lote.
- Verificação de duplicatas com interface gráfica para escolha de exclusão
- Geração de logs completos (TXT)
- Detecção e renomeio de pastas inválidas com prefixo `_` (detecta pastas que não são de consoles e marca com _ no inicio)
- Scraping automático de imagens, vídeos e manuais
- Geração e atualização do `gamelist.xml` por console
- Interface gráfica em PowerShell (Windows Forms)
- Toda configuração centralizada em `.xml`

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
1. Configure os caminhos e credenciais no `.xml`.
2. Coloque suas ROMs na pasta `roms/`.
3. Execute `organizador_cgpt.ps1` com PowerShell.
	3.1. Abra o PowerShell como administrador, navegue até a pasta que contém o arquivo e execute "./organizador_cgpt.ps1"
	3.2. Caso dê erro relacionado à politica na primeira utilização, esecute o comando "Set-ExecutionPolicy RemoteSigned" após isso, confirme com "S"
4. Use a interface gráfica para organizar, compactar, verificar duplicatas, baixar mídias e gerar o `gamelist.xml`.

## 🧑‍💻 Contribuições
Contribuições são bem-vindas! 
Use issues ou pull requests.


## 💻 Principais Correções e Melhorias:
20250718 - CORREÇÃO VIA DEEPSEEK
- Correção de erros de sintaxe:
	1. Corrigidos colchetes faltantes em várias partes do código
	2. Corrigido nome de variável ($destinoCompleto estava escrito errado)

- Interface Gráfica Aprimorada:
	1. Adicionados todos os botões faltantes para cada função principal:
	2. Organizar ROMs

- Inseridos botões:
	1. Renomear Pastas
	2. Ver Duplicatas
	3. Compactar ROMs
	4. Iniciar Scraping
	5. Sair

- Adicionado painel para agrupar os botões principais
- Adicionado label de status

- Melhorias na organização do código:
	1. Movida a variável global $metadados para o início do script
	2. Adicionado parâmetro -cfg à função Get-ConsolesMap
	3. Adicionado [System.Windows.Forms.Application]::DoEvents() na barra de progresso

- Correções na lógica:
	1. Verificação correta dos caminhos de mídia (usando OR em vez de AND)
	2. Passagem correta dos parâmetros para Scrape-ScreenScraper
	3. Adicionado parâmetro -metadados à função Atualizar-GamelistXml

- Melhorias visuais:
	1. Tamanho da janela aumentado para acomodar todos os controles
	2. Barra de progresso mais larga
	3. Formato fixo para a janela (não redimensionável)
	
- Tratamento de erros:
	1. Adicionada função Mostrar-Erro para exibir mensagens de erro consistentes
	2. Todos os blocos críticos agora têm tratamento de erro com try-catch
	3. Mensagens de erro são exibidas tanto em MessageBox quanto no console

- Barra de progresso:
	1. Incrementada para todas as operações demoradas
	2. Agora mostra o nome do arquivo sendo processado no status
	3. Melhor atualização visual com DoEvents()

- Janela de duplicatas aprimorada:
	1. A janela principal é minimizada quando a janela de duplicatas é aberta
	2. Caminhos completos são substituídos por caminhos relativos (mostrando apenas a partir da pasta \roms)
	3. Duplicatas são agrupadas por hash MD5
	4. Interface em árvore (TreeView) para melhor organização
	5. Itens originais destacados em verde
	6. Checkboxes para seleção múltipla

- Outras melhorias:
	1. Variável global $formPrincipal para controle da janela principal
	2. Melhor formatação dos logs de duplicatas
	3. Confirmação antes de excluir arquivos duplicados
	4. Status mais informativo na barra de status

- Interface mais robusta:
	1. Verificação de sucesso em todas as operações
	2. Mensagens de status mais descritivas
	3. Progresso detalhado durante o scraping

Esta versão agora possui uma interface completa com todos os botões necessários para executar todas as funções do organizador de ROMs, mais robusta, com melhor tratamento de erros e uma interface mais amigável para o gerenciamento de duplicatas..

## 📄 Licença
Distribuído sob a Licença MIT. Veja `LICENSE` para mais detalhes.
