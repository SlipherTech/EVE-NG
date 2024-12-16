# Esse script monitora determinado ip, se a conexão em 10 pings não é bem sucedida, troca de placa na NIC Team.
# Esse script tambem acompanha um arquivo .bat para sua utilização "failover.bat" para executa-lo sem precisar 
# assinar digitalmente o script via bypass, POREM É RECOMENDADO FAZER A ASSINATURA SE QUISER USAR EM PRODUÇÃO
# Configurações iniciais
$primaryInterface = "Ethernet"       # Interface física principal no NIC Team
$secondaryInterface = "Ethernet 2"   # Interface física secundária no NIC Team
$ipToPing = "172.16.31.1"            # IP que será usado para verificar a conectividade
$pingInterval = 10                   # Intervalo entre tentativas de ping (em segundos)
$maxPingFailures = 10                # Número de falhas de ping consecutivas antes de alternar interfaces

# Função para testar o ping
function Test-Ping {
    param ([string]$ip)

    # Testar o ping
    $pingResult = Test-Connection -ComputerName $ip -Count 1 -Quiet
    return $pingResult
}

# Função para desativar uma interface de rede
function Disable-NetworkInterface {
    param ([string]$interfaceName)
    Write-Host "Desabilitando a interface $interfaceName..."
    Get-NetAdapter -Name $interfaceName | Disable-NetAdapter -Confirm:$false
}

# Função para ativar uma interface de rede
function Enable-NetworkInterface {
    param ([string]$interfaceName)
    Write-Host "Habilitando a interface $interfaceName..."
    Get-NetAdapter -Name $interfaceName | Enable-NetAdapter -Confirm:$false
}

# Função para alternar entre as interfaces
function Switch-Interfaces {
    param ([string]$activeInterface, [string]$standbyInterface)

    Write-Host "Falha de ping. Alternando para $standbyInterface..."
    Disable-NetworkInterface -interfaceName $activeInterface
    Enable-NetworkInterface -interfaceName $standbyInterface

    # Aguardar 10 segundos para garantir que a interface está completamente ativa
    Start-Sleep -Seconds 10
}

# Verificar o status inicial das interfaces ao iniciar o script
function Initialize-Interfaces {
    $primaryStatus = (Get-NetAdapter -Name $primaryInterface).Status
    $secondaryStatus = (Get-NetAdapter -Name $secondaryInterface).Status

    if ($primaryStatus -ne 'Up' -and $secondaryStatus -ne 'Up') {
        Write-Host "Nenhuma interface está ativa. Ativando a interface $primaryInterface."
        Enable-NetworkInterface -interfaceName $primaryInterface
        $currentPrimary = $primaryInterface
    }
    elseif ($secondaryStatus -eq 'Up') {
        Write-Host "A interface $secondaryInterface está ativa. Utilizando $secondaryInterface."
        $currentPrimary = $secondaryInterface
    }
    else {
        Write-Host "A interface $primaryInterface está ativa. Utilizando $primaryInterface."
        $currentPrimary = $primaryInterface
    }

    return $currentPrimary
}

# Função principal de monitoramento
function Monitor-Network {
    $failedPingCount = 0       # Contador de falhas de ping consecutivas
    $currentPrimary = Initialize-Interfaces  # Verifica qual interface está ativa no início

    while ($true) {
        # Testar o ping para o endereço IP
        $pingSuccess = Test-Ping -ip $ipToPing

        if ($pingSuccess) {
            Write-Host "Ping bem-sucedido para $ipToPing pela interface $currentPrimary."

            # Resetar o contador de falhas de ping
            $failedPingCount = 0

            # Certifique-se de que a interface standby está desativada
            $standbyInterface = if ($currentPrimary -eq $primaryInterface) { $secondaryInterface } else { $primaryInterface }
            if ((Get-NetAdapter -Name $standbyInterface).Status -eq 'Up') {
                Write-Host "Desativando a interface standby ($standbyInterface)."
                Disable-NetworkInterface -interfaceName $standbyInterface
            }
        }
        else {
            $failedPingCount++
            Write-Host "Falha no ping para $ipToPing. Contador de falhas: $failedPingCount."

            # Se o número de falhas de ping atingir o limite, alternar as interfaces
            if ($failedPingCount -ge $maxPingFailures) {
                Write-Host "Falha de ping atingiu $maxPingFailures. Alternando interfaces."

                # Alternar a interface ativa
                if ($currentPrimary -eq $primaryInterface) {
                    Switch-Interfaces -activeInterface $primaryInterface -standbyInterface $secondaryInterface
                    $currentPrimary = $secondaryInterface
                }
                else {
                    Switch-Interfaces -activeInterface $secondaryInterface -standbyInterface $primaryInterface
                    $currentPrimary = $primaryInterface
                }

                # Resetar o contador de falhas após alternar as interfaces
                $failedPingCount = 0
            }

            # Mostrar mensagem de espera apenas se o ping falhar
            Write-Host "Aguardando $pingInterval segundos antes do próximo ping."
        }

        # Verificar novamente após o intervalo
        Start-Sleep -Seconds $pingInterval
    }
}

# Iniciar o monitoramento da rede
Monitor-Network
