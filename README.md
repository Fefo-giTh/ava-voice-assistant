# Ava — assistente de voz para Mac

Um assistente pessoal controlado só por voz, com um mascote em pixel art flutuando na tela. Você aperta um atalho, conversa normalmente, e ele responde falando — em português do Brasil.

- **Ouve e fala no seu Mac:** a transcrição (Whisper, na GPU) e a voz (Kokoro) rodam localmente.
- **Pensa com o Claude:** usa o [Claude Code](https://claude.com/claude-code) com a sua própria conta (Haiku para responder rápido, Opus como consultor nas tarefas difíceis). Não precisa de chave de API.
- **Mexe nos seus arquivos com segurança:** lê, procura, cria, edita e organiza arquivos da sua pasta pessoal — mas nunca apaga de verdade (manda para a Lixeira) e pede confirmação antes de mexer em muita coisa.
- **Conversa ao vivo:** com a sessão aberta, é só falar; ele responde frase por frase e volta a ouvir.

> Projeto independente, sem relação com a Anthropic.

## Instalar com um único prompt

Abra o Claude Code no terminal e cole (troque o nome, a voz e o atalho como quiser):

```
Clone https://github.com/Fefo-giTh/ava-voice-assistant na minha pasta pessoal e rode
./install.sh --nome Luna --voz pf_dora --atalho option+space
Se faltar alguma dependência, me explique como instalar e rode de novo.
```

Ou faça na mão:

```bash
git clone https://github.com/Fefo-giTh/ava-voice-assistant ~/ava-voice-assistant
cd ~/ava-voice-assistant
./install.sh --nome Luna --voz pf_dora --atalho option+space
```

### Requisitos

- Mac com chip Apple (M1 ou mais novo) e macOS 14+. Com 8 GB de RAM funciona; com 16 GB sobra folga.
- Ferramentas do Xcode (`xcode-select --install`) e [Homebrew](https://brew.sh).
- [Claude Code](https://claude.com/claude-code) instalado e com login feito. As conversas usam o limite da sua assinatura.
- O instalador cuida do resto (`uv`, `espeak-ng`, modelos de voz). A primeira instalação baixa ~2 GB.

## Usar

| Ação | O que acontece |
|---|---|
| Atalho (padrão **Control+Espaço**) | Abre a sessão: o mascote aparece, aguardando. |
| Começar a falar | Ele ouve; quando você para, pensa e responde em voz. Depois volta a aguardar. |
| **Esc** enquanto ele pensa ou fala | Corta a resposta e volta a aguardar. |
| Atalho de novo (ou Esc aguardando) | Fecha a sessão; o mascote some. |

Exemplos: "Quantos arquivos tem na minha pasta Downloads?", "Organiza os PDFs da Mesa numa pasta Documentos/PDFs", "Me passa um link para aprender Python" (vai para a área de transferência), "Faz um resumo de como estudar para provas" (vira nota no Obsidian, se você escolher um cofre no menu).

O menu na barra (ícone do mascote) tem: **Voz**, **Cofre do Obsidian**, **Atalho…** e **Abrir ao iniciar o Mac**.

Se usar Control+Espaço, desative o atalho do macOS em **Ajustes do Sistema › Teclado › Atalhos › Fontes de Entrada**.

## Personalizar

Tudo fica em `~/.ava/config.json` (o `install.sh` cria). Depois de editar, saia e abra o app de novo.

```json
{
  "name": "Luna",
  "voice": "pf_dora",
  "hotkey": "option+space",
  "palette": ["#07050D", "#140C26", "#2A1852", "#4A2A96", "#7848DC", "#A86EFF", "#D696FF", "#FFECFF"],
  "mascot": {
    "rows": ["....##########....", "...##E######E##...", "..##############..", "..##############.."],
    "legs": ["..##.###..###.##..", "..###.##..##.###.."]
  }
}
```

- **name:** como o assistente se chama.
- **voice:** `pf_dora` (feminina), `pm_alex` (masculina jovem) ou `pm_santa` (masculina madura).
- **hotkey:** `control`/`option`/`command`/`shift` + `space`, uma letra ou um número. Ex.: `option+shift+a`.
- **palette:** 8 cores, da mais escura para a mais clara. A 6ª é a cor principal do mascote.
- **mascot:** 4 linhas de 18 caracteres (`#` corpo, `E` olho, `.` vazio) e 2 quadros de pernas. Cada caractere vira um pixel 2×4.

## Segurança

- O Claude **não tem comando para apagar** (`rm` e afins são bloqueados). "Apagar" = mover para a Lixeira.
- O terminal dele roda num **sandbox que só escreve na sua pasta pessoal**.
- Antes de mandar para a Lixeira, sobrescrever arquivos ou mexer em mais de cinco de uma vez, ele **pergunta e espera seu "sim"** (essa parte é instrução, não bloqueio técnico).
- O microfone só fica ativo com a sessão aberta. A sessão fecha sozinha depois de 5 minutos sem ninguém falar.

## Privacidade e custos

- Sua voz é transcrita no próprio Mac. O **texto** da conversa e o conteúdo dos arquivos que o assistente abrir vão para o Claude (Anthropic), como em qualquer uso do Claude Code.
- Não há cobrança extra: usa o limite da sua assinatura do Claude.

## Como funciona

```
Sources/Ava/   app Swift: atalho, microfone, sessão, mascote (44×44 px ampliado, paleta de 8 cores, dithering)
backend/       servidor local em Python (porta 8000): mlx-whisper (fala → texto) e Kokoro (texto → fala)
               desliga sozinho após 10 min sem uso
claude -p      cérebro: um processo do Claude Code aberto durante o uso, respostas em streaming
```

Desenvolver: `swift test` roda os testes; `AVA_SERVER=1` e `AVA_CLAUDE=1` incluem os testes que usam o servidor de voz e o Claude de verdade. `./build-app.sh` recompila e reinstala.

## Desinstalar

```bash
rm -rf /Applications/Ava.app ~/.ava ~/ava-voice-assistant
```

Os modelos de voz ficam em `~/.cache/huggingface` (Kokoro-82M e whisper-small-mlx) e podem ser apagados também.

## Licença

MIT. Modelos e bibliotecas usados têm suas próprias licenças: Whisper e mlx-whisper (MIT), Kokoro (Apache 2.0), KeyboardShortcuts (MIT), espeak-ng (GPL-3, instalado à parte pelo Homebrew).
