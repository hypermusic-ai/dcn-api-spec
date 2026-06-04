#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Union

import yaml


Json = Union[Dict[str, Any], List[Any], str, int, float, bool, None]
HttpMethods = {"get", "put", "post", "delete", "options", "head", "patch", "trace"}


class SpecBundler:
    def __init__(self, spec_root: Path) -> None:
        self.spec_root = spec_root.resolve()
        self._documents: dict[Path, dict[str, Any]] = {}
        self._schema_components: dict[str, dict[str, Any]] = {}
        self._security_components: dict[str, dict[str, Any]] = {}
        self._component_sources: dict[tuple[str, str], Path] = {}

    def bundle(self, *, title: str, version: str, drop_options: bool) -> dict[str, Any]:
        service_specs = self._service_specs()
        if not service_specs:
            raise RuntimeError(f"No service specs found under {self.spec_root / 'services'}")

        first = self._load(service_specs[0])
        bundled: dict[str, Any] = {
            "openapi": "3.0.3",
            "info": {"title": title, "version": version},
            "servers": first.get("servers", []),
            "security": [],
            "tags": [],
            "paths": {},
            "components": {"securitySchemes": {}, "schemas": {}},
        }

        seen_tags: set[str] = set()
        for spec_path in service_specs:
            doc = self._load(spec_path)
            for tag in doc.get("tags", []):
                name = tag.get("name")
                if isinstance(name, str) and name not in seen_tags:
                    bundled["tags"].append(copy.deepcopy(tag))
                    seen_tags.add(name)

            for path, path_item in sorted((doc.get("paths") or {}).items()):
                if not isinstance(path_item, dict):
                    continue
                resolved_path_item = self._resolve_node(path_item, spec_path)
                if drop_options:
                    resolved_path_item = {
                        key: value
                        for key, value in resolved_path_item.items()
                        if key.lower() != "options"
                    }
                if not any(key.lower() in HttpMethods for key in resolved_path_item):
                    continue
                if path in bundled["paths"]:
                    raise RuntimeError(f"Duplicate path in service specs: {path}")
                bundled["paths"][path] = resolved_path_item

        bundled["components"]["securitySchemes"] = dict(sorted(self._security_components.items()))
        bundled["components"]["schemas"] = dict(sorted(self._schema_components.items()))
        if not bundled["components"]["securitySchemes"]:
            del bundled["components"]["securitySchemes"]
        if not bundled["components"]["schemas"]:
            del bundled["components"]["schemas"]
        if not bundled["components"]:
            del bundled["components"]

        return bundled

    def _service_specs(self) -> list[Path]:
        services_dir = self.spec_root / "services"
        return sorted(path for path in services_dir.glob("*/openapi.yaml") if path.is_file())

    def _load(self, path: Path) -> dict[str, Any]:
        resolved = path.resolve()
        if resolved not in self._documents:
            with resolved.open("r", encoding="utf-8") as file:
                data = yaml.safe_load(file) or {}
            if not isinstance(data, dict):
                raise RuntimeError(f"OpenAPI document is not an object: {resolved}")
            self._documents[resolved] = data
        return self._documents[resolved]

    def _resolve_node(self, node: Any, current_file: Path) -> Any:
        if isinstance(node, list):
            return [self._resolve_node(item, current_file) for item in node]
        if not isinstance(node, dict):
            return copy.deepcopy(node)

        ref = node.get("$ref")
        if isinstance(ref, str):
            return self._resolve_ref(ref, current_file)

        return {
            key: self._resolve_node(value, current_file)
            for key, value in node.items()
        }

    def _resolve_ref(self, ref: str, current_file: Path) -> dict[str, str] | Any:
        ref_file, pointer = self._split_ref(ref, current_file)
        target_doc = self._load(ref_file)
        target = self._pointer(target_doc, pointer)

        if self._is_security_ref(pointer):
            name = pointer.rsplit("/", 1)[-1]
            self._security_components[name] = self._resolve_node(target, ref_file)
            self._component_sources[("security", name)] = ref_file
            return {"$ref": f"#/components/securitySchemes/{name}"}

        if self._is_schema_file(ref_file):
            name = self._schema_name(target, ref_file)
            if name not in self._schema_components:
                self._component_sources[("schema", name)] = ref_file
                self._schema_components[name] = self._resolve_node(target, ref_file)
            return {"$ref": f"#/components/schemas/{name}"}

        return self._resolve_node(target, ref_file)

    def _split_ref(self, ref: str, current_file: Path) -> tuple[Path, str]:
        file_part, _, pointer = ref.partition("#")
        ref_file = current_file.resolve() if not file_part else (current_file.parent / file_part).resolve()
        return ref_file, pointer or ""

    @staticmethod
    def _pointer(document: dict[str, Any], pointer: str) -> Any:
        if not pointer:
            return document
        if not pointer.startswith("/"):
            raise RuntimeError(f"Only JSON pointer refs are supported: #{pointer}")
        current: Any = document
        for raw_part in pointer.lstrip("/").split("/"):
            part = raw_part.replace("~1", "/").replace("~0", "~")
            if not isinstance(current, dict) or part not in current:
                raise RuntimeError(f"Invalid JSON pointer: #{pointer}")
            current = current[part]
        return current

    @staticmethod
    def _is_security_ref(pointer: str) -> bool:
        return pointer.startswith("/components/securitySchemes/")

    def _is_schema_file(self, path: Path) -> bool:
        try:
            relative = path.resolve().relative_to(self.spec_root)
        except ValueError:
            return False
        parts = relative.parts
        return "schemas" in parts and path.suffix in {".yaml", ".yml", ".json"}

    @staticmethod
    def _schema_name(schema: Any, path: Path) -> str:
        if isinstance(schema, dict) and isinstance(schema.get("title"), str):
            return SpecBundler._pascal(schema["title"])
        return SpecBundler._pascal(path.stem)

    @staticmethod
    def _pascal(value: str) -> str:
        chars: list[str] = []
        upper_next = True
        for char in value:
            if char.isalnum():
                chars.append(char.upper() if upper_next else char)
                upper_next = False
            else:
                upper_next = True
        return "".join(chars) or "Schema"


