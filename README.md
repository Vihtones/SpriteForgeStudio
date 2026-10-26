# Sprite Forge Studio 0.75

## Estado vigente

Editor offline em Godot 4.7.2 para Windows. O marco 0.75 reúne máscaras binárias de visibilidade por camada/cel, criação de telas retangulares, prévia de sequências de clips e exportação/reimportação de sequências PNG com timing e proveniência. Consulte `docs/STATUS.md` e `docs/VALIDACAO-0.75.md`. O produto continua em desenvolvimento; esta entrega não representa conclusão integral do Documento Mestre.

Para instalar para o usuário atual, extraia o pacote Windows e execute `Instalar-SpriteForgeStudio.cmd`. Instruções de instalação, remoção e modo portátil: `docs/INSTALL-WINDOWS.md`.

O produto ainda está em desenvolvimento: o HyperLearn pode classificar um candidato após cumprir critérios estatísticos, mas não aprova arte final nem substitui revisão anatômica humana; partes do Documento Mestre permanecem pendentes. Esta versão do projeto-fonte não representa conclusão integral nem progresso de 100%.

**Acompanhamento:** os 55% informados anteriormente eram uma estimativa manual, sem cálculo ponderado dos requisitos, e não devem ser tratados como medição atual de aceite. A entrega avança por fluxos verificados; o próximo marco está em `docs/OBJETIVO-FINAL.md`. As lacunas principais continuam sendo produção local integrada, geração/anatomia confiável, HyperLearn com evidência suficiente para autonomia e validação prolongada em Windows.

**Prévia de sequência no Animation Studio:** no fonte atual da linha 0.74, **Prévia de sequência…** permite adicionar, ordenar e repetir clips para revisar cortes entre movimentos. Cada entrada toca uma vez com suas durações originais; Play/Pause, velocidade, reverso e direção funcionam na timeline existente. A lista é temporária e não gera poses de ligação nem é exportada. Consulte `docs/VALIDACAO-0.74.md`.

**Sequência PNG:** em **Exportar…**, escolha **Sequência PNG + timing JSON**. O sexto perfil grava cada quadro composto em `frames/<direção>/frame_0000.png`, com hash, pivô, âncoras, eventos e hitbox em `sequence.json`; clips preservam sua ordem e duração própria por quadro. O worker publica e verifica todos os arquivos, e corrupção invalida o cache. O projeto SFS e o perfil modular continuam preservando as layers editáveis.

**Reimportar sequência:** no Pixel Studio, **Importar sequência PNG…** abre o `sequence.json` em uma nova aba candidata, com pixels, clips, timing, pivôs, âncoras, eventos e guias do rig. PNGs modificados externamente exigem confirmação e registram os hashes anteriores/atuais. A importação é composta em uma layer e não recupera as partes originais, Art Lock ou aprovações; use o SFS original para essa estrutura.

**Máscara da camada:** selecione uma região local e use **Ocultar seleção**, **Revelar seleção** ou **Remover máscara da cel**. A máscara pertence somente à layer/direção/quadro atual, preserva o raster original, respeita proteção/Art Lock e tem Undo/Redo. É binária, sem tons de cinza; edição da máscara requer rotação/deslocamento neutros. A prévia acompanha a pose; bake de pose e síntese raster em camada mascarada são recusados. Projetos com máscara usam schema 4 para impedir leitura incorreta por editores antigos; sem máscara, o schema 3 permanece disponível.

**3D Motion Studio:** use a aba dedicada para ajustar o manequim ou importar um GLB autocontido, mapear ossos e editar poses-chave. **Salvar receita…** guarda num `.sfsrecipe.json` a paleta, a direção de arte, os clips/eventos, poses, proporções, encaixes, passes e o modelo GLB incorporado. **Aplicar receita…** restaura essa configuração em uma única operação Undo, valida o modelo e requer canvas/quantidade de quadros compatíveis. A receita não contém os pixels capturados nem aprova arte. Encaixe uma arma ou escudo rígido próprio ou use a peça demonstrativa; a captura modular cria Corpo/Escudo/Arma em layers editáveis e recapturas preservam retoques por pixel quando possível. **Capturar todos os clips** confere limites de resolução, memória, quantidade de frames e layers antes de iniciar; estima a carga, mostra o andamento e permite cancelar após o clip atual. O lote aguarda a confirmação de recuperação após cada clip; uma nova execução pula apenas clips completos cujas poses, paleta, rig, equipamentos, modelo e passes não mudaram. Os resultados permanecem candidatos e exigem revisão humana. Capturar todos os passes pode exigir até 32 renders por quadro. As operações geométricas são locais. Consulte `docs/STATUS.md` para o estado atual.

O manequim tem nove articulações, incluindo cotovelos/joelhos. GLBs skinned podem usar vínculos manuais de um eixo por articulação. Equipamentos GLB são apenas rígidos, com até 4 MiB por peça e encaixe manual em um dos dois slots. Atlas externos oferecem 8/16/32 vistas ou ângulos personalizados; o documento raster mantém oito direções. Clips capturados comportam 1–8 quadros por clip, e o lote verifica todos antes de começar. IK, anatomia semântica, armaduras deformáveis, criaturas prontas e reprojeção semântica de retoques permanecem pendentes; os cels exigem revisão humana.

