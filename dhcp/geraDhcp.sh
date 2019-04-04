#!/bin/bash
:<<'INFO_INICIAL'
 geraDHCP.sh -
 Manutenção: coris@dtic.unipampa.edu.br
  -------------------------------------------------------------
   Este programa gera as confs do servidor DHCP
  -------------------------------------------------------------

 Atualização: configurada verificacao de local de execucao, permitindo
 que o script seja exetudado de qualquer diretorio caso desejado e 
 corretamente configurado.
INFO_INICIAL

VERSAO=261011.0

:<<'AJUSTE_DA_VERSAO'
 Nessa versao foram alteradas as funcoes statusDhcp e getPid para torna possivel
 a utilizacao do script com versoes anteriores ao ubunto 16.04 onde a forma de 
 retorno das informacoes da execucao do isc-dhcp-server sao diferntes.
AJUSTE_DA_VERSAO

# Funcao principal que inicial a execucao do script
function main(){
        
    # LIMPA RESQUICOOS DE EXECUCAO ANTERIOR
    rm -r $FILE_MACS $FILE_DEBUG *.txt 2> /dev/null

    local aPathAtual=`pwd`

    # Caso o aquivo nao exista ele gera um erro sem importancia
    [ "aPathLocal" != "PATH_SH" ] && mv $1 /root/dhcp 2> /dev/null;

    # Vai para o diretorio de execucao 
    cd /root/dhcp

    # Arquivo de configuracao que contem a inicializacao das variaveis globais
    # utilizadas no sistema
    if [ -s "geraDhcp.conf" ];then
        source ./geraDhcp.conf;
    else 
    	echo -e "\e[31;1m ERRO: ARQUIVO DE CONFIGURACAO FALTADO \e[m" | tee -a $LOG_ERROS
        exit
    fi
        
    # Marca LOG_ERROS:
    echo -e "\e[32;1m `date +%x" "%X`__________________________________________________\e[m" | tee -a $LOG_ERROS
    echo -e "\e[32;1m `date +%x" "%X` -> INICIANDO PROCESSO GERA DHCP ......\e[36;1m V.$VERSAO\e[m" | tee -a $LOG_ERROS
    echo ""
    
    # Verifica se existe, se e arquivo 
    if [ $1 ] && [ -s $1 ]; then
    	echo -e "\e[36;1m `date +%x" "%X` -> UTILIZANDO ARQUIVO PASSADO \n\e[m" | tee -a $LOG_ERROS
        geraDhcp $1
        rm -rf $1 2> /dev/null;
    else
        if [ $1 ]; then
    	    echo -e "\e[31;1m `date +%x" "%X` -> ERRO: ARQUIVO PASSADO INCORRETO \e[m" | tee -a $LOG_ERROS

        fi
    	echo -e "\e[36;1m `date +%x" "%X` -> BUSCANDO ARQUIVO ONLINE \e[m" | tee -a $LOG_ERROS
        aErro=$( getFileMacs );
        
        if [ "$aErro" == "0" ]; then
    	    echo -e "\e[31;1m `date +%x" "%X` -> ERRO:  FALHA AO BAIXAR ARQUIVO ONLINE \n\e[m" | tee -a $LOG_ERROS
        else
    	    echo -e "\e[36;1m `date +%x" "%X` -> UTILIZANDO ARQUIVO ONLINE \n\e[m" | tee -a $LOG_ERROS
            geraDhcp $FILE_MACS
        fi
    fi

    cd - 1> /dev/null
}

