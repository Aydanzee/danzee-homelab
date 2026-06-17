# Axiom Local v1.2 operations

Axiom Local is the private browser interface for Ollama on the homelab. Its application source is intentionally stored separately from this public infrastructure repository.

## v1.2 capabilities

The deployed v1.2 release adds:

- multiple persistent conversations;
- a Recent Chats sidebar;
- server-side conversation storage;
- cross-device chat visibility;
- rename and delete operations;
- text, code, structured-data, and selectable-text PDF uploads;
- per-chat model, mode, and answer-length settings;
- improved slow-model loading feedback;
- temporary model warm retention;
- continuation support for long answers;
- rollback protection during deployment.

## Request path

```text
Browser
  |
  v
Axiom Local :8088
  |
  v
Ollama 127.0.0.1:11434
```

Ollama remains loopback-only. The browser does not connect directly to the Ollama API.

## Model-loading behaviour

On a low-memory CPU-only host, cold model loading can take much longer than token generation. A healthy direct request may spend most of its total duration loading the model.

Operational checks:

```bash
systemctl status ollama --no-pager
curl -fsS http://127.0.0.1:11434/api/tags | python3 -m json.tool
curl -fsS http://127.0.0.1:11434/api/ps | python3 -m json.tool
curl -fsS http://127.0.0.1:8088/api/health | python3 -m json.tool
docker logs --tail 100 axiom-local
```

## File-upload boundary

The installed text models can analyse extracted text and source code. They do not provide genuine image understanding.

Supported use cases include:

- plain text;
- Markdown;
- source-code files;
- JSON, YAML, CSV, SQL, and logs;
- PDFs containing selectable text.

Scanned or image-only PDFs require OCR or a vision-capable model and should be clearly rejected rather than silently treated as empty documents.

## Public-repository boundary

Do not commit:

- the private Axiom Local application source;
- chat databases;
- uploaded user files;
- environment files;
- model credentials or service tokens;
- backups or rollback archives.

The public repository documents the infrastructure, network boundary, operational checks, and deployment posture only.
