# CheatOptimizer

CheatOptimizer é um script em PowerShell com interface gráfica (WinForms) focado em **otimização de desempenho**, **desativação de serviços desnecessários**, **tweaks de registro** e **desativação/remoção de componentes de IA do Windows**.

O usuário **escolhe manualmente** o que aplicar — nada é alterado automaticamente.

---

## 🚀 Como usar

Abra o PowerShell e execute (o script pede elevação de Administrador sozinho, se necessário):

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/cheatzera/CheatOptimizer/refs/heads/main/CheatOptimizer.ps1")))
```

Ou baixe o `CheatOptimizer.ps1` e rode com botão direito → *Executar com o PowerShell*.

Passe o mouse sobre cada opção para ver uma descrição.

---

## 🧩 Funcionalidades

### 🧠 IA / Copilot
- Desativar chaves de registro de IA (Recall, Click to Do)
- Impedir a reinstalação de pacotes de IA
- Desativar políticas do Copilot (e o botão da barra de tarefas)
- Remover pacotes Appx de IA *(irreversível)*
- Desativar o recurso opcional Recall
- Remover pacotes CBS de IA *(experimental, irreversível)*
- Apagar dados do Recall (snapshots) *(irreversível)*
- Ocultar componentes de IA nas Configurações
- Desativar recursos de IA do Notepad (Rewrite)
- Desativar tarefas agendadas do Recall/IA

### 🔧 Serviços
SysMain, Windows Search, BITS, Spooler de Impressão, Telemetria (DiagTrack), Geolocalização, Fax, Smart Card.

### 🧾 Tweaks de registro
- Desativar GameDVR
- `Win32PrioritySeparation = 36`
- Desativar Multiplane Overlay (MPO)
- Desativar Power Throttling
- `MenuShowDelay = 0`
- Desativar NDU

### ⏱️ Tarefas agendadas
WinSAT, Windows Error Reporting, Compatibility Appraiser, tarefas de Diagnosis.

---

## 🔄 Reverter alterações

Antes de alterar qualquer coisa, o programa guarda o estado original em
`%ProgramData%\CheatOptimizer\backup.json`. O botão **Revert** restaura as opções
**marcadas** para o valor original salvo (ou para o padrão do Windows, caso não haja registro).

- Há também a opção de criar um **ponto de restauração** antes de aplicar.
- Remoções (pacotes Appx/CBS, dados apagados) **não** podem ser revertidas automaticamente.
- Algumas mudanças só têm efeito após reiniciar (ou sair e entrar na conta).

## ⚠️ Important
This project is intended for advanced users. Use at your own risk. Disabling services such as Print Spooler, BITS or Smart Card can break printing, Windows Update downloads or smart-card logins.

## 🇧🇷 Aviso
Este projeto é voltado para usuários avançados. Use por sua conta e risco. Desativar serviços como Spooler, BITS ou Smart Card pode quebrar impressão, downloads do Windows Update ou login por smart card.

---

👤 **Autor:** [cheatzera](https://github.com/cheatzera)
