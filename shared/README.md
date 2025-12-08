# Shared Schemas for DCN API Specification

Common reusable components for all DCN service contracts.

The `shared/` directory contains **canonical schema definitions** used across the  
Decentralised Creative Network (DCN). These definitions ensure that services all  
communicate using consistent data structures, error formats, metadata, and  
primitive types.

These files are imported via `$ref` from individual service OpenAPI contracts.

Every service in `services/` may reference these files.