**Exportação por lote:** a versão 0.38 publica a árvore completa de recursos, incluindo salas adicionais, `rooms.json` e scripts de execução. O manifesto registra hashes de todos os arquivos; cache corrompido invalida e reconstrói a saída, e falhas de publicação restauram arquivos anteriores. O consumidor Godot limpo passa a validar mapas de várias salas.

**Biblioteca direcional:** quatro folhas licenciadas Universal LPC de idle, caminhada, corte e pulo estão offline. O importador mapeia suas quatro linhas para N/W/S/E sem preencher diagonais; a direção visual LPC fica separada da Sentinela. Veja `docs/BIBLIOTECA-PUBLICA.md` e `docs/VALIDACAO-0.43.md`.

**Interpolação do rig:** no painel de articulações, interpolar poses preenche rotações, offsets de equipamento e posições de âncoras entre chaves existentes no clip selecionado. A prévia requer confirmação, preserva quadros-chave e pixels, respeita o menor arco angular e aceita Undo em uma operação. Não deforma um corpo inteiro nem retargeta rigs incompatíveis. Veja `docs/VALIDACAO-0.44.md`.

**Retarget por segmentos:** associe cada camada raster a um osso; o pivô acompanha a raiz do segmento. Transfira orientação entre quadros e projetos SFS da mesma família, mesmo com nomes/topologias diferentes, mapeando camadas por chave explícita e segmentos próprios. A comparação usa a composição real e exige confirmação; pixels e âncoras não são copiados, e Undo reverte o destino. Incompatibilidades e proporções fora do intervalo seguro são recusadas. Consulte `docs/RETARGET-SEGMENTADO.md` e `docs/VALIDACAO-0.47.md`.

**Rasterização de pose:** converta o giro/offset da camada ativa em pixels editáveis apenas no frame atual. A interface mostra a cel fonte e o raster resultante antes de aplicar; composição e opacidade permanecem iguais, a layer continua separada e Undo/Redo restaura rig e raster. Art Lock, bloqueios e cels com máscara protegida ambígua impedem a operação. Consulte `docs/VALIDACAO-0.48.md`.

**Quadros raster intermediários:** entre duas poses-chave do mesmo clip e direção, gere cels editáveis nos frames existentes ou insira novos frames entre chaves adjacentes. A opção **Ajustar escala das partes ao comprimento do osso** faz uma deformação uniforme de vizinho mais próximo (0,5×–2×) em camadas anatômicas já mapeadas; equipamentos permanecem rígidos. A operação preserva cores originais, oferece folha de contato, respeita Art Lock/máscaras/bloqueios e tem Undo. Não funde contornos da pose destino, não deforma articulações internamente nem avalia anatomia, volume, mãos ou contatos. Todo resultado exige revisão. Consulte `docs/VALIDACAO-0.57.md`.

**Formas do Pixel Studio:** retângulos vazados/preenchidos e elipses vazadas/preenchidas, com prévia no canvas. As bordas podem usar a espessura configurada; as formas respeitam espelho, seleção e pixels protegidos, e cada gesto é reversível em uma ação. Atalhos novos: U (retângulo preenchido), Q (elipse) e J (elipse preenchida). Consulte `docs/VALIDACAO-0.50.md`.

**Composição de vilarejo:** o layout determinístico agora usa papéis de tiles selecionáveis para solo, caminho, praça, construção e vegetação. Casas recebem tiles visíveis e colisão com uma entrada livre; a interface controla a seed, mostra o limite de placeholder e mantém Undo. Consulte `docs/VALIDACAO-0.51.md`.

**Limpeza revisável de clusters:** em Pixel Studio, **Revisar clusters pequenos…** encontra pequenos componentes opacos conectados na cel ativa, gera uma comparação antes/depois e só edita após confirmação. O limite ajustável é de 1 a 64 pixels. Respeita a seleção e a máscara protegida por componente, bloqueia camadas e Art Lock, invalida propostas obsoletas e preserva Undo/Redo e aprovações. Conectividade/tamanho são critérios geométricos, não uma avaliação artística: confira cada proposta visualmente. Consulte `docs/VALIDACAO-0.52.md`.

**Rampas de material:** **Criar rampa de material…** pede nome, cores existentes para sombra/base/luz e quantidade ímpar de tons (3/5/7/9). Mostra uma comparação ampliada e salva a rampa junto à paleta apenas após confirmação. Os swatches mostram seus materiais nos tooltips. A rampa não repinta os pixels existentes; selecione seus tons no pincel para pintar. Ver `docs/VALIDACAO-0.53.md`.

**Recolorir com rampa:** **Recolorir região com rampa…** troca uma cor-fonte pela cor de destino de um material salvo. Pode agir em todos os pixels da cor na seleção/máscara ou apenas no componente conectado a uma coordenada. Mostra antes/depois, preserva alfa e exige confirmação; Undo restaura a arte e as aprovações. O operador escolhe a cor-fonte e o escopo; o programa não tenta adivinhar qual material está desenhado. Ver `docs/VALIDACAO-0.54.md`.

**Preparar partes para rig:** **Extrair região em camada de rig…** cria uma camada a partir da seleção ou de uma componente opaca conectada, nomeia a parte e permite associá-la a um segmento existente. Opacidade, ordem e alinhamento são preservados; a comparação é obrigatória e Undo restaura toda a extração. Rotação ativa precisa ser rasterizada antes. O programa não infere qual região é braço, perna ou torso. Ver `docs/VALIDACAO-0.55.md`.

