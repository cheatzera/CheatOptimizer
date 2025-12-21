# CheatOptimizer

CheatOptimizer é um script em PowerShell com interface gráfica (WinForms) focado em **otimização de desempenho**, **desativação de serviços desnecessários**, **tweaks de registro** e **remoção/desativação de componentes de IA do Windows**.

O script permite que o usuário **escolha manualmente** o que deseja aplicar, sem alterações automáticas forçadas.

---

## 🚀 Como usar

Execute diretamente no PowerShell (Administrador):

powershell


& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/cheatzera/CheatOptimizer/main/CheatOptimizer.ps1")))

🧩 Funcionalidades


🧠 IA / Copilot

Desativar chaves de registro relacionadas à IA

Desativar Copilot e Recall

Remover pacotes Appx de IA

Remover componentes ocultos da CBS

Impedir reinstalação de pacotes de IA

Remover tarefas agendadas do Recall

Ocultar componentes de IA nas Configurações

🔧 Serviços do Windows

SysMain

Windows Search

Telemetria (DiagTrack)

BITS

Spooler de Impressão

Geolocalização

Fax

Smart Card

🧾 Tweaks de Registro

Desativar GameDVR

Ajustar Win32PrioritySeparation

Desativar Multiplane Overlay

Desativar Power Throttling

MenuShowDelay = 0

Desativar NDU

⏱️ Tarefas Agendadas

WinSAT

Windows Error Reporting

Compatibility Appraiser

Diagnosis Tasks

🔄 Reverter alterações

O CheatOptimizer possui um botão Revert, que tenta restaurar:

Serviços

Chaves de registro principais

Tarefas agendadas

Nem todas as remoções (ex: pacotes CBS) podem ser revertidas automaticamente.

🎨 Interface

Interface gráfica em WinForms

Tema azul/ciano

Execução direta via PowerShell (sem instalador)

⚠️ Aviso importante

Este script modifica configurações do sistema operacional.
Use por sua conta e risco.

Recomendado:

Criar um ponto de restauração

Usar apenas se souber o que está fazendo

👤 Autor

cheatzera
GitHub: https://github.com/cheatzera