# Executa o processo de geração de um novo arquivo e inicialização do dhcp
function geraDhcp(){
    # LIMPA O ARQUIVO DE MACS FREE
    if [ "$SO" == "FreeBSD" ]; then
	# AS OPCOES TESTADAS NAO TRATAM ACENTOS NO FreeBSD
	#iconv -f utf8 -t ascii//TRANSLIT $1 > $1.tmp
	cat $1 > $1.tmp
	cat $1 > SAIDA
        # PRIMEIRO, remove ^M e linhas em branco
	perl -p -e 's/\r//g' $1.tmp | grep \# > $1.sed
    else
	# REMOVE ACENTOS DO ARQUIVOS
    	iconv -f utf8 -t ascii//TRANSLIT $1 -o $1.tmp
        # PRIMEIRO, gera nova saida convertendo CRLF em LF
        sed 's/\x0D$//' $1.tmp > $1.sed
    fi
    

    # GEPOIS gera novo arquivo, apagando linhas invalidas
    sed '/^#/d;/^\s*$/d;s/,//g' $1.sed > $1.tmp
    

    # Seleciona as subredes cadastradas na planilha excluindo valores repetidos
    theSubnets=`cut -d"#" -f1 $1.tmp | uniq`

    # Percorrendo as sub-redes
    for i in $theSubnets
    do
        echo -e "\e[32;1m `date +%x" "%X`  PROCESSANDO SUBREDE $i \e[m"
        # Gerando novos arquivos, filtrando por sub-redes 
        grep -w ^$i $1.tmp | tr -d [:blank:] > $1.tmp.$i 
        
        # Utiliza do $1 para refereciar o nome do arquivo
        formataSubnet $1 

        echo '  ';
        rm -f $1.tmp.$i
    done

    rm -f $1.sed $1.tmp

    # Utiliza do $1 para refereciar o nome do arquivo
    geraFileHosts $1

    # Função que atualiza o dhcp.conf
    # Utiliza do $1 para refereciar o nome do arquivo
    atualizaFileHosts $1

    # Testando se houve erros
    if [ $ERRO -eq 1 ]; then
        echo -e "\e[31;1m ATENCAO: ERROS EM $FILE_HOSTS, CONSULTE "$PATH_DHCP'error.LOG_ERROS'" \e[m"
    fi
    
    reiniciaDhcp
}

