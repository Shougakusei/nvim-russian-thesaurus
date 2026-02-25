#!/usr/bin/env python3
"""Сервер морфологического анализа для nvim-russian-thesaurus.

Читает слова из stdin (по одному на строку), возвращает лемму (нормальную форму)
в stdout. Используется как persistent subprocess из Neovim.

Протокол:
    → stdin:  "серая\n"
    ← stdout: "серый\n"
"""

import sys

try:
    import pymorphy3
except ImportError:
    print("ОШИБКА: модуль pymorphy3 не установлен", file=sys.stderr, flush=True)
    sys.exit(1)


def main():
    """Основной цикл сервера."""
    morph = pymorphy3.MorphAnalyzer()
    print("READY", flush=True)

    for line in sys.stdin:
        word = line.strip()
        if not word:
            continue
        parsed = morph.parse(word)
        lemma = parsed[0].normal_form if parsed else word
        print(lemma, flush=True)


if __name__ == "__main__":
    main()
