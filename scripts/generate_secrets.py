#!/usr/bin/env python3
"""Генерирует iOS/Generated/BuildSecrets.swift со встроенными ключами Gemini.

Только для ЛИЧНОЙ локальной сборки в Xcode: ключи берутся из файла .secrets/gemini_keys
(в .gitignore) или переменной GEMINI_API_KEYS. Через запятую или по одному в строке.
CI публичного репозитория ключи не передаёт — иначе их можно достать из скачанной IPA.
Такую IPA не публикуйте: маскировка XOR лишь убирает ключ из открытого текста, но не защищает его.
"""
import os
import pathlib
import secrets

root = pathlib.Path(__file__).resolve().parent.parent
raw = os.environ.get("GEMINI_API_KEYS", "")
local = root / ".secrets" / "gemini_keys"
if not raw.strip() and local.exists():
    raw = local.read_text()
if os.environ.get("CI") and raw.strip():
    raise SystemExit("Refusing to embed Gemini keys in a CI build: public artifacts would expose them.")

keys = []
for part in raw.replace(",", "\n").splitlines():
    key = part.strip()
    if key and key not in keys:
        keys.append(key)

salt = secrets.token_bytes(32)


def mask(key: str) -> str:
    data = key.encode()
    return "[" + ", ".join(str(b ^ salt[i % len(salt)]) for i, b in enumerate(data)) + "]"


encoded = ",\n        ".join(mask(k) for k in keys)
swift = f"""// Сгенерировано scripts/generate_secrets.py при сборке. Не редактировать и не коммитить.

enum BuildSecrets {{
    private static let salt: [UInt8] = [{", ".join(str(b) for b in salt)}]

    private static let encoded: [[UInt8]] = [
        {encoded}
    ]

    static var geminiKeys: [String] {{
        encoded.compactMap {{ bytes in
            let decoded = bytes.enumerated().map {{ $0.element ^ salt[$0.offset % salt.count] }}
            return String(bytes: decoded, encoding: .utf8)
        }}
    }}
}}
"""

out = root / "iOS" / "Generated" / "BuildSecrets.swift"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(swift)
print(f"Embedded Gemini keys: {len(keys)}")