**Inserir novos quadros de movimento:** **Inserir e gerar novos quadros…** insere até oito cels raster na timeline entre poses adjacentes, distribui a duração original entre pose inicial, novas cels e pose final, remapeia outros clips, eventos e máscaras, e exige comparação antes da confirmação. A operação inteira tem Undo/Redo; os novos cels são exportáveis e editáveis. A geração articula rigidamente camadas que o operador já mapeou ao rig: não deforma anatomia nem valida por si só os membros ou contatos. Ver `docs/VALIDACAO-0.56.md`.

**Auditoria de escopo:** veja `docs/AUDITORIA-MESTRE.md` para o resultado objetivo das versões 0.39–0.42, os 17 módulos, as lacunas prioritárias e a dependência artística congelada da Sentinela.

Validação: `docs/VALIDACAO-0.59.md`. O objetivo completo continua em desenvolvimento; 0.59 é um pacote portátil funcional, não o aceite final.

**Biblioteca pública** inclui busca, procedência, três atlas Kenney CC0 e 18 folhas de sprites offline com atribuição; a documentação lista escopo, licença e limites de aplicação. Importações gravam origem e configurações junto ao Undo. Ainda não é uma biblioteca integral nem uma substituição aprovada da direção de arte mestre. Ver `docs/BIBLIOTECA-PUBLICA.md`.

**Geração local:** as tentativas SD1.5/DreamShaper foram reprovadas para a direção artística. O runtime permanece como experimento manual, sem geração automática. O fluxo recomendado prioriza código, edição e composição de recursos curados. HyperLearn registra preferências, mas não treina pesos generativos nem entende anatomia.

**Sentinela v10:** candidata sem aprovação global; sete direções continuam dependentes de fonte artística externa. O trabalho nesse item está congelado até existir uma fonte ou capacidade nova que permita resolver a arte. Os estados aprovados da v9 não são herdados automaticamente.

## Geração de imagens local

O HyperLearn Lab conserva o adaptador local experimental, cuja qualidade artística foi reprovada. A instalação de pesos descrita em `docs/LOCAL-AI.md` é opcional e não é necessária para a biblioteca, o editor ou as animações.

Editor offline de pixel art e preparação de recursos Godot 4.7.2. A versão 0.31 oferece redimensionamento proporcional e uma variante 64×64 gerada pelo editor. A versão 0.29 testa a reprodução real das 24 faixas: idle avança e repete; pulo/ataque avançam até o último quadro e encerram em todas as direções. A versão 0.28 corrige vazamento de pixels entre células no candidato de animação, mantendo somente o componente conectado da figura e uma margem para antialias. Testes agora verificam componentes isolados e recorte do canvas nas 144 cels. A versão 0.27 integra uma demonstração editável de três animações em oito direções (144 cels) e testes que carregam o projeto SFS, verificam proveniência das aprovações delimitadas, reproduzem as 24 faixas e exportam uma cena Godot. Só o ataque N (seis poses) e o terceiro quadro do ataque S têm aprovação humana; idle, pulo e o conjunto completo continuam em revisão. A versão 0.26 adiciona importação determinística de spritesheets: recorte por célula com margens/espaçamento e aplicação à direção ativa ou às oito direções, com validação de tamanho e undo em uma operação. A versão 0.25 acrescenta timeline visual por camada com miniaturas, duração, eventos e hitboxes; a casca de cebola mostra os frames vizinhos da sequência do clip. A versão 0.24 corrigiu o estado de aprovação artística exibido na revisão de personagem. A versão 0.23 registra a reprovação humana da arte da Sentinela e impede que ela seja aprovada como personagem. Ela é mantida somente como fixture técnica. A versão 0.22 conectou idle, caminhada, pulo e ataque à prévia jogável do World Studio; a 0.21 acrescentou um portão técnico de animação com aprovação humana; a 0.20 corrigiu hitboxes direcionais; a 0.19 acrescentou equipamento modular; a 0.18, caminhada nas oito direções; a 0.17 iniciou a prova. A versão 0.16 acrescenta um painel opcional de geração de imagem, com aprovação individual por chamada, mantendo a edição principal offline. As 83 seções e marcos do Documento Mestre estão acompanhados em `docs/ETAPAS-MESTRE.md`; `docs/REQUISITOS-MESTRE.json` preserva o texto e o hash da fonte. Resultados desta rodada: `docs/VALIDACAO-0.31.md`.

## Demonstrações integradas — 0.31

Clique em **Demo animada** para abrir a origem 208×208; **Estudo 64×64** abre uma cópia reduzida pelo próprio redimensionador do editor, no tamanho-base provisório da Bíblia de Arte. A versão reduzida preserva idle, pulo, ataque e oito direções, mas reinicia todas as aprovações para revisão nova. O exame de escala encontra mediana de 40 px para a altura do personagem.

