Set-Item Env:TARGET_BASE_URL "https://unicheck-api-qr.onrender.com"
Set-Item Env:TEST_EMAIL "felipe.garcia@upc.edu.co"
Set-Item Env:TEST_PASSWORD "password123"
Set-Item Env:TEACHER_EMAIL "andres.salazar@profes.upc.edu.co"
Set-Item Env:TEACHER_PASSWORD "password123"

Write-Host "Entorno k6 configurado:" -ForegroundColor Green
Write-Host " TARGET_BASE_URL = $Env:TARGET_BASE_URL"
Write-Host " TEST_EMAIL      = $Env:TEST_EMAIL"
Write-Host " TEACHER_EMAIL   = $Env:TEACHER_EMAIL"