def write_yaml(path: Path, data: Json) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as file:
        yaml.safe_dump(data, file, sort_keys=False, allow_unicode=False)


def run(command: list[str], *, cwd: Path | None = None) -> None:
    print("+", " ".join(command), flush=True)
    subprocess.check_call(command, cwd=str(cwd) if cwd is not None else None)


def bundle_command(args: argparse.Namespace) -> int:
    spec_root = Path(args.spec_root)
    if not (spec_root / "services").is_dir():
        raise RuntimeError(
            f"Missing dcn-api-spec services at {spec_root}. "
            "Run: git submodule update --init --recursive submodules/dcn-api-spec"
        )
    bundled = SpecBundler(spec_root).bundle(
        title=args.title,
        version=args.version,
        drop_options=not args.keep_options,
    )
    write_yaml(Path(args.output), bundled)
    print(f"Bundled OpenAPI spec -> {args.output}")
    return 0


def generate_command(args: argparse.Namespace) -> int:
    spec_output = Path(args.spec_output)
    bundle_command(args)

    language = args.language
    output_dir = Path(args.output_dir)
    output_dir.parent.mkdir(parents=True, exist_ok=True)

    if language == "typescript":
        generator = Path(args.generator_bin) if args.generator_bin else shutil.which("openapi")
        if generator is None or not Path(generator).exists():
            raise RuntimeError("TypeScript generator not found. Pass --generator-bin or install openapi-typescript-codegen.")
        run([
            str(generator),
            "--input",
            str(spec_output),
            "--output",
            str(output_dir),
            "--client",
            "fetch",
            "--useUnionTypes",
            "--exportSchemas",
            "true",
            "--postfixServices",
            "Api",
            "--name",
            args.client_name,
        ])
        return 0

    if language == "python":
        command = [
            sys.executable,
            "-m",
            "openapi_python_client",
            "generate",
            "--path",
            str(spec_output),
            "--output-path",
            str(output_dir),
            "--overwrite",
        ]
        config = {
            "project_name_override": args.python_project_name,
            "package_name_override": args.python_package_name,
        }
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".json", delete=False) as file:
            json.dump(config, file)
            config_path = Path(file.name)
        try:
            run([*command, "--config", str(config_path)])
        finally:
            config_path.unlink(missing_ok=True)
        return 0

    raise RuntimeError(f"Unsupported language: {language}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Bundle DCN OpenAPI specs and generate SDK clients.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_bundle_args(subparser: argparse.ArgumentParser) -> None:
        subparser.add_argument("--spec-root", required=True)
        subparser.add_argument("--output", required=True)
        subparser.add_argument("--title", default="DCN Chain API")
        subparser.add_argument("--version", default="0.2.0")
        subparser.add_argument("--keep-options", action="store_true")

    bundle = subparsers.add_parser("bundle")
    add_bundle_args(bundle)
    bundle.set_defaults(func=bundle_command)

    generate = subparsers.add_parser("generate")
    add_bundle_args(generate)
    generate.add_argument("--spec-output", required=True)
    generate.add_argument("--language", required=True, choices=["typescript", "python"])
    generate.add_argument("--output-dir", required=True)
    generate.add_argument("--generator-bin")
    generate.add_argument("--client-name", default="DcnGeneratedClient")
    generate.add_argument("--python-project-name", default="dcn_api_client")
    generate.add_argument("--python-package-name", default="dcn_api_client")
    generate.set_defaults(func=generate_command)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return int(args.func(args))
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