Abra o aplicativo e clique em **Demo animada** no topo. O projeto editável carrega três clips de seis quadros (idle respirando, pulo e ataque), com oito direções, na área de trabalho normal. Play/Pause, timeline e troca de direção usam os controles do editor; a cena de prévia também fica disponível em `examples/animation_candidate_v6/preview.tscn`. Esse arquivo é uma demonstração candidata para avaliação artística, não arte final aprovada: apenas as seis poses do ataque Norte e a terceira pose do ataque Sul têm aprovação humana registrada.

## Fixture técnico de animação — arte reprovada

O fixture inicial em `examples/animation_proof/` permanece reprovado como arte final. Isso não descreve a coleção histórica v9 posteriormente validada nem concede aprovação à correção v10. As folhas experimentais v6 são mantidas como histórico técnico.

Abra `examples/animation_proof/sentinela.sfs.json` somente para testar o fluxo técnico: carrega 4 clips e 8 direções, exporta recursos e alimenta a prévia jogável. O usuário reprovou esta arte por não parecer humana e por ter membros/roupas incoerentes. A aplicação registra esse feedback, exibe o aviso no World Studio e bloqueia sua aprovação como personagem. `technical_preview_rejected.gif` também é uma demonstração técnica reprovada, não o resultado visual solicitado.

Na versão 0.20, a hitbox do frame ativo de ataque passou a ser derivada dos pixels opacos da espada por direção e verificada contra o cel exportado. O painel Qualidade executa o portão técnico de `idle_breathing`, `jump` e `attack` nas oito direções, incluindo tempos, eventos e hitboxes. A ação de aprovar um personagem executa o portão novamente, guarda a evidência técnica junto à versão aprovada e ainda exige identificação, notas e confirmação explícita de uma pessoa. Passar nos testes não concede aprovação artística.

## Prévia jogável — 0.22

Na aba Mapa e prévia, ligue **Prévia jogável** e dê foco ao mapa. Use WASD ou setas para se mover, Espaço para pular, J ou clique esquerdo para atacar e E para usar uma porta próxima. Sem movimento, o personagem respira em `idle_breathing`. Pulo e ataque tocam uma vez e voltam ao idle; o pulo desenha um arco visual e o ataque mostra a hitbox direcional no frame de contato. A animação de teste não altera o frame nem o clip selecionado no editor. A física de movimento permanece simples e não substitui controlador de jogo ou balanceamento de combate.

## Câmera por sala — 0.14

Em Câmera Pixel configure zoom inteiro, suavização e snap de pixels por sala. A prévia jogável acompanha o personagem; ao exportar, `character.tscn` inclui uma `Camera2D` com limites da sala e um controlador que arredonda a posição da câmera para pixels físicos. Em portais entre salas, o controlador recebe os limites e o zoom da cena destino. O pacote mantém o snap 2D habilitado; projetos consumidores podem ajustar esse comportamento nas configurações globais de renderização.

As luzes configuradas no mapa são exportadas como `PointLight2D`, com cor, raio, energia e sombras. Colisões geram oclusores de sombra reais. A prévia do editor ainda desenha a luz como uma aproximação e não substitui a revisão de iluminação no jogo final.

## Luz ambiente por sala — 0.15

Escolha o tom global e aplique-o à sala no inspetor do World Studio. O tom é salvo, entra no Undo, aparece na prévia e exporta como `CanvasModulate`; as luzes pontuais exportam como `PointLight2D`. O teste consumidor confirma que o tom da sala de destino carrega junto à transição. Os halos da prévia continuam aproximados e a direção visual ainda precisa de aprovação artística.

## Salas de World Studio — 0.11

O painel Salas cria até 32 ambientes separados no mesmo projeto. Cada sala mantém dimensões, camadas, terrenos, colisões, portas locais e luzes. Trocar de sala conserva a edição; renomear, remover e trocar de sala participam do Undo. O salvamento registra o conjunto completo e contabiliza os buffers das salas na estimativa de memória.

Exportar gera `rooms.json`, `map.tscn` para a sala ativa e uma cena `rooms/<id>/map.tscn` para cada outra sala, cada uma com tileset próprio. A geração, a indexação e o carregamento das cenas foram testados. Portais entre salas e transição de cena estão descritos na seção 0.12 abaixo.

## Portas entre salas — 0.12

Na ferramenta Porta, marque uma célula de entrada, selecione outra sala no painel e marque a saída. As ligações ficam no projeto com IDs estáveis, são editáveis/removíveis e atualizam a análise de navegação global. A prévia troca de sala com E. A exportação inclui `rooms.json`, as conexões, os scripts de interação e cada `Area2D` com a cena de destino.

No Godot exportado, aproxime um `CharacterBody2D` na collision layer 1 e pressione E. Um controlador persistente retira o personagem da cena antiga, carrega a sala destino, reinsere o personagem e aplica a posição de chegada. Um teste consumidor limpo confirmou a mudança de `PackedScene` e a preservação do ator.

O projeto agora fornece plumbing para construir interiores conectados. Ele ainda não gera vila, casas ou decoração automaticamente e não contém o vilarejo artístico final do documento.

## Layout procedural — 0.13

Na aba Mapa e prévia, escolha uma seed e clique **Gerar layout**. O gerador cria ruas ortogonais conectadas, praça, pequenos espaços verdes, lotes e casas com entradas; colisões e tiles persistem na sala e são exportados pelo fluxo normal. A mesma seed e as mesmas dimensões reproduzem o mesmo layout. O gerador não desenha fachadas ou decoração e não toma decisões semânticas sobre biomas. Use um tileset de pelo menos três tiles na ordem solo, caminho e praça; a geração substitui a sala ativa e pode ser desfeita.

