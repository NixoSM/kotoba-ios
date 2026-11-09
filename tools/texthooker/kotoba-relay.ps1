# Kotoba relay: sends each line Textractor copies to the clipboard to the iPhone.
# Use it when the iPhone can't reach Textractor's WebSocket (e.g. Windows firewall).
# On the iPhone: Kotoba > Dal PC > Collegamento > "Ricevi anche dal PC verso il telefono".
param([string]$Phone)

if (-not $Phone) {
    Write-Host "Indirizzo del telefono (in Kotoba: Dal PC > Collegamento, es. 192.168.1.34):"
    $Phone = Read-Host
}
$Phone = ($Phone.Trim() -replace '^https?://', '') -replace '/.*$', ''
if ($Phone -notmatch ':') { $Phone = "${Phone}:6678" }
$url = "http://$Phone/text"

Write-Host ""
Write-Host "Mando a $url ogni riga che Textractor copia negli appunti."
Write-Host "In Textractor deve esserci l'estensione 'Copy to Clipboard'. Chiudi questa finestra per smettere."
Write-Host ""

$last = Get-Clipboard -Raw -ErrorAction SilentlyContinue
while ($true) {
    $text = $null
    try { $text = Get-Clipboard -Raw -ErrorAction Stop } catch { }
    if ($text -and $text -ne $last) {
        $last = $text
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
            Invoke-WebRequest -Uri $url -Method Post -Body $bytes -ContentType 'text/plain; charset=utf-8' `
                -UseBasicParsing -TimeoutSec 3 | Out-Null
            Write-Host ("-> " + $text.Trim())
        } catch {
            Write-Host "Il telefono non risponde: Kotoba e' aperta sulla scheda 'Dal PC', con la ricezione dal PC accesa, sulla stessa Wi-Fi?" -ForegroundColor Yellow
        }
    }
    Start-Sleep -Milliseconds 250
}
