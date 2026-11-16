<#
.SYNOPSIS
  Verifica que el backend de SafeLink sea alcanzable desde un telefono Android fisico.

.DESCRIPTION
  Solo Windows (PowerShell 5.1 o 7+). Revisa, en orden: Docker, contenedor de la base,
  /health desde la PC, adb, dispositivos conectados, adb reverse y (opcional) /health
  desde el telefono. No lee ni imprime el archivo .env.
  Guia completa: docs/CONEXION_DISPOSITIVO.md

.PARAMETER Port
  Puerto de la API (el PORT de tu .env). Por omision 3000.

.PARAMETER AplicarReverse
  Si falta la regla, ejecuta `adb reverse tcp:<Port> tcp:<Port>`. Sin este parametro,
  solo muestra el comando.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/verificar-conexion.ps1 -AplicarReverse

.NOTES
  Codigo de salida: 0 si todo lo esencial esta bien; 1 si algo esencial fallo.
#>
[CmdletBinding()]
param(
  [ValidateRange(1, 65535)]
  [int]$Port = 3000,
  [switch]$AplicarReverse
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$ok = [string][char]0x2714
$mal = [string][char]0x2718
$fallos = 0

function Mostrar-Ok([string]$texto) { Write-Host "  $ok $texto" -ForegroundColor Green }
function Mostrar-Mal([string]$texto, [string]$accion) {
  $script:fallos++
  Write-Host "  $mal $texto" -ForegroundColor Red
  if ($accion) { Write-Host "      -> $accion" -ForegroundColor Yellow }
}
function Mostrar-Aviso([string]$texto) { Write-Host "  - $texto" -ForegroundColor Yellow }
function Mostrar-Titulo([string]$texto) { Write-Host ""; Write-Host $texto -ForegroundColor Cyan }

Write-Host "Verificacion de conexion SafeLink (puerto $Port)" -ForegroundColor Cyan

# 1. Docker
Mostrar-Titulo "1. Docker"
$dockerListo = $false
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Mostrar-Mal "No se encontro el comando docker." "Instala Docker Desktop y vuelve a abrir la terminal."
} else {
  $null = & docker info 2>&1
  if ($LASTEXITCODE -eq 0) {
    $dockerListo = $true
    Mostrar-Ok "Docker responde."
  } else {
    Mostrar-Mal "Docker no responde." "Abre Docker Desktop y espera a que diga 'Engine running'."
  }
}

# 2. Contenedor de la base
Mostrar-Titulo "2. Base de datos (contenedor db)"
if (-not $dockerListo) {
  Mostrar-Mal "No se puede revisar el contenedor sin Docker." ""
} else {
  # Se consulta por etiqueta de Compose: no necesita leer el .env.
  $estado = & docker ps --filter "label=com.docker.compose.service=db" --format "{{.Names}}|{{.Status}}" 2>&1 | Select-Object -First 1
  if ($LASTEXITCODE -ne 0 -or -not $estado) {
    Mostrar-Mal "No hay un contenedor db en ejecucion." "En backend/: npm run db:up"
  } else {
    $partes = ([string]$estado).Split('|')
    if ($partes[1] -match '\(healthy\)') {
      Mostrar-Ok "Contenedor $($partes[0]) healthy."
    } else {
      Mostrar-Mal "Contenedor $($partes[0]) no esta healthy ($($partes[1]))." "Espera unos segundos y repite, o revisa: docker logs $($partes[0])"
    }
  }
}

# 3. /health desde la PC
Mostrar-Titulo "3. API desde la PC"
$urlHealth = "http://127.0.0.1:$Port/health"
try {
  $r = Invoke-RestMethod -Uri $urlHealth -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
  if ($r.data.status -eq 'ok') {
    Mostrar-Ok "GET $urlHealth respondio ok."
  } else {
    Mostrar-Mal "GET $urlHealth respondio, pero sin data.status = ok." "Revisa la version de la API."
  }
} catch {
  Mostrar-Mal "GET $urlHealth no respondio." "En backend/: npm run dev (y confirma que PORT en .env sea $Port; si no, usa -Port)."
}