## World Connections — 0.10

No modo Porta, clique em duas células livres para criar uma conexão bidirecional entre exterior e interior. Edite o nome antes da próxima conexão; o mapa exibe os dois lados e a lista permite remover o vínculo. A análise de navegação considera as passagens. Na prévia, aproxime o personagem e pressione E para atravessar.

Na exportação, cada lado vira uma `Area2D` com colisão, metadata e o script `examples/export/doorway.gd`. O script procura um `CharacterBody2D` na camada de colisão 1 e transfere sua posição ao pressionar E. Pinte paredes e coloque os pares de portas em corredores livres para criar áreas interiores acessíveis.

Cada mapa exportado pode ser organizado como uma sala independente desde a versão 0.11. Portas agora ligam salas e trocam cenas. A versão 0.13 adiciona um gerador topológico básico; a arte final do mestre segue pendente.

## Anatomy & Rig — 0.9

O overlay mostra 15 pontos articulares e 13 segmentos de referência. Escolha a articulação na lateral e use a ferramenta Âncora para posicioná-la; pontos podem variar por direção e frame. Use `+ Articulação` para pontos próprios. Camadas modulares podem usar qualquer articulação como pivô e receber rotação rígida pelo controle de ângulo. Equipamentos também mantêm âncora, offset e profundidade por pose. A rotação não altera os pixels fonte; a composição usa vizinho mais próximo e é gravada no spritesheet exportado. O rig não deforma malhas nem interpola movimento.

## Produção automática — 0.5

Na aba Automação, escolha uma pasta de projetos `.sfs.json` e outra pasta de saída, separada da entrada. Clique Aplicar e iniciar. Arquivos estáveis são admitidos uma vez por conteúdo/perfil/destino; cada execução tem uma subpasta própria. O programa prepara `candidate.sfs.json`, inspeciona todas as cels, valida contratos, exporta para `export/`, carrega as cenas produzidas e registra `production-report.json`. Os originais permanecem intactos.

Ajustar pixels à paleta é opcional, desmarcado inicialmente, e atua nas cópias respeitando camadas bloqueadas e pixels protegidos. Candidatos alterados recebem nova identidade e perdem as aprovações herdadas. Exigir arte não vazia impede exportar composições inteiramente transparentes. O relatório contém métricas técnicas; não concede aprovação artística.

Retomar ao abrir o programa reativa monitoramento e fila persistida. Pausar automação e fila interrompe novas admissões; o worker atual termina, podendo ser cancelado em Lotes. Falha de processo sem relatório válido tem até três tentativas com intervalo crescente; erro de validação exige correção ou repetição manual. Repetir falhas reinicia o orçamento de tentativas. Esquecer registros finalizados permite reprocessá-los; o cache continua verificando a integridade das saídas.

O monitor considera somente arquivos no primeiro nível da pasta, até 64 MiB por arquivo e 2.048 registros de automação/256 tarefas na fila. Não trabalha com edições ainda não salvas. Precisa permanecer aberto; não instala serviço nem agenda no Windows. Também pode operar sem janela pelos comandos documentados em `docs/AUTOMACAO.md`. Não interpreta pedidos artísticos nem gera novos desenhos a partir de texto.

## World Studio — 0.6

Mapas aceitam 1–128 células por dimensão. A camada Solo continua como base e até sete adicionais podem ser reordenadas, ocultadas, bloqueadas para tiles/terreno e ajustadas por opacidade. Use lápis, balde e retângulo para tiles, terrenos ou colisões; botão direito apaga.

Crie terrenos a partir de 16 tiles consecutivos. Máscaras N=1, E=2, S=4 e W=8 escolhem as variantes, e a pintura atualiza vizinhos. Reduzir um mapa mostra confirmação; Undo recupera o recorte. A prévia e a navegação usam as dimensões escolhidas.

A exportação cria um TileMapLayer por camada e conserva ordem, visibilidade, opacidade, colisões e navegação. Cada luz guarda cor, energia, raio e sombras; colisões viram oclusores reais quando sombras estão habilitadas. A cena foi executada em projeto consumidor limpo.

O formato de projeto ampliado é schema 3. Projetos schemas 1 e 2 continuam abrindo.

## Novidades do editor — 0.4

Novo e Abrir criam abas independentes. Ctrl+Tab alterna; Ctrl+W fecha com opção de salvar, descartar ou cancelar. Salvar todos percorre os documentos e pede destino para os sem título. Cancelar interrompe a sequência. Copiar/colar pixels funciona entre abas; zoom, posição do canvas, direção e frame ficam por documento. Histórico lista ações de undo; Enquadrar ajusta a arte ao canvas.

Salvar, autosave e preparar snapshot para exportação codificam PNG/JSON em uma thread auxiliar. A cópia inicial dos buffers permanece na interface e pode causar pausa breve em documentos grandes. Alterações feitas enquanto uma versão é gravada continuam marcadas como pendentes. Recuperar sessão restaura os últimos checkpoints concluídos, a cada 30 segundos, sem substituir abas já abertas. Backups `.bak` preservam a gravação anterior; histórico undo não é recuperado.

