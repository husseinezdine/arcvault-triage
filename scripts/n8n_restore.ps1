# After a fresh n8n (owner account created in the browser first), restore everything from .\data\backup\
docker exec arcvault-n8n n8n import:credentials --input=/data/backup/credentials.json
docker exec arcvault-n8n n8n import:workflow --input=/data/backup/workflows.json
docker compose restart n8n
Write-Host "Restored. Open http://localhost:5678, open the workflow, check it is Active."