# 4. adb
Mostrar-Titulo "4. adb y dispositivo"
$adbListo = $false
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  Mostrar-Mal "adb no esta en el PATH." "Instala Android platform-tools y agrega su carpeta al PATH (prueba con: adb version)."
} else {
  $adbListo = $true
  Mostrar-Ok "adb encontrado."
}

$dispositivos = @()
if ($adbListo) {
  $lineas = & adb devices 2>&1
  foreach ($l in $lineas) {
    if ("$l" -match '^(\S+)\s+device\s*$') { $dispositivos += $Matches[1] }
  }
  $otros = @($lineas | Where-Object { "$_" -match '\s(unauthorized|offline)\s*$' })
  if ($dispositivos.Count -ge 1) {
    Mostrar-Ok "Dispositivos conectados: $($dispositivos.Count) ($($dispositivos -join ', '))."
    if ($dispositivos.Count -gt 1) { Mostrar-Aviso "Hay varios dispositivos: adb reverse requiere uno solo (o define ANDROID_SERIAL)." }
  } else {
    Mostrar-Mal "adb no ve ningun telefono en estado 'device'." "Activa la depuracion USB, usa un cable de datos y acepta el aviso en el telefono; si persiste: adb kill-server"
    if ($otros.Count -gt 0) { Mostrar-Aviso "Hay un dispositivo 'unauthorized' u 'offline': acepta la autorizacion en la pantalla del telefono." }
  }
}

# 5. adb reverse
Mostrar-Titulo "5. adb reverse tcp:$Port"
$comandoReverse = "adb reverse tcp:$Port tcp:$Port"
if ($dispositivos.Count -lt 1) {
  Mostrar-Mal "Sin dispositivo no se puede revisar el reverse." "Cuando conectes el telefono: $comandoReverse"
} else {
  $lista = (& adb reverse --list 2>&1) -join "`n"
  if ($lista -match "tcp:$Port\s+tcp:$Port") {
    Mostrar-Ok "La regla tcp:$Port ya existe."
  } elseif ($AplicarReverse) {
    $null = & adb reverse "tcp:$Port" "tcp:$Port" 2>&1
    if ($LASTEXITCODE -eq 0) {
      Mostrar-Ok "Regla aplicada: $comandoReverse"
    } else {
      Mostrar-Mal "No se pudo aplicar $comandoReverse." "Revisa que el telefono siga autorizado (adb devices)."
    }
  } else {
    Mostrar-Mal "Falta la regla tcp:$Port." "Ejecuta: $comandoReverse   (o vuelve a correr este script con -AplicarReverse)"
  }
}

# 6. /health desde el telefono (opcional, no cuenta como fallo)
Mostrar-Titulo "6. API desde el telefono (opcional)"
if ($dispositivos.Count -lt 1) {
  Mostrar-Aviso "Omitido: no hay dispositivo."
} else {
  $urlTel = "http://127.0.0.1:$Port/health"
  $salida = $null
  $curl = (& adb shell "command -v curl" 2>&1) -join ''
  if ($curl.Trim()) {
    $salida = (& adb shell "curl -s -m 5 $urlTel" 2>&1) -join ''
  } else {
    $wget = (& adb shell "command -v wget" 2>&1) -join ''
    if ($wget.Trim()) { $salida = (& adb shell "wget -q -T 5 -O - $urlTel" 2>&1) -join '' }
  }
  if ($null -eq $salida) {
    Mostrar-Aviso "El telefono no tiene curl ni wget; se omite la prueba automatica."
    Mostrar-Aviso "Pruebalo a mano: abre $urlTel en el navegador del telefono (debe mostrar status ok)."
  } elseif ($salida -match '"status"\s*:\s*"ok"') {
    Mostrar-Ok "El telefono alcanza $urlTel."
  } else {
    Mostrar-Aviso "El telefono no pudo leer $urlTel. Confirma la regla adb reverse y abre esa URL en su navegador."
  }
}

# Resumen
Write-Host ""
if ($fallos -eq 0) {
  Write-Host "$ok Todo lo esencial esta bien. En la app: --dart-define=API_URL=http://127.0.0.1:$Port/api/v1" -ForegroundColor Green
  exit 0
}
Write-Host "$mal Fallaron $fallos comprobacion(es) esencial(es). Revisa las acciones sugeridas arriba." -ForegroundColor Red
exit 1