Play usa duração por frame e acumula tempo residual; pequenos atrasos avançam os frames devidos. Pintar, buscar um frame ou mudar de aba pausa a animação e cancela gestos pendentes. Equipamentos com âncora/offset usam coordenadas locais para pintura e seleção e coordenadas do documento para hitboxes. Mapas e banco de referências carregam seus caches quando o painel é aberto.

Limites: oito documentos e 256 MiB de buffers RGBA abertos, com teto de 64 MiB por documento. Histórico, texturas e snapshots consomem memória adicional. São documentos separados; a biblioteca com múltiplos sprites dentro de um único projeto ainda não existe. Ver `docs/STATUS.md` e `docs/ETAPAS-MESTRE.md` para as lacunas do escopo integral.

## Acervo de referência preservado — 0.3

O painel Acervo Arton inclui cópias verificadas de 32 PNGs: oito vistas de cada base humanoide, canídea e felina, mais oito vistas de um colete separado. Ler catálogo → escolher família → Importar base + peças compatíveis inicia um worker. Em Lotes, selecione a tarefa concluída e clique Abrir importação. Os projetos prontos também estão em `examples/arton_projects/` no código-fonte.

Bases preservam RGBA e resolução 256×256. Oito direções são um único frame estático. Colete começa oculto e usa a calibração pescoço/bainha do catálogo, com offsets por direção/frame. Morfologia, pose e versão de rig são verificadas além da família. A calibração da roupa é quantizada em pixels e permanece candidata, sem aprovação automática. Detalhes e limites em `docs/ACERVO-ARTON.md`.

O adaptador atende a biblioteca `12_sistema_modular/godot_previa/biblioteca.json`, não todas as bibliotecas históricas. Os projetos de equipamentos v1–v7 têm outros contratos, poses/rotações e corpos vestidos; não foram convertidos automaticamente em peças modulares independentes. Nenhum script ou finalizador do acervo foi executado.

**Ainda não é o produto profissional completo descrito no documento.** Há ferramentas executáveis e testes reais; geração de imagem remota é opcional e parcial, enquanto anatomia automática, rigs ósseos e os casos artísticos finais não estão implementados. Não há áudio. Nenhuma chamada paga foi feita durante o desenvolvimento.

## Instalar e abrir

Extraia o ZIP Windows e abra `SpriteForgeStudio.exe`. Mantenha `SpriteForgeStudio.pck` ao lado. O editor e as exportações funcionam sem internet, chaves, Python ou instalação separada de Godot. O pacote é portátil e usa o executável oficial de editor Godot 4.7.2 com o PCK do aplicativo, não um release enxuto ou instalador assinado.

Para desenvolver, importe `project.godot` no Godot 4.7.2 e pressione F5. Código de domínio em `core/`, interface em `ui/`, serviço opcional em `services/`, testes em `tests/`. Nenhuma skill externa é necessária para executar o software.

## Fluxo de edição

1. Edite a demonstração ou clique Novo. Documentos têm oito direções e cels independentes por camada/frame. A ordem agora é **N, NE, E, SE, S, SW, W, NW**. Arquivos schema 1 são migrados preservando orientação e índices de tiles.
2. Use lápis, borracha, balde, linha, retângulo e conta-gotas. Direito apaga. Scroll aproxima; botão central move. A Máscara é seleção retangular transitória.
3. Copiar/Colar, Virar H/V, Girar 90° e setas transformam a região selecionada da cel atual; sem seleção, usam a cel inteira. Rotação exige região quadrada. Não há interpolação. Deslocar para fora da imagem recorta pixels: use Undo para recuperar.
4. Proteger região marca pixels que não podem ser pintados ou quantizados. Transformações que tocam pixels protegidos são recusadas. Desproteger cel remove a proteção desse frame/direção. A proteção é persistente.
5. Camadas permitem nome (Enter), ordem, visibilidade, bloqueio e opacidade. O painel lateral tem rolagem. Equipamentos usam coordenadas locais, âncora e offset; desenhe o item perto de (0,0). A ferramenta Âncora registra posição **por direção e frame**, com fallback aos pontos globais.
6. Escolha a família anatômica e registre manualmente a adaptação do equipamento. Equipamentos incompatíveis ficam ocultos e bloqueiam exportação. Isso verifica metadados, não prova qualidade do encaixe. Profundidade pode variar por frame/direção; a camada assimétrica recusa espelhamento automático.
7. Crie clips nomeados sobre intervalos de frames existentes. A timeline abaixo do canvas mostra miniaturas por camada, duração em ms, eventos e hitboxes; clique em qualquer célula para mudar de frame. Duplique/remova frames, ajuste FPS, Loop, Reverso e velocidade. Play/Pause, Stop e frame a frame operam no clip ativo. A casca de cebola colore o frame anterior em magenta e o seguinte em ciano.
8. Hitbox = máscara registra um retângulo por direção/frame. Evento aceita um nome por linha. Os dados são exportados; não executam regras de dano ou lógica de jogo automaticamente.
9. Revisar correção pela paleta cria uma proposta antes/depois, preservando máscara e pixels protegidos. Aceitar aplica uma alteração reversível; rejeitar não muda a arte. Uma proposta desatualizada é recusada.

## Referências e direção artística

