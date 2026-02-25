"""Тесты для morph_server.py."""

import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = str(Path(__file__).parent.parent / "scripts" / "morph_server.py")


@pytest.fixture
def server():
    """Запускает morph_server.py как subprocess."""
    proc = subprocess.Popen(
        [sys.executable, SCRIPT],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    # Ждём сигнал готовности
    ready = proc.stdout.readline().strip()
    assert ready == "READY", f"Ожидалось 'READY', получено '{ready}'"
    yield proc
    proc.stdin.close()
    proc.wait(timeout=5)


def query(proc, word):
    """Отправляет слово серверу и возвращает ответ."""
    proc.stdin.write(word + "\n")
    proc.stdin.flush()
    return proc.stdout.readline().strip()


class TestMorphServer:
    """Тесты морфологического сервера."""

    def test_adjective_feminine_to_base(self, server):
        """Женская форма прилагательного -> мужская (словарная)."""
        assert query(server, "серая") == "серый"

    def test_adjective_neuter_to_base(self, server):
        """Средний род прилагательного -> мужской (словарный)."""
        assert query(server, "серое") == "серый"

    def test_noun_accusative_to_nominative(self, server):
        """Винительный падеж существительного -> именительный."""
        assert query(server, "машину") == "машина"

    def test_noun_genitive_plural(self, server):
        """Родительный падеж множественного числа -> именительный единственного."""
        assert query(server, "домов") == "дом"

    def test_verb_participle_to_infinitive(self, server):
        """Причастие -> инфинитив."""
        assert query(server, "бегущий") == "бежать"

    def test_verb_past_tense(self, server):
        """Прошедшее время глагола -> инфинитив."""
        assert query(server, "бежал") == "бежать"

    def test_base_form_unchanged(self, server):
        """Словарная форма возвращается без изменений."""
        assert query(server, "серый") == "серый"

    def test_unknown_word_returned_as_is(self, server):
        """Неизвестное слово возвращается без изменений."""
        assert query(server, "абракадабра") == "абракадабра"

    def test_multiple_queries_sequential(self, server):
        """Несколько запросов подряд обрабатываются корректно."""
        assert query(server, "серая") == "серый"
        assert query(server, "домов") == "дом"
        assert query(server, "бежал") == "бежать"