# Funcao que recebe como paramentro o nome do arquivo contendo os registros e formata para o 
# padrao do dhcp, gerenado um arquivo temporario para cada subrede. Estas subredes serao 
# separadas posteriormente.
function formataSubnet(){
    local aTmp="";
    local aProx="";
    # Converte o arquivo de macs ($1.tmp.$i) no arquivo padrao do DHCP ($1.dhcp.$i)
    for aLinha in `cat $1.tmp.$i`
    do
        count=$(($count+1))
        local aSubrede=`echo $aLinha | cut -d"#" -f1 | sed 's/ //g'`
        local aNome=`echo $aLinha | cut -d"#" -f2 | sed 's/ //g' | cut -b1-20`
        local aHostName=`echo $aNome | egrep '^([a-zA-Z0-9._-]*)$'` 
        local aIpFinal=`echo $aLinha | sed 's/^[^#]*#[^#]*#\([^#]*\).*$/\1/;s/ //g'`
        local aIp=$aSubrede.$aIpFinal
        local aIpValido=$( ipValido $aIp )
        local aMac=`echo $aLinha | sed 's/^[^#]*#[^#]*#[^#]*#//;s/#/ /g'  | sed 's/^[ \t]*//'`
        local aComentario=`echo $aLinha | cut -d'#' -f6`
        if [ ${#aComentario} -gt 0 ];  then
            aLinha=`echo $aLinha | sed 's/'$aComentario'//g'`
        fi

        # Testando se não existe nome duplicado
        for item in "${LISTA_HOSTNAMES[@]}"; do
            if [ $item = $aHostName ]; then
                aTmpHostName=$aHostName"_"$INDEX
                aHostName=$aTmpHostName
                aMsgHostname="Hostname $item duplicado - ALTERADO PARA"
                echo -e "\e[33;1m -> ATENCAO: "$aMsgHostname": \e[m" | tee -a $LOG_ERROS
                echo -e "\e[37;1m \t [$aHostName - $aIp - $aMac]  \e[m" | tee -a $LOG_ERROS
                INDEX=$(($INDEX+1))
            fi
        done
        LISTA_HOSTNAMES[$count]=$aHostName

        # Testando se todas as variaveis possuem valor
        if [ -z "${aSubrede}"  ] || [ -z "${aHostName}"  ] || [ -z "${aIp}"  ] || [ -z "${aIpFinal}"  ] || [ -z "${aMac}"  ]; then
            ERRO=2
            TIPO_ERRO[2]="HOST COM CAMPOS VAZIOS NAO INCLUIDO"
            echo -e "\e[31;1m -> ATENCAO: "${TIPO_ERRO[$ERRO]}": \e[m" | tee -a $LOG_ERROS
            echo -e "\e[37;1m \t [$aHostName - $aIp - $aMac]  \e[m" | tee -a $LOG_ERROS

        elif [ -z "${aHostName}"  ]; then
            ERRO=3
            TIPO_ERRO[3]="HOSTNAME COM CARACTERES INVALIDOS"
            echo -e "\e[31;1m -> ATENCAO: "${TIPO_ERRO[$ERRO]}": \e[m" | tee -a $LOG_ERROS
            echo -e "\e[37;1m \t [$aHostName - $aIp - $aMac]  \e[m" | tee -a $LOG_ERROS

        elif [ "ipValido"  == "0" ]; then
            ERRO=4
            TIPO_ERRO[4]="HOSTNAME COM IP INVALIDO"
            echo -e "\e[31;1m -> ATENCAO: "${TIPO_ERRO[$ERRO]}": \e[m" | tee -a $LOG_ERROS
            echo -e "\e[37;1m \t [$aHostName - $aIp - $aMac]  \e[m" | tee -a $LOG_ERROS

        else
            for j in `echo $aLinha | sed 's/^[^#]*#[^#]*#[^#]*#//;s/#/ /g'`
            do
                aMacValido=`echo $j | egrep '^([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})$'`
                if [ -z "${aMacValido}"  ]; then
                    ERRO=5
                    TIPO_ERRO[5]="HOSTNAME COM MAC INVALIDO"
                    echo -e "\e[31;1m -> ATENCAO: "${TIPO_ERRO[$ERRO]}": \e[m" | tee -a $LOG_ERROS
                    echo -e "\e[37;1m \t [$aHostName - $aIp - $j]  \e[m" | tee -a $LOG_ERROS
                else
                    aNome=$aHostName$aProx;
                    aMac=`echo $j | tr '[[:lower:]]' '[[:upper:]]'`
                    
                    if [ "$aSubrede" == "0.0.0" ] || [ "$aIpFinal" == "*" ]; then
                        echo -e "\t host $( printf "%-25s" "$aNome" ) { hardware ethernet $j; } # $aComentario" >> $1.dhcp.$i
                    else
                        echo -e "\t host $( printf "%-25s" "$aNome" ) { hardware ethernet $j; fixed-address $aIp; } # $aComentario" >> $1.dhcp.$i
                    fi
                    #echo -e "\t host $aHostName$aProx$aTab { hardware ethernet $j; fixed-address $aIp; } # $aComentario" >> $1.dhcp.$i
                    aProx="_W";
                fi
            done
        fi
        aProx="";
    done
}


# Gera o arquivo hosts.conf. Percorre as redes cadastradas na plainha, gerando o arquivo de configuracao
# de cada rede, utilizando para tal os arquivos de configuração das redes, localizados em /root/dhcp
function geraFileHosts(){

    local aRanges=`ls | grep dhcpd.conf | cut -d'.' -f3,4,5`
    local aFileHosts=$1.dhcpd.conf
    local aAbreRede=0;
    local aFechaRede=0;
    echo "#INICIO" >> $aFileHosts
    # Remove a subrede de 0.0.0 poi não possui configuração
    theSubnets=("${theSubnets/0.0.0}")
    
    for i in $theSubnets
    do
        #Se for um range com arquivo analisa o arquivo
        aAbreRede=`echo "$aRanges" | grep "$i$" | wc -l`

        if [ $aAbreRede -eq 1 ];then
            [ $aFechaRede -eq 0 ] && aFechaRede=1 ||  echo -e "}\n\n" >> $aFileHosts ;
            [ -f dhcpd.conf.$i ] || { echo -e "\e[31;1m -> ATENCAO: ARQUIVO dhcpd.conf.$i NAO ENCONTRADO! \e[m"; exit; }
            cat dhcpd.conf.$i >> $aFileHosts
        fi

        cat $1.dhcp.$i >> $aFileHosts
        echo -e "\n\t #### FIM REDE $i" >> $aFileHosts
        echo -e "\t################################################################################" >> $aFileHosts
            
        rm -f $1.dhcp.$i

    done
    # Fecha a ultima rede
    echo "}" >> $aFileHosts

    # Inclui hosts sem IP
    echo -e "\n############################### HOSTS IP DINAMICO ##############################" >> $aFileHosts
    cat $1.dhcp.0.0.0 >> $aFileHosts 2>/dev/null
    
    echo "#FIM" >> $aFileHosts
}

# Atualiza o arquivo de hosts, realizando backup do arquivo atual e
# gerando um novo arquivo a partir o arquivo temporario originado na
# funcao geraFileHosts
function atualizaFileHosts(){

    echo ""
    echo -e "\e[33;1m FAZENDO BACKUP DO ARQUIVO DE HOSTS EM "$PATH_BKP$FILE_HOSTS'-'$DATA" \e[m"
    [ -d $PATH_BKP ] || { mkdir -p $PATH_BKP; }
    
    # Realiza um backup do arquivo de hosts atuais
    cp $PATH_DHCP$FILE_HOSTS $PATH_BKP$FILE_HOSTS'-'$DATA

    echo -e "\e[33;1m GERANDO ARQUIVO DE HOSTS em "$PATH_DHCP$FILE_HOSTS " \e[m"
    cat $1.dhcpd.conf > $PATH_DHCP$FILE_HOSTS
    
    echo -e "\e[33;1m REMOVENDO OS ARQUIVOS $1.dhcpd.conf $1.dhcp $1.tmp  \e[m"
    rm -f $1.dhcpd.conf $1.dhcp* $1.tmp 
}

function reiniciaDhcp(){
    if [ "$SO" == "FreeBSD" ]; then
	service isc-dhcpd restart 1> /dev/null 2>/dev/null
    else
	service isc-dhcp-server restart 1> /dev/null 2>/dev/null
    fi	
    ### AQUI ESTAVA O CONTEUDO DA FUNCAO TRECHO FINAL REMOVIDO ###
    ### AS LINHAS ABAIXO FORAM ADICIONADAS EM SUBSTITUIÇÃO AO TRECHO REMOVIDO ###
    echo ""
    echo -e "\e[32;1m _______________________________________________________________________\e[m" | tee -a $LOG_ERROS
    echo -e "\e[32;1m `date +%x" "%X` -> USER [$SUDO_USER]: reiniciando servidor dhcp ...\e[m" | tee -a $LOG_ERROS
    # Tempo adicionado devido a dificuldade de obter o correto status devido execucao concorrente
    sleep 3
    aErro=$( statusDhcp );

    if [ "$aErro" == "1" ] || [ "$aErro" == "2" ]; then
        restauraFileHosts
    else
        echo -e "\t -> SERVIDOR PRINCIPAL REINICIADO PID:  \t[$aErro]" | tee -a $LOG_ERROS;
        echo -e "\t -> ARQUIVO DE MACS REMOVIDO" | tee -a $LOG_ERROS;

        if [[ -n "$DHCP2_IP" ]]; then        
            atualizaDhcpSecundario
        fi

    fi
    rm -r $FILE_MACS $FILE_DEBUG *.txt 2> /dev/null
}

# Restaura o arquivo de hosts gerado como bkp antes da atualizacao
function restauraFileHosts(){
    
    echo -e "\e[31;1m ATENCAO: SERVIDOR DHCP NAO FOI INICIADO CORRETAMENTE:  \e[m"
    echo -e "\e[31;1m \t ==> "$PATH_BKP$FILE_HOSTS-"$DATA SERA RESTAURADO!  \e[m"
    
    #DEBUG
    cp $PATH_DHCP$FILE_HOSTS /root/dhcp/$FILE_DEBUG
    cp $PATH_BKP$FILE_HOSTS'-'$DATA $PATH_DHCP$FILE_HOSTS
    
    service isc-dhcp-server restart 1> /dev/null 2>/dev/null

    if [ $? -eq 0 ]; then
        rm -r $1 2> /dev/null
        echo -e "\e[37;1m  SERVIDOR DHCP INICADO COM SUCESSO!  \e[m"
        exit 0
    else
        echo -e "\e[31;1m ATENCAO: FALHA AO INICIAR DHCP, VERIFIQUE MANUALMENTE!  \e[m"
    fi
}

###############################################################################
############################ FUNCOES DHCP SECUNDARIO ##########################
###############################################################################

# Sincroniza as configuracoes do dhcp principal com o secundario, reiniciando o mesmo.
function atualizaDhcpSecundario(){
        
    ping -c2 $DHCP2_IP 1> /dev/null 2> /dev/null
    
    if [ $? -ne 0 ]; then
        echo -e "\e[3;1m `date +%x" "%X` -> ATENCAO: FALHA AO ACESSAR DHCP SECUNDARIO. \e[m" | tee -a $LOG_ERROS
        exit
    fi
    
    echo -e "\e[32;1m `date +%x" "%X` -> INICIANDO ATUALIZACAO DO DHCP SECUNDARIO\e[m" | tee -a $LOG_ERROS
    local aErro=0
    # Sincroniza o arquvo mantendo permissoes, data e hora do original
    #rsync -atvp $PATH_DHCP$FILE_HOSTS -e  "ssh -p ${PORTA_SSH:}" $DHCP2_USER@$DHCP2_IP:$PATH_DHCP 2> /dev/null 1>/dev/null
    rsync -atvp $PATH_DHCP$FILE_HOSTS -e  "ssh -p ${PORTA_SSH}" $DHCP2_SSH:$PATH_DHCP 2> /dev/null 1> /dev/null

    #Verifica sincronizacao
    echo -n -e "\t -> COMPARANDO ARQUIVOS ENTRE SERVIDORES" | tee -a $LOG_ERROS
    aErro=$( comparaFileHosts )

    if [ "$aErro" == "0" ]; then
        echo -e "\t[OK]" | tee -a $LOG_ERROS #OK do comparando arquivos entre servidores
        echo -n -e "\t -> REINICIANDO SERVIDOR SECUNDARIO" | tee -a $LOG_ERROS
        aErro=$( reiniciaDhcpRemoto )
        
        if [ $aErro == "1" ]; then
            echo -e "\e[31;1m\t -> FALHA NA INICIALIZACAO: TENTANDO NOVAMENTE \e[m" | tee -a $LOG_ERROS;
            local aErro2=$( reiniciaDhcpRemoto )
            if [ $aErro2 == "1" ]; then
                echo -e "\e[31;1m\t -> ERRO: SERVIDOR SECUNDARIO PARADO - VERIFIQUE MANUALMENTE \e[m" | tee -a $LOG_ERROS;
            fi
        else
            echo -e " \t\t[OK]" | tee -a $LOG_ERROS
            aErro=`echo $aErro | tr -d [:space:]`;
            echo -e "\t -> SERVIDOR SECUNDARIO REINICIADO PID: \t[$aErro]" | tee -a $LOG_ERROS;
        fi
    elif [ "$aErro" == "2" ]; then
        echo -e "\t[\e[31;1mERRO\e[m]" | tee -a $LOG_ERROS  #OK do comparando arquivos entre servidores
        echo -e "\e[31;1m \t ...FALHA AO GERAR HASH - VERIFIQUE OS ARQUIVOS \e[m" | tee -a $LOG_ERROS;
    else
        echo -e "\t[\e[31;1mERRO\e[m]" | tee -a $LOG_ERROS #OK do comparando arquivos entre servidores
        echo -e "\e[31;1m \t ...ARQUIVO NAO SINCRONIZADO - VERIFIQUE MANUALMENTE \e[m" | tee -a $LOG_ERROS;
    fi

}

#Compara os arquivos com md5sum verificando se foram sincronizados. RETORNA:
#   0 - sincronizados | 1 - não sincronizados |  2 - hash nulo
function comparaFileHosts(){
    local aStatus=0;
    # Atribui a variavel o comando para gerar o hash
    local hashCmd=(" md5sum $PATH_DHCP$FILE_HOSTS" );

    # Obtem o hash dos arquivos local e remoto
    local hashDhcp1=`$hashCmd 2> /dev/null | cut -d' ' -f1`;
    local hashDhcp2=`ssh $DHCP2_SSH_P $hashCmd 2> /dev/null | cut -d' ' -f1`;

    if [ -z $hashDhcp1 ] || [ -z $hashDhcp2 ];then
        # Verifica se algum dos dois e nulo 
        aStatus=2;
    elif [ "$hashDhcp1" != "$hashDhcp2" ]; then
        # Compara se sao iguais desde que nao nulos
        aStatus=1;
    fi
    echo $aErro;
}

# Acessa o servidor secundario, obtem o PID do processo atual e reinicia o 
# servico, obtendo o PID do novo processo e comparando. RETORNA:
#   1 para falha na reinicializacao
#   2 para falha sendo que o servico ja estava parado antes
#   PID do processo atual em caso de sucesso
function reiniciaDhcpRemoto(){
    
    # Obtem o status do servico antes de reiniciar
    local dhcpPre_Status=`ssh $DHCP2_SSH_P service isc-dhcp-server status | grep Active | awk {' printf $2 '}`;
    
    # Reinicia o servidor remoto
    ssh $DHCP2_SSH_P service isc-dhcp-server restart 1> /dev/null  2> /dev/null;
    
    # Obtem o status do servico e o PID após reiniciar
    local dhcpPos_Status=`ssh $DHCP2_SSH_P service isc-dhcp-server status | grep Active | awk {' printf $2 '}`;
    local dhcpPos_Pid=`ssh $DHCP2_SSH_P service isc-dhcp-server status | grep PID | awk {' printf $3 '}`;

    if [ "$dhcpPos_Status" == "active" ]; then
        # Se o status é ativo, atribui o pid para ser retornado
        aErro=$dhcpPos_Pid;
    elif [ "$dhcpPre_Status" == "failed" ];then
        # o estado atual e o anterior sao dhcp parado
        aErro=2;
    fi
    echo $aErro;
}


###############################################################################
############################## FUNCOES AUXILIARES #############################
###############################################################################

# Verifica se o ip passado e valido
function ipValido(){
    local aIpValido=`echo $1 | egrep '^(((1[0-9]|[1-9]?)[0-9]|2([0-4][0-9]|5[0-5]))\.){3}((1[0-9]|[1-9]?)[0-9]|2([0-4][0-9]|5[0-5]))$'`
    if [ -z "${aIpValido}"  ]; then
        echo 0;
    else
        echo 1;
    fi
}

# Formata a saida de cada entrada do dhcp
function formataNome(){
    local a=$1
    local aNome="`printf "%25s" "$a"`";
    echo $aNome;
}

# Realiza a busca do arquivo de MACs da planilha compartilhada
function getFileMacs(){
    if [ "$SO" == "FreeBSD" ]; then
	curl "$URL_PLANILHA" -o "$FILE_MACS"  2> /dev/null
    else  
	wget -O $FILE_MACS "$URL_PLANILHA" 2> /dev/null
    fi
	# Verifica se existe e se contem conteudo
    [ $FILE_MACS ] && [ -s $FILE_MACS ] && ifArqOk=1 || ifArqOk=0 ;
    echo $ifArqOk;
}

# Retorna o PID do processo atual. Caso o DHCP esteja parado, retorna vazio
function getPidDhcp(){
    local aDhcpPid=`service isc-dhcp-server status | grep PID | cut -d':' -f2 | cut -d' ' -f2`;

    # Se o pid é vazio tenta buscar de outra porta
    [ -z "$aDhcpPid" ] && aDhcpPid=`service isc-dhcp-server status | cut -d' ' -f4`;
    echo $aDhcpPid;
}

# Obtem o PID do processo atual e reinicia o servico, obtendo o PID do novo 
# processo e comparando. RETORNA
#   0 em caso de sucesso
#   1 para falha na reinicializacao
#   2 para falha sendo que o servico ja estava parado antes
function statusDhcp(){
    local aErro=1;
    local aStatus=`service isc-dhcp-server status | grep Active | awk {' printf $2 '}`
    
    if [ "$aStatus" == "active" ]; then
        # Se o status é ativo, atribui o pid para ser retornado
        aErro=$( getPidDhcp );
    elif [ -z "$aStatus" ]; then
        # Se não retornar nada considera outra versao do sistema
        aStatus=`service isc-dhcp-server status | grep start | wc -l `
        [ $aStatus -eq 1 ] && aErro=$( getPidDhcp ); 
    fi
    echo $aErro;
}


function mnt(){
    echo -e "\e[31;1m AVISO: SCRIPT EM MANUTENCAO. USUARIO[S] LOGADO[S]:\e[m" 
    for user in `who | cut -d' ' -f1`;do
        echo -e "\t- $user"
    done
    echo -e "\e[31;1m        EXECUCAO ABORTADA \e[m"
    exit
}


###############################################################################
################################### EXECUCAO ##################################
###############################################################################

# Descomentar para colocar o script em modo de mautencao
#mnt
main $1