Importe PNG, preencha procedência e licença. O original e uma thumbnail são incorporados ao projeto, com limite agregado de 16 MiB de dados base64 de originais. Referências idênticas são deduplicadas pelo hash. Caminhos antigos são metadados; referências novas continuam disponíveis mesmo se o arquivo original for movido.

Estados: imported, analyzed, review, approved, partial, archived, rejected. Escolha uma característica (palette, lighting, anatomy, materials) e aplique o estado. Aprovação parcial só torna a característica escolhida elegível. Vincular referência aprovada registra dependência. Rejeitar mantém o histórico, invalida regras derivadas e sinaliza dependentes; Arquivar retira da recuperação ativa.

Art Bible é texto versionado. Art Lock congela sua edição, referências e aprovações de paleta. Não equivale a restrições semânticas completas por recurso nem impede toda pintura manual.

HyperLearn Lab guarda aprovação/reprovação explícita com hash SHA-256 do projeto, revisão, observação e prancha de contato de todas as direções/frames (`user://hyperlearn/`). O classificador logístico local aprende sinais raster simples; treino e validação cruzada agrupam versões pelo ID do projeto. Esses sinais não reconhecem anatomia. A aprovação do usuário desta conversa tornou-se o primeiro exemplo positivo; faltam muitas aprovações e reprovações independentes, então autonomia permanece bloqueada.

Geração local nativa usa `stable-diffusion.cpp` com backend Vulkan e escreve PNGs em `user://hyperlearn/generated/`. O runtime vai ao lado do executável e os modelos opcionais ficam na pasta de dados do usuário. Nenhuma API paga é chamada. O gerador não substitui revisão artística humana e não treina pesos de difusão; detalhes e limites estão em `docs/LOCAL-AI.md`.

## Qualidade e versões

O painel mostra cores fora da paleta, pixels isolados e alfa parcial como sugestões. Não avalia automaticamente anatomia, fluidez ou intenção artística.

O revisor atribui quatro notas com pesos 35/25/25/15. Registrar versão aprovada exige nota geral ≥85, cada critério ≥75, integridade estrutural, identificação e confirmação humana. A versão é preservada em `user://approved_library/`, separada do cache. Compare pixels antes/depois ou restaure uma versão como documento sem título. Notas não são preenchidas automaticamente.

## Mapa e prévia

Mapa 1–128 × 1–128. Solo mais sete overlays. Importe tileset PNG com tiles 16×16 até 256×256. Sem tileset dedicado, as cels servem de tiles. Importar substitui tiles e limpa pintura de todas as camadas e terrenos; Undo reverte.

Pinte tiles, terrenos conectados por N/E/S/W, colisões e luzes com lápis, balde ou retângulo. Redimensionar pode recortar; Undo restaura. Checar caminhos analisa o tamanho real. Prévia usa colisões. Luz no canvas é ilustrativa; a cena exportada tem PointLight2D e oclusores configuráveis.

## Salvar e recuperar

Ctrl+S salva, Ctrl+Z desfaz, Ctrl+Y refaz. `.sfs.json` schema 3 inclui mapas em camadas. Schemas 1 e 2 continuam legíveis; PNGs artísticos não são recodificados com perda.

Gravações usam arquivo temporário e backup `.bak`. Em falha entre renomeações, abra o backup pelo filtro JSON. O histórico de edição é volátil; versões aprovadas persistem separadamente. Dados ficam em `%APPDATA%/Godot/app_userdata/Sprite Forge Studio/`.

Limites: buffers de documento até 64 MiB, dimensões até 512×512, 16 camadas e 32 frames sujeitos ao teto agregado; até 32 clips. O histórico contabiliza buffers dos snapshots com teto de 32 MiB, mantendo no mínimo um snapshot. Texturas, referências, JSON e outras cópias consomem memória adicional. Arquivos JSON acima de 64 MiB são recusados, inclusive antes de substituir um arquivo salvo.

## Exportar e processar lotes

Exportar pacote cria um snapshot do documento atual e coloca uma tarefa de prioridade alta na fila. Acompanhe em Lotes. O processamento pesado ocorre em outro processo Godot; falhas não alteram os pixels em edição. Serialização do snapshot e autosave ainda ocorrem na interface e podem causar pausa em documentos grandes.

Lotes aceita projetos salvos, pasta exclusiva de saída e prioridade. O backend suporta dependências e bloqueia ciclos, falta de dependências, excesso de tentativas e memória estimada acima do orçamento. Um worker de exportação por vez; o teto de admissão padrão é 1 GiB estimado, não um monitor rígido do consumo real de processos/VRAM.

Pausa impede a próxima tarefa; cancelar é cooperativo entre etapas. Fechar o editor interrompe o worker e deixa a tarefa pendente para retomada explícita. Checkpoints são gravados antes/depois das etapas. A saída é preparada em staging, validada e publicada com backups por arquivo; o manifesto é escrito por último. Não é transação atômica do pacote inteiro. Uma interrupção durante publicação pode deixar arquivos misturados; repetir a tarefa recompõe o pacote.

Cache SHA-256 considera o projeto completo (incluindo Bible e dependências), versão do exportador e integridade das **sete** saídas. Cache não é biblioteca aprovada. Lotes substitui nomes fixos na pasta escolhida; tarefas distintas devem usar pastas exclusivas.

