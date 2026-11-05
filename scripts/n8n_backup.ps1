# Export the workflow + credentials (decrypted) from the running n8n into .\data\backup\  (git-ignored)
docker exec arcvault-n8n n8n export:workflow --all --output=/data/backup/workflows.json
docker exec arcvault-n8n n8n export:credentials --all --decrypted --output=/data/backup/credentials.json
Get-ChildItem .\data\backup
