# Helper script to run NextAction FastAPI backend in local development
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendPath = Join-Path (Split-Path -Parent $scriptPath) "backend"

Set-Location $backendPath
& ".\.venv\Scripts\uvicorn.exe" app.main:app --reload --port 8000