| Saída | Conteúdo |
| --- | --- |
| frame.png | Composição atual RGBA |
| spritesheet.png | Frames nas colunas; oito direções nas linhas |
| metadata.json | Frames, direções, rig, clips, eventos, hitboxes, mapa e manifesto |
| character.tscn | AnimatedSprite2D com clips `nome_N`, `nome_NE` etc., durações e loop |
| animations.tres | SpriteFrames independente |
| map.tscn | TileMapLayer, colisões StaticBody2D, NavigationRegion2D e luzes |
| tileset.tres | TileSet independente, células de 24 unidades |

As cenas embutem recursos para transporte. Não incluem controlador jogável ou execução dos eventos/hitboxes exportados. A prévia jogável pertence ao editor.

## Catálogo SQLite opcional

Em Qualidade e versões, informe um Python **3.11+** existente e clique Atualizar índice SQLite. Nenhuma instalação automática. O cliente inicia um processo auxiliar que usa somente bibliotecas padrão, sem rede. Metadados e dependências são indexados transacionalmente em `user://catalog/catalog.sqlite`; bytes de imagem, thumbnails e credenciais não entram no índice. O índice é reconstruível, não a fonte da arte editável. A configuração do interpretador ainda não é persistida. Sem Python, o restante do editor funciona normalmente.

## IA e integrações

O painel **IA Assistida** pode gerar uma imagem PNG 1024×1024 com GPT Image 2.5 Sunburst ou Flare. Qualidade baixa é o padrão; transparência também. O resultado é uma prévia local que você pode salvar e depois importar como referência ou preparar para pixel art. A integração não modifica o documento ativo.

Cada pedido exige uma confirmação nova que informa o modelo, a qualidade e o fundo. Não existe consentimento persistente nem repetição automática. O clique em **Autorizar uma chamada** pode gerar cobrança. Cancelar ou fechar a confirmação não envia o pedido. Chamadas pagas não foram usadas para desenvolver ou verificar esta versão.

No editor Godot, a chave pode vir de `OPENAI_API_KEY` no ambiente do processo ou de `.env.local` na raiz do workspace. No pacote portátil, configure a variável `OPENAI_API_KEY` no Windows e reinicie o aplicativo. Não cole chaves no código, no prompt ou em capturas de tela. A chave não é embutida no PCK, nos executáveis ou nos arquivos ZIP; os arquivos de ambiente são ignorados pelo controle de versão. Chaves ausentes ou falhas de rede não afetam o editor offline.

O serviço envia uma geração individual em PNG por HTTPS ao endpoint oficial de imagens; a saída é validada e gravada em `user://ai_generated/`. Não há edição de imagem, geração de múltiplas imagens, estimativa ou registro de custo, integração local, nem detecção de compatibilidade de modelos na RX 580. Graphify e Headroom são experimentais e não obrigatórios. As skills GDAS são ferramentas de desenvolvimento, ficam fora do executável e não implementam os 17 módulos internos do produto.

## Verificação e build

`Run-Tests.ps1 -Godot 'C:\caminho\Godot_v4.7.2-stable_win64_console.exe'` roda testes Godot reais, incluindo uma segunda instância de projeto consumidor que executa os arquivos exportados. A fixture do consumidor também valida duas salas conectadas, colisão e luz com sombra. O worker de exportação grava `export-validation.json` e bloqueia a publicação quando uma checagem estrutural falha. Em **Lotes**, selecione a tarefa e use **Ver relatório técnico** para consultar falhas ou abrir o relatório da última exportação; esse relatório comprova integridade técnica, não aprovação artística. Para o teste opcional do catálogo, defina `SFS_TEST_PYTHON` com o caminho de Python. Sem a variável, a suíte verifica o editor sem testar a ponte SQLite.

`python -m unittest discover -s services -p test_catalog.py -v` verifica o catálogo (6 testes). `tests/consumer_project/` contém um consumidor Godot sem código do editor. `tests/export_consumer_tests.gd` gera um demo sintético, exporta os recursos diretamente para a raiz desse projeto e o abre em um processo Godot independente para verificar cena, câmera, reprodução de animação, tileset e caminho de navegação.

`Build-Windows.ps1 -Godot 'C:\caminho\Godot_v4.7.2-stable_win64_console.exe'` gera o pacote portátil e executa o self-check embutido. A suíte do instalador é independente e usa pequenos arquivos de teste: `tests/installer_tests.ps1 -PackagePath 'C:\caminho\Windows'`. Ela confirma antes que o pacote real tem os arquivos obrigatórios, depois exercita instalar, atualizar e remover usando a fixture leve. Templates oficiais correspondentes permitem release convencional com o preset Windows Desktop; não estão instalados neste ambiente. A entrega preserva a versão 0.1 nos ZIPs antigos.

Builds executáveis são agrupados por marco funcional. Mudanças pequenas e correções documentais ficam no código-fonte até que o fluxo principal do marco esteja implementado e os testes relevantes passem; self-check de release, pacote Windows e arquivo de entrega são feitos uma vez ao fechar esse marco.

Veja `docs/ACERVO-ARTON.md`, `test_results/arton-report.json` e `test_results/report.json` para a revisão 0.3. `docs/VALIDACAO-0.2.md` e os probes preservam os resultados históricos medidos na versão 0.2.



