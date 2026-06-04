# Tools for DCN API Specification

Utilities for validating, bundling, and generating SDKs for the  
**Decentralised Creative Network (DCN)** protocol.

The `tools/` directory contains all auxiliary scripts and configuration files  
required to maintain API consistency, perform contract linting, validate  
OpenAPI structure, and automate SDK code generation.

These tools run locally and inside CI pipelines to guarantee that all DCN  
services follow shared standards.

---

## SDK generation

`generate-sdk.py` is the shared SDK codegen entrypoint. It can:

- bundle `services/*/openapi.yaml` into one aggregate SDK OpenAPI spec
- drop CORS `OPTIONS` operations by default
- preserve generated SDK operations such as `GET`, `POST`, and `HEAD`
- invoke TypeScript or Python client generators from caller-provided paths

Example:

```bash
python tools/generate-sdk.py bundle \
  --spec-root . \
  --output generated/openapi/dcn-sdk.openapi.yaml
```
